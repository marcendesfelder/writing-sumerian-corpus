CREATE TABLE compounds_pns (
  transliteration_id integer,
  compound_no integer,
  pn_id integer,
  pn_variant_no integer,
  PRIMARY KEY (transliteration_id, compound_no),
  FOREIGN KEY (transliteration_id, compound_no) REFERENCES @extschema:cuneiform_corpus@.compounds (transliteration_id, compound_no) ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY (pn_id, pn_variant_no) REFERENCES @extschema:cuneiform_pn_tables@.pn_variants (pn_id, pn_variant_no) ON DELETE CASCADE ON UPDATE CASCADE
);


CREATE OR REPLACE VIEW compounds_sign_meanings AS
WITH _ AS NOT MATERIALIZED (
  SELECT 
    corpus.*,
    compound_no, 
    word_no - min(word_no) OVER (PARTITION BY transliteration_id, compound_no) AS word_no_norm,
    CASE WHEN sign_no = min(sign_no) OVER (PARTITION BY transliteration_id, compound_no) THEN capitalized ELSE FALSE END AS capitalized
  FROM 
    @extschema:cuneiform_corpus@.corpus
    LEFT JOIN @extschema:cuneiform_corpus@.words USING (transliteration_id, word_no)
)
SELECT
  transliteration_id,
  compound_no,
  CASE WHEN bool_and(sign_id IS NOT NULL) THEN
    array_agg(
      (
        word_no_norm,
        value_id,
        sign_id,
        indicator_type,
        phonographic,
        stem,
        capitalized
      )::@extschema:cuneiform_sign_properties@.sign_meaning
      ORDER BY sign_no
    )
  ELSE 
    NULL
  END AS sign_meanings,
  max(sign_no) - max(sign_no) FILTER (WHERE stem) AS suffix_len
FROM
  _
  LEFT JOIN @extschema:cuneiform_signlist@.sign_variants USING (sign_variant_id)
GROUP BY
  transliteration_id,
  compound_no;


CREATE OR REPLACE VIEW compounds_grapheme_ids AS
SELECT 
  transliteration_id, 
  compound_no, 
  CASE WHEN bool_and(grapheme_id IS NOT NULL) THEN
    array_agg(grapheme_id ORDER BY sign_no, ordinality)
  ELSE
    NULL
  END AS grapheme_ids 
FROM 
  @extschema:cuneiform_corpus@.corpus
  LEFT JOIN @extschema:cuneiform_corpus@.words USING (transliteration_id, word_no)
  LEFT JOIN @extschema:cuneiform_signlist@.sign_variants_composition USING (sign_variant_id)
  LEFT JOIN LATERAL unnest(grapheme_ids) WITH ORDINALITY AS _(grapheme_id, ordinality) ON TRUE
GROUP BY
  transliteration_id,
  compound_no;


CREATE VIEW compounds_pns_match AS
SELECT
    DISTINCT ON (transliteration_id, compound_no)
    transliteration_id,
    compound_no,
    pns.pn_id,
    pn_variant_no
FROM
    compounds_sign_meanings a
    LEFT JOIN @extschema:cuneiform_corpus@.compounds USING (transliteration_id, compound_no)
    JOIN @extschema:cuneiform_pn_tables@.pns USING (pn_type)
    LEFT JOIN @extschema:cuneiform_pn_tables@.pn_variants b ON pns.pn_id = b.pn_id
WHERE
    (a.sign_meanings IS NULL AND b.sign_meanings IS NULL)
    OR (a.sign_meanings[1:cardinality(b.sign_meanings)] = b.sign_meanings 
      AND cardinality(a.sign_meanings) - cardinality(b.sign_meanings) <= suffix_len)
ORDER BY
  transliteration_id,
  compound_no,
  cardinality(b.sign_meanings) DESC;



CREATE OR REPLACE FUNCTION match_sign_meanings_to_compound (
    v_transliteration_id integer,
    v_compound_no integer,
    v_sign_meanings @extschema:cuneiform_sign_properties@.sign_meaning[],
    OUT sign_nos_old integer[],
    OUT sign_nos_new integer[],
    OUT sign_variant_ids_new integer[]
    )
    STABLE
    LANGUAGE SQL
BEGIN ATOMIC

WITH RECURSIVE
a AS (
  SELECT
    array_agg(sign_no ORDER BY sign_no) AS sign_nos_old,
    array_agg(glyph_id ORDER BY sign_no, glyph_no) AS glyph_ids_old,
    max(sign_no) FILTER (WHERE COALESCE(stem, true)) AS suffix_start
  FROM
    @extschema:cuneiform_corpus@.corpus
    LEFT JOIN @extschema:cuneiform_corpus@.words USING (transliteration_id, word_no)
    LEFT JOIN @extschema:cuneiform_signlist@.sign_variants_composition USING (sign_variant_id)
    LEFT JOIN LATERAL UNNEST(glyph_ids) WITH ORDINALITY AS _(glyph_id, glyph_no) ON TRUE
  WHERE
    transliteration_id = v_transliteration_id
    AND compound_no = v_compound_no
),
b AS (
  SELECT
    0 AS n,
    sign_nos_old,
    glyph_ids_old,
    suffix_start,
    ARRAY[]::integer[] AS sign_nos_new,
    ARRAY[]::integer[] AS glyph_ids_new,
    ARRAY[]::integer[] AS sign_variant_ids_new,
    0 AS nondefault_variants,
    0 AS nonstandard_variants
  FROM
    a
  UNION ALL
  SELECT
    n+1,
    sign_nos_old,
    glyph_ids_old,
    suffix_start,
    sign_nos_new || array_fill(n, ARRAY[cardinality(glyph_ids)]),
    glyph_ids_new || glyph_ids,
    sign_variant_ids_new || array_fill(sign_variant_id, ARRAY[cardinality(glyph_ids)]),
    nondefault_variants + (variant_type = 'nondefault')::integer,
    nonstandard_variants + (variant_type > 'nondefault')::integer
  FROM
    b,
    @extschema:cuneiform_signlist@.sign_variants_composition
  WHERE
    sign_id = (v_sign_meanings[n+1]).sign_id
    AND glyph_ids_old[1:cardinality(glyph_ids_new)+cardinality(glyph_ids)] = glyph_ids_new || glyph_ids
)
SELECT
  sign_nos_old[1:cardinality(glyph_ids_new)],
  sign_nos_new,
  sign_variant_ids_new
FROM
  b
WHERE
  n = cardinality(v_sign_meanings)
  AND sign_nos_old[cardinality(glyph_ids_new)] >= suffix_start
  AND sign_nos_old[cardinality(glyph_ids_new)] != COALESCE(sign_nos_old[cardinality(glyph_ids_new)+1], -1)
ORDER BY
  nonstandard_variants,
  nondefault_variants,
  sign_nos_old[cardinality(glyph_ids_new)] DESC;
END;


CREATE OR REPLACE FUNCTION match_sign_meanings_to_compound_and_segmentize (
    v_transliteration_id integer,
    v_compound_no integer,
    v_sign_meanings @extschema:cuneiform_sign_properties@.sign_meaning[],
    OUT sign_nos_old integer[],
    OUT sign_nos_new integer[],
    OUT sign_variant_ids_new integer[]
    )
    RETURNS SETOF record
    STABLE
    LANGUAGE SQL
BEGIN ATOMIC
    WITH a AS (
        SELECT
            ord,
            sign_no_old,
            sign_no_new,
            sign_variant_id_new,
            COALESCE(sign_no_old != lag(sign_no_old) OVER (w) AND sign_no_new != lag(sign_no_new) OVER (w), FALSE) AS break,
            COALESCE(sign_no_old = lag(sign_no_old) OVER (w) AND sign_no_new = lag(sign_no_new) OVER (w), FALSE) AS skip
        FROM
            match_sign_meanings_to_compound(v_transliteration_id, v_compound_no, v_sign_meanings)
            LEFT JOIN LATERAL UNNEST(sign_nos_old, sign_nos_new, sign_variant_ids_new) WITH ORDINALITY AS _(sign_no_old, sign_no_new, sign_variant_id_new, ord) ON TRUE
        WHERE
            sign_nos_old IS NOT NULL
        WINDOW
            w AS (ORDER BY ord)
    ),
    b AS (
        SELECT
            ord,
            sign_no_old,
            sign_no_new,
            sign_variant_id_new,
            sum(break::integer) OVER (ORDER BY ord) AS subgroup
        FROM
            a
        WHERE NOT skip
    )
    SELECT
        array_agg(sign_no_old ORDER BY ord),
        array_agg(sign_no_new ORDER BY ord),
        array_agg(sign_variant_id_new ORDER BY ord)
    FROM
        b
    GROUP BY
        subgroup
    ORDER BY
        subgroup;
END;



CREATE OR REPLACE FUNCTION adjust_compound_to_sign_meanings (
    v_transliteration_id integer,
    v_compound_no integer,
    v_sign_meanings @extschema:cuneiform_sign_properties@.sign_meaning[]
    )
    RETURNS SETOF @extschema:cuneiform_actions@.log_data
    VOLATILE
    LANGUAGE PLPGSQL
    AS
$BODY$
DECLARE

v_min_sign_no integer;
v_min_word_no integer;

v_sign_no_diff integer := 0;

v_sign_nos_old integer[];
v_sign_nos_new integer[];
v_sign_variant_ids_new integer[];

v_sign_nos_old_uniq integer[];
v_sign_nos_new_uniq integer[];

v_valid boolean := false;

v_i integer;
v_sign_no integer;
v_line_no integer;
v_word_no integer;
v_condition @extschema:cuneiform_sign_properties@.sign_condition;
v_crits text;
v_ligature boolean;
v_newline boolean;
v_inverted boolean;

v_split boolean;
v_row_count integer;
v_capitalizeds boolean[];

BEGIN

SELECT 
    min(sign_no), 
    min(word_no) 
INTO 
    v_min_sign_no, 
    v_min_word_no 
FROM 
    @extschema:cuneiform_corpus@.corpus 
    JOIN @extschema:cuneiform_corpus@.words USING (transliteration_id, word_no)
WHERE 
    transliteration_id = v_transliteration_id 
    AND compound_no = v_compound_no;


FOR v_sign_nos_old, v_sign_nos_new, v_sign_variant_ids_new 
    IN SELECT * FROM @extschema@.match_sign_meanings_to_compound_and_segmentize(v_transliteration_id, v_compound_no, v_sign_meanings)
LOOP

    SELECT array_agg(sign_no+v_sign_no_diff ORDER BY sign_no) INTO v_sign_nos_old FROM UNNEST(v_sign_nos_old) AS _(sign_no);
    SELECT array_agg(DISTINCT sign_no ORDER BY sign_no) INTO v_sign_nos_old_uniq FROM UNNEST(v_sign_nos_old) AS _(sign_no);
    SELECT array_agg(DISTINCT sign_no ORDER BY sign_no) INTO v_sign_nos_new_uniq FROM UNNEST(v_sign_nos_new) AS _(sign_no);

    WITH a AS (
        SELECT 
            @extschema:cuneiform_replace@.bool_and_ex_last(NOT inverted AND NOT ligature ORDER BY sign_no DESC) 
                AND bool_and(comment IS NULL)
                AND min(line_no) = max(line_no)
                AND (@extschema:cuneiform_sign_properties@.condition_agg(condition) IS NOT NULL)
                AND sum(newline::integer) <= 1
                AS valid
        FROM 
            @extschema:cuneiform_corpus@.corpus
            JOIN UNNEST(v_sign_nos_old, v_sign_nos_new) AS _(sign_no, sign_no_new) USING (sign_no)
        WHERE
            transliteration_id = v_transliteration_id
        GROUP BY
            sign_no_new
    )
    SELECT 
        bool_and(valid)
    INTO
        v_valid
    FROM 
        a;

    IF NOT v_valid THEN
        RAISE EXCEPTION 'Cannot replace compound % in %', v_compound_no, v_transliteration_id;
    END IF;
    SELECT true INTO v_valid;
    
    FOR v_i, v_sign_no, v_line_no, v_word_no, v_condition, v_crits, v_newline, v_ligature, v_inverted IN 
        WITH a AS (
            SELECT
                sign_no_new,
                min(line_no),
                min(word_no),
                @extschema:cuneiform_sign_properties@.condition_agg(condition),
                string_agg(crits, ''),
                bool_or(newline),
                bool_or(ligature),
                bool_or(inverted)
            FROM
                @extschema:cuneiform_corpus@.corpus
                JOIN UNNEST(v_sign_nos_old, v_sign_nos_new) AS _(sign_no, sign_no_new) USING (sign_no)
            WHERE
                transliteration_id = v_transliteration_id
            GROUP BY
                sign_no_new
        )
        SELECT
            row_number() OVER (ORDER BY sign_no_new),
            *
        FROM
            a
        ORDER BY
            sign_no_new

    LOOP

        IF v_i > cardinality(v_sign_nos_old_uniq) THEN
            RETURN QUERY SELECT * FROM @extschema:cuneiform_actions@.insert_entry(
                v_transliteration_id, 
                v_sign_no + v_min_sign_no,
                'corpus', 
                'sign_no', 
                (
                    v_transliteration_id, 
                    v_sign_no + v_min_sign_no,
                    v_line_no,
                    v_word_no, 
                    (v_sign_meanings[v_sign_no+1]).value_id,
                    v_sign_variant_ids_new[v_i],
                    NULL,
                    CASE WHEN (v_sign_meanings[v_sign_no+1]).value_id IS NULL THEN 'sign' ELSE 'value' END,
                    (v_sign_meanings[v_sign_no+1]).indicator_type,
                    (v_sign_meanings[v_sign_no+1]).phonographic,
                    (v_sign_meanings[v_sign_no+1]).stem,
                    v_condition,
                    v_crits,
                    NULL,
                    v_newline,
                    v_inverted,
                    v_ligature
                )::@extschema:cuneiform_corpus@.corpus,
                '@extschema:cuneiform_corpus@');
            SELECT v_sign_no_diff+1 INTO v_sign_no_diff;
        ELSE
            RETURN QUERY SELECT * FROM @extschema:cuneiform_actions@.update_entry(
              v_transliteration_id, 
              v_sign_no + v_min_sign_no, 
              'corpus', 
              'sign_no', 
              (
                v_transliteration_id, 
                v_sign_no + v_min_sign_no,
                v_line_no,
                v_word_no,
                (v_sign_meanings[v_sign_no+1]).value_id,
                v_sign_variant_ids_new[v_i],
                NULL,
                CASE WHEN (v_sign_meanings[v_sign_no+1]).value_id IS NULL THEN 'sign' ELSE 'value' END,
                (v_sign_meanings[v_sign_no+1]).indicator_type,
                (v_sign_meanings[v_sign_no+1]).phonographic,
                (v_sign_meanings[v_sign_no+1]).stem,
                v_condition,
                v_crits,
                NULL,
                v_newline,
                v_inverted,
                v_ligature
              )::@extschema:cuneiform_corpus@.corpus,
              '@extschema:cuneiform_corpus@');
        END IF;
    END LOOP;

    FOR v_sign_no IN SELECT * FROM UNNEST(v_sign_nos_old_uniq[cardinality(v_sign_nos_new_uniq)+1:]) ORDER BY unnest DESC LOOP
        RETURN QUERY SELECT * FROM @extschema:cuneiform_actions@.delete_entry (v_transliteration_id, v_sign_no, 'corpus', 'sign_no', '@extschema:cuneiform_corpus@');
        SELECT v_sign_no_diff-1 INTO v_sign_no_diff;
    END LOOP;

END LOOP;

IF NOT v_valid THEN
  RAISE EXCEPTION 'Cannot replace compound % in %', v_compound_no, v_transliteration_id;
END IF;

FOR v_word_no IN
      SELECT word_no FROM (
        SELECT word_no FROM @extschema:cuneiform_corpus@.words WHERE transliteration_id = v_transliteration_id AND compound_no = v_compound_no
        EXCEPT SELECT word_no FROM @extschema:cuneiform_corpus@.corpus WHERE transliteration_id = v_transliteration_id) _
      ORDER BY word_no DESC
    LOOP
    RETURN QUERY SELECT * FROM @extschema:cuneiform_actions@.shift_key_col(v_transliteration_id, v_word_no+1, 'corpus', 'word_no', -1, '@extschema:cuneiform_corpus@');
    RETURN QUERY SELECT * FROM @extschema:cuneiform_actions@.delete_entry(v_transliteration_id, v_word_no, 'words', 'word_no', '@extschema:cuneiform_corpus@');
END LOOP;
    
SELECT array_agg(capitalized ORDER BY word_no) INTO v_capitalizeds FROM (SELECT word_no, bool_or(capitalized) AS capitalized FROM UNNEST(v_sign_meanings) GROUP BY word_no) _;


LOOP
    SELECT 
        sign_no-1,
        a.word_no+v_min_word_no-1,
        a.word_no+v_min_word_no > b.word_no
    INTO
        v_sign_no,
        v_word_no,
        v_split
    FROM 
        @extschema:cuneiform_corpus@.corpus b 
        JOIN UNNEST(v_sign_meanings) WITH ORDINALITY a ON ordinality+v_min_sign_no-1 = sign_no
    WHERE 
        transliteration_id = v_transliteration_id
        AND a.word_no+v_min_word_no != b.word_no
    ORDER BY sign_no LIMIT 1;

    GET DIAGNOSTICS v_row_count = ROW_COUNT;
    EXIT WHEN v_row_count = 0;

    IF v_split THEN
        RETURN QUERY SELECT * FROM
                @extschema:cuneiform_actions@.split_entry(
                    v_transliteration_id, 
                    v_sign_no, 
                    'corpus', 
                    'sign_no',
                    'words', 
                    'word_no', 
                    (v_transliteration_id, v_word_no, v_compound_no, v_capitalizeds[v_word_no-v_min_word_no+1])::@extschema:cuneiform_corpus@.words, 
                    '@extschema:cuneiform_corpus@');
    ELSE
        RETURN QUERY SELECT * FROM @extschema:cuneiform_actions@.merge_entries(v_transliteration_id, v_sign_no, 'words', 'word_no', 'corpus', 'sign_no', '@extschema:cuneiform_corpus@');
    END IF;
END LOOP;

FOR v_word_no IN 
    SELECT
        word_no 
    FROM 
        @extschema:cuneiform_corpus@.words 
    WHERE 
        capitalized != v_capitalizeds[word_no-v_min_word_no+1] 
        AND transliteration_id = v_transliteration_id 
        AND compound_no = v_compound_no
    LOOP

    RETURN QUERY SELECT * FROM @extschema:cuneiform_actions@.update_entry(
      v_transliteration_id, 
      v_word_no, 
      'words', 
      'word_no', 
      (
        v_transliteration_id, 
        v_word_no,
        v_compound_no, 
        v_capitalizeds[v_word_no-v_min_word_no+1]
      )::@extschema:cuneiform_corpus@.words, 
      '@extschema:cuneiform_corpus@');

END LOOP;

RETURN;
END;
$BODY$;



CREATE OR REPLACE PROCEDURE adjust_pn_in_corpus (
    v_pn_id integer,
    v_user_id integer,
    v_internal boolean DEFAULT true
    )
    LANGUAGE PLPGSQL
AS $BODY$
DECLARE

v_transliteration_id integer;
v_compound_no integer;
v_sign_meanings @extschema:cuneiform_sign_properties@.sign_meaning[];
v_edit_no integer;
v_changes boolean;

BEGIN

FOR v_transliteration_id, v_compound_no, v_sign_meanings IN 
  SELECT 
    transliteration_id, 
    compound_no, 
    sign_meanings 
  FROM 
    @extschema@.compounds_pns
    JOIN @extschema:cuneiform_pn_tables@.pn_variants USING (pn_id, pn_variant_no)
  WHERE pn_id = v_pn_id
LOOP

  BEGIN
    SELECT COALESCE(max(edit_no)+1, 0) INTO v_edit_no FROM @extschema:cuneiform_log_tables@.edits WHERE transliteration_id = v_transliteration_id;

    INSERT INTO @extschema:cuneiform_log_tables@.edits
    SELECT 
        v_transliteration_id, 
        v_edit_no,
        CURRENT_TIMESTAMP, 
        v_user_id,
        v_internal;

    INSERT INTO @extschema:cuneiform_log_tables@.edit_log 
    SELECT
        v_transliteration_id,
        v_edit_no,
        ordinality,
        entry_no,
        key_col,
        target,
        action,
        val,
        val_old
    FROM
        @extschema@.adjust_compound_to_sign_meanings(v_transliteration_id, v_compound_no, v_sign_meanings) WITH ORDINALITY;

    SELECT count(*) > 0 INTO v_changes FROM @extschema:cuneiform_log_tables@.edit_log WHERE transliteration_id = v_transliteration_id AND edit_no = v_edit_no;
    IF NOT v_changes THEN
        DELETE FROM @extschema:cuneiform_log_tables@.edits WHERE transliteration_id = v_transliteration_id AND edit_no = v_edit_no;
    ELSE
      RAISE NOTICE 'Replaced compound % in %', v_compound_no, v_transliteration_id;
    END IF;
  EXCEPTION
    WHEN OTHERS THEN RAISE NOTICE 'Warning: Cannot replace compound % in %', v_compound_no, v_transliteration_id;
  END;

END LOOP;

END;
$BODY$;