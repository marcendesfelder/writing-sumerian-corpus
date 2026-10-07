CREATE TYPE levenshtein_op AS ENUM ('NONE', 'INSERT', 'DELETE', 'UPDATE');
CREATE TYPE wagner_fischer_op AS (op levenshtein_op, pos integer);

CREATE OR REPLACE FUNCTION levenshtein (
    s anyarray,
    t anyarray,
    OUT v_cost integer,
    OUT v_ops wagner_fischer_op[])
    LANGUAGE PLPGSQL

    COST 100
    STABLE 
AS $BODY$
DECLARE

    d integer[][] := array_fill(0, ARRAY[cardinality(s)+1, cardinality(t)+1]);
    o @extschema@.levenshtein_op[][] := array_fill('NONE'::@extschema@.levenshtein_op, ARRAY[cardinality(s)+1, cardinality(t)+1]);
    op @extschema@.levenshtein_op;

    k integer := cardinality(s)+1;
    l integer := cardinality(t)+1;

BEGIN
    FOR i IN 1..cardinality(s)+1 LOOP
        d[i][1] = i-1;
    END LOOP;
    FOR i IN 1..cardinality(t)+1 LOOP
        d[1][i] = i-1;
    END LOOP;

    FOR j IN 2..cardinality(t)+1 LOOP
        FOR i IN 2..cardinality(s)+1 LOOP
            op = 'NONE';
            v_cost = d[i-1][j-1];
            IF s[i-1] != t[j-1] THEN
                v_cost = v_cost+1;
                op = 'UPDATE';
            END IF;

            IF v_cost > d[i-1][j] + 1 THEN
                v_cost = d[i-1][j] + 1;
                op = 'DELETE';
            ELSIF v_cost > d[i][j-1] + 1 THEN
                v_cost = d[i][j-1] + 1;
                op = 'INSERT';
            END IF;

            d[i][j] = v_cost;
            o[i][j] = op;
        END LOOP;
    END LOOP;

    v_ops = ARRAY[]::@extschema@.wagner_fischer_op[];

    WHILE k != 1 AND l != 1 LOOP
        IF o[k][l] = 'DELETE' THEN
            v_ops = ROW('DELETE', l)::@extschema@.wagner_fischer_op||v_ops;
            k = k-1;
        ELSIF o[k][l] = 'INSERT' THEN
            v_ops = ROW('INSERT', l-1)::@extschema@.wagner_fischer_op||v_ops;
            l = l-1;
        ELSIF o[k][l] = 'UPDATE' THEN
            v_ops = ROW('UPDATE', l-1)::@extschema@.wagner_fischer_op||v_ops;
            k = k-1;
            l = l-1;
        ELSE
            k = k-1;
            l = l-1; 
        END IF;
    END LOOP;

    FOR i IN 1..k-1 LOOP
        v_ops = ROW('DELETE', 1)::@extschema@.wagner_fischer_op||v_ops;
    END LOOP;
    FOR j IN 1..l-1 LOOP
        v_ops = ROW('INSERT', 1)::@extschema@.wagner_fischer_op||v_ops;
    END LOOP;

    v_cost = d[array_length(s,1)+1][array_length(t,1)+1];
END;

$BODY$;


CREATE OR REPLACE FUNCTION update_all_entries (
    v_transliteration_id integer,
    v_target text,
    v_key_col text,
    v_source_schema text, 
    v_target_schema text
  )
  RETURNS SETOF log_data
  VOLATILE
  LANGUAGE PLPGSQL
AS $BODY$
DECLARE

  v_entry_no integer;
  v_row record;

BEGIN

  FOR v_row IN EXECUTE format($$
    SELECT 
      *
    FROM 
      %3$I.%2$I
    WHERE 
      transliteration_id = %1$s
    $$,
    v_transliteration_id, v_target, v_source_schema)
  LOOP

    v_entry_no := (to_jsonb(v_row) ->> v_key_col)::integer;
    RETURN QUERY SELECT * FROM @extschema:cuneiform_actions@.update_entry(v_transliteration_id, v_entry_no, v_target, v_key_col, v_row, v_target_schema);

  END LOOP;

  RETURN;

END;
$BODY$;


CREATE OR REPLACE FUNCTION split_merge_all_entries (
    v_transliteration_id integer,
    v_target text,
    v_child_target text,
    v_key_col text,
    v_child_key_col text,
    v_columns text[],
    v_special_col boolean[],
    v_source_schema text, 
    v_target_schema text
  )
  RETURNS SETOF log_data
  VOLATILE
  LANGUAGE PLPGSQL
AS $BODY$
DECLARE

  v_rec             record;
  v_entry_no        integer;
  v_child_entry_no  integer;
  v_split           boolean;

  v_row_count       integer;

  v_col             text;
  v_cols_t          text[] := array[]::text[];
  i               integer;    

BEGIN

  FOR i IN 1..array_length(v_columns, 1) LOOP
    IF v_special_col[i] THEN
      v_cols_t = v_cols_t || ('b.' || quote_ident(v_columns[i]));
    ELSE
      v_cols_t = v_cols_t || ('a.' || quote_ident(v_columns[i]));
    END IF;
  END LOOP;

  LOOP
    EXECUTE format($$
      SELECT 
        %1$I-1,
        a.%2$I,
        a.%2$I > b.%2$I
      FROM 
        %6$I.%3$I a 
        JOIN %5$I.%3$I b USING (transliteration_id, %1$I)
      WHERE 
        a.transliteration_id = %4$s
        AND a.%2$I != b.%2$I
      ORDER BY %1$I LIMIT 1
      $$,
      v_child_key_col,
      v_key_col,
      v_child_target,
      v_transliteration_id,
      v_target_schema,
      v_source_schema)
    INTO
      v_child_entry_no,
      v_entry_no,
      v_split;

    GET DIAGNOSTICS v_row_count = ROW_COUNT;
    EXIT WHEN v_row_count = 0;

    IF v_split THEN
      EXECUTE format($$
        SELECT 
          a.transliteration_id,
          a.%3$I,
          %5$s
        FROM 
          %7$s.%1$I a
          LEFT JOIN %6$s.%1$I b ON a.transliteration_id = b.transliteration_id AND b.%3$I = %4$s-1
        WHERE
          a.transliteration_id = %2$s 
          AND a.%3$I = %4$s-1
        $$,
        v_target,
        v_transliteration_id,
        v_key_col,
        v_entry_no,
        array_to_string(v_cols_t, ','),
        v_target_schema,
        v_source_schema)
      INTO STRICT v_rec;
      RETURN QUERY SELECT * FROM @extschema:cuneiform_actions@.split_entry(v_transliteration_id, v_child_entry_no, v_child_target, v_child_key_col, v_target, v_key_col, v_rec, v_target_schema);
    ELSE
      RETURN QUERY SELECT * FROM @extschema:cuneiform_actions@.merge_entries(v_transliteration_id, v_entry_no, v_target, v_key_col, v_child_target, v_child_key_col, v_target_schema);
    END IF;
  END LOOP;

END;
$BODY$;


CREATE OR REPLACE FUNCTION align_sections (
    v_transliteration_id integer,
    v_source_schema text, 
    v_target_schema text
  )
  RETURNS SETOF log_data
  VOLATILE
  LANGUAGE PLPGSQL
AS $BODY$
DECLARE

  v_max_section_no_target integer;
  v_compound_no integer;
  v_section_no_diff integer;
  v_row_count integer;

BEGIN

  EXECUTE format($$
    SELECT COALESCE(max(section_no), -1) FROM %2$I.sections WHERE transliteration_id = %1$s
    $$,
    v_transliteration_id,
    v_target_schema)
  INTO v_max_section_no_target;

  RETURN QUERY EXECUTE format($$
    SELECT (insert_entry).* FROM (
      SELECT 
        @extschema:cuneiform_actions@.insert_entry(
          transliteration_id, 
          section_no, 
          'sections', 
          'section_no', 
          sections, 
          %2$L
        ) 
      FROM 
        %3$I.sections 
      WHERE 
        transliteration_id = %1$s
        AND section_no > %4$s) _
    $$,
    v_transliteration_id,
    v_target_schema,
    v_source_schema,
    v_max_section_no_target);

  LOOP
    EXECUTE format($$
      SELECT 
        compound_no,
        b.section_no - a.section_no
      FROM 
        %2$I.compounds a 
        JOIN %3$I.compounds b USING (transliteration_id, compound_no)
      WHERE 
        a.transliteration_id = %1$s
        AND a.section_no != b.section_no
      ORDER BY compound_no LIMIT 1
      $$,
      v_transliteration_id,
      v_target_schema,
      v_source_schema)
    INTO
      v_compound_no,
      v_section_no_diff;

    GET DIAGNOSTICS v_row_count = ROW_COUNT;
    EXIT WHEN v_row_count = 0;

    RETURN QUERY SELECT * FROM @extschema:cuneiform_actions@.adjust_key_col(v_transliteration_id, v_compound_no, 'compounds', 'compound_no', 'section_no', v_section_no_diff, v_target_schema);

  END LOOP;
  RETURN;
END;
$BODY$;


CREATE OR REPLACE FUNCTION delete_empty_entries (
    v_transliteration_id integer,
    v_target text,
    v_child_target text,
    v_key_col text,
    v_target_schema text
  )
  RETURNS SETOF log_data
  VOLATILE
  LANGUAGE PLPGSQL
AS $BODY$
DECLARE

    v_entry_no        integer;

BEGIN

  FOR v_entry_no IN
    EXECUTE format(
      $$
      SELECT %1$I FROM (
        SELECT %1$I FROM %5$I.%2$I WHERE transliteration_id = %4$s
        EXCEPT SELECT %1$I FROM %5$I.%3$I WHERE transliteration_id = %4$s) _
      ORDER BY %1$I DESC
      $$,
      v_key_col,
      v_target,
      v_child_target,
      v_transliteration_id,
      v_target_schema)
  LOOP
    RETURN QUERY SELECT * FROM @extschema:cuneiform_actions@.shift_key_col(v_transliteration_id, v_entry_no+1, v_child_target, v_key_col, -1, v_target_schema);
    RETURN QUERY SELECT * FROM @extschema:cuneiform_actions@.delete_entry(v_transliteration_id, v_entry_no, v_target, v_key_col, v_target_schema);
  END LOOP;

END;
$BODY$;


CREATE OR REPLACE FUNCTION edit (
    v_source_schema text, 
    v_target_schema text,
    v_transliteration_id integer
  )
  RETURNS SETOF log_data
  VOLATILE
  LANGUAGE PLPGSQL
AS $BODY$

DECLARE

  v_op      @extschema@.wagner_fischer_op;
  v_ops     @extschema@.wagner_fischer_op[];
  v_rec     record;
  v_col     text;

  v_word_no   integer;
  v_line_no   integer;

  v_word_columns          text[]      := '{compound_no, capitalized}';
  v_word_special_col      boolean[]   := '{t,f}';
  v_word_noupdate_col     boolean[]   := '{t,f}';
  v_compound_columns      text[]      := '{pn_type, language, section_no, compound_comment}';
  v_compound_special_col  boolean[]   := '{f,f,f,f}';
  v_compound_noupdate_col boolean[]   := '{f,f,f,f}';
  v_line_columns          text[]      := '{block_no, line, line_comment}';
  v_line_special_col      boolean[]   := '{t,f,f}';
  v_block_columns         text[]      := '{surface_no, block_type, block_data, block_comment}';
  v_block_special_col     boolean[]   := '{t,f,f,f}';
  v_surface_columns       text[]      := '{surface_type, surface_data, surface_comment}';
  v_surface_special_col   boolean[]   := '{f,f,f}';
  v_section_columns       text[]      := '{section_name, composition_id}';
  v_section_special_col   boolean[]   := '{f,f}';

BEGIN

  EXECUTE format(
    $$
    WITH
    a AS (
      SELECT 
        COALESCE(array_agg(COALESCE(value, glyphs, custom_value) ORDER BY sign_no), ARRAY[]::text[]) AS signs 
      FROM 
        %2$I.corpus
        LEFT JOIN @extschema:cuneiform_signlist@.values USING (value_id) 
        LEFT JOIN @extschema:cuneiform_signlist@.value_variants ON main_variant_id = value_variant_id
        LEFT JOIN @extschema:cuneiform_signlist@.sign_variants_composition USING (sign_variant_id)
      WHERE 
        corpus.transliteration_id = %3$s
    ),
    b AS (
      SELECT 
        COALESCE(array_agg(COALESCE(value, glyphs, custom_value) ORDER BY sign_no), ARRAY[]::text[]) AS signs 
      FROM 
        %1$I.corpus 
        LEFT JOIN @extschema:cuneiform_signlist@.values USING (value_id) 
        LEFT JOIN @extschema:cuneiform_signlist@.value_variants ON main_variant_id = value_variant_id
        LEFT JOIN @extschema:cuneiform_signlist@.sign_variants_composition USING (sign_variant_id)
      WHERE 
        corpus.transliteration_id = %3$s
    )
    SELECT 
      (@extschema@.levenshtein(a.signs, b.signs)).v_ops
    FROM a, b
    $$,
    v_source_schema,
    v_target_schema,
    v_transliteration_id)
  INTO v_ops;

  FOREACH v_op IN ARRAY v_ops LOOP
    IF (v_op).op = 'INSERT' THEN

      EXECUTE format(
        $$
        SELECT
          CASE 
            WHEN COALESCE(a.word_no = a1.word_no, TRUE) THEN
              COALESCE(b1.word_no, 0)
            ELSE
              COALESCE(b2.word_no, b1.word_no, 0)
          END,
          CASE 
            WHEN COALESCE(a.line_no = a1.line_no, TRUE) THEN
              COALESCE(b1.line_no, 0)
            ELSE
              COALESCE(b2.line_no, b1.line_no, 0)
          END
        FROM
          %2$I.corpus a
          LEFT JOIN %2$I.corpus a1 ON a.transliteration_id = a1.transliteration_id AND a1.sign_no = %1$s-2
          LEFT JOIN %3$I.corpus b1 ON a.transliteration_id = b1.transliteration_id AND b1.sign_no = %1$s-2
          LEFT JOIN %3$I.corpus b2 ON a.transliteration_id = b2.transliteration_id AND b2.sign_no = %1$s-1
        WHERE
          a.transliteration_id = %4$s AND a.sign_no = %1$s-1
        $$,
        (v_op).pos,
        v_source_schema,
        v_target_schema,
        v_transliteration_id)
      INTO
        v_word_no,
        v_line_no;

      EXECUTE format(
        $$
        SELECT 
          a.transliteration_id,
          %1$s-1,
          %5$s,
          %6$s,
          a.value_id,
          a.sign_variant_id,
          a.custom_value,
          a.type,
          a.indicator_type,
          a.phonographic,
          a.stem,
          a.condition,
          a.crits,
          a.comment,
          a.newline,
          a.inverted,
          a.ligature
        FROM 
          %2$I.corpus a
          LEFT JOIN %3$I.corpus b ON a.transliteration_id = b.transliteration_id AND b.sign_no = %1$s-2
        WHERE
          a.transliteration_id = %4$s AND a.sign_no = %1$s-1
        $$,
        (v_op).pos,
        v_source_schema,
        v_target_schema,
        v_transliteration_id,
        v_line_no,
        v_word_no)
      INTO v_rec;

      RETURN QUERY SELECT * FROM @extschema:cuneiform_actions@.insert_entry(v_transliteration_id, (v_op).pos-1, 'corpus', 'sign_no', v_rec, v_target_schema);

    ELSIF (v_op).op = 'DELETE' THEN

      RETURN QUERY SELECT * FROM @extschema:cuneiform_actions@.delete_entry(v_transliteration_id, (v_op).pos-1, 'corpus', 'sign_no', v_target_schema);

    END IF;
  END LOOP;

  RETURN QUERY SELECT * FROM @extschema@.delete_empty_entries(v_transliteration_id, 'words', 'corpus', 'word_no', v_target_schema);
  RETURN QUERY SELECT * FROM @extschema@.split_merge_all_entries(v_transliteration_id, 'words', 'corpus', 'word_no', 'sign_no', v_word_columns, v_word_special_col, v_source_schema, v_target_schema);

  RETURN QUERY SELECT * FROM @extschema@.delete_empty_entries(v_transliteration_id, 'compounds', 'words', 'compound_no', v_target_schema);
  RETURN QUERY SELECT * FROM @extschema@.split_merge_all_entries(v_transliteration_id, 'compounds', 'words', 'compound_no', 'word_no', v_compound_columns, v_compound_special_col, v_source_schema, v_target_schema);
  RETURN QUERY SELECT * FROM @extschema@.align_sections(v_transliteration_id, v_source_schema, v_target_schema);
  RETURN QUERY SELECT * FROM @extschema@.update_all_entries(v_transliteration_id, 'compounds', 'compound_no', v_source_schema, v_target_schema);
  RETURN QUERY SELECT * FROM @extschema@.delete_empty_entries(v_transliteration_id, 'sections', 'compounds', 'section_no', v_target_schema);
  
  RETURN QUERY SELECT * FROM @extschema@.delete_empty_entries(v_transliteration_id, 'lines', 'corpus', 'line_no', v_target_schema);
  RETURN QUERY SELECT * FROM @extschema@.split_merge_all_entries(v_transliteration_id, 'lines', 'corpus', 'line_no', 'sign_no', v_line_columns, v_line_special_col, v_source_schema, v_target_schema);

  RETURN QUERY SELECT * FROM @extschema@.delete_empty_entries(v_transliteration_id, 'blocks', 'lines', 'block_no', v_target_schema);
  RETURN QUERY SELECT * FROM @extschema@.split_merge_all_entries(v_transliteration_id, 'blocks', 'lines', 'block_no', 'line_no', v_block_columns, v_block_special_col, v_source_schema, v_target_schema);
  RETURN QUERY SELECT * FROM @extschema@.delete_empty_entries(v_transliteration_id, 'surfaces', 'blocks', 'surface_no', v_target_schema);
  RETURN QUERY SELECT * FROM @extschema@.split_merge_all_entries(v_transliteration_id, 'surfaces', 'blocks', 'surface_no', 'block_no', v_surface_columns, v_surface_special_col, v_source_schema, v_target_schema);
  
  RETURN QUERY SELECT * FROM @extschema@.update_all_entries(v_transliteration_id, 'corpus', 'sign_no', v_source_schema, v_target_schema);   
  RETURN QUERY SELECT * FROM @extschema@.update_all_entries(v_transliteration_id, 'words', 'word_no', v_source_schema, v_target_schema);   
  RETURN QUERY SELECT * FROM @extschema@.update_all_entries(v_transliteration_id, 'sections', 'section_no', v_source_schema, v_target_schema);
  RETURN QUERY SELECT * FROM @extschema@.update_all_entries(v_transliteration_id, 'lines', 'line_no', v_source_schema, v_target_schema);
  RETURN QUERY SELECT * FROM @extschema@.update_all_entries(v_transliteration_id, 'blocks', 'block_no', v_source_schema, v_target_schema);
  RETURN QUERY SELECT * FROM @extschema@.update_all_entries(v_transliteration_id, 'surfaces', 'surface_no', v_source_schema, v_target_schema);

  RETURN;
END;

$BODY$;