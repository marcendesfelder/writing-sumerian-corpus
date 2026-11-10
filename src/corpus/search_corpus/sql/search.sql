CREATE TABLE corpus_search (
  transliteration_id integer NOT NULL,
  sign_no integer,
  position @extschema:cuneiform_search@.cun_position,
  word_no integer,
  compound_no integer,
  line_no integer,
  value_id integer,
  sign boolean,
  meaning_id integer,
  form_id integer,
  type @extschema:cuneiform_sign_properties@.sign_type,
  indicator_type @extschema:cuneiform_sign_properties@.indicator_type,
  phonographic boolean
);

CREATE INDEX ON corpus_search (transliteration_id);
CREATE INDEX ON corpus_search (value_id) WHERE value_id IS NOT NULL;
CREATE INDEX ON corpus_search (transliteration_id, value_id) WHERE value_id IS NOT NULL;
CREATE INDEX ON corpus_search (sign, meaning_id);
CREATE INDEX ON corpus_search (transliteration_id, sign, meaning_id);
CREATE INDEX ON corpus_search (sign, form_id);
CREATE INDEX ON corpus_search (transliteration_id, sign, form_id);
CREATE INDEX corpus_search_transliteration_id_position_ix ON corpus_search (transliteration_id, position);
CLUSTER corpus_search USING corpus_search_transliteration_id_position_ix;

ALTER TABLE corpus_search ALTER COLUMN value_id SET STATISTICS 1000;
ALTER TABLE corpus_search ALTER COLUMN meaning_id SET STATISTICS 1000;
ALTER TABLE corpus_search ALTER COLUMN form_id SET STATISTICS 1000;

CREATE OR REPLACE FUNCTION corpus_search_update_marginals (
    v_transliteration_id integer
  )
  RETURNS void
  VOLATILE
  LANGUAGE SQL
  AS
$BODY$
  DELETE FROM @extschema@.corpus_search
  WHERE
    transliteration_id = v_transliteration_id
    AND sign_no IS NULL;

  INSERT INTO @extschema@.corpus_search 
  SELECT
    *
  FROM 
    @extschema@.corpus_search_view
  WHERE
    transliteration_id = v_transliteration_id
    AND sign_no IS NULL;
$BODY$;


CREATE OR REPLACE FUNCTION corpus_search_update_signs (
    v_transliteration_id integer,
    v_old_sign_nos integer[],
    v_new_sign_nos integer[]
  )
  RETURNS void
  VOLATILE
  LANGUAGE SQL
  AS
$BODY$
  DELETE FROM @extschema@.corpus_search
  WHERE
    transliteration_id = v_transliteration_id
    AND sign_no = ANY(v_old_sign_nos);

  INSERT INTO @extschema@.corpus_search
  SELECT
    *
  FROM
    @extschema@.corpus_search_view
  WHERE
    transliteration_id = v_transliteration_id
    AND sign_no = ANY(v_new_sign_nos);
$BODY$;


CREATE OR REPLACE FUNCTION corpus_search_corpus_trigger_fun ()
  RETURNS trigger
  VOLATILE
  LANGUAGE PLPGSQL
  AS
$BODY$
DECLARE

  v_old_transliteration_ids integer[];
  v_old_sign_nos            integer[];
  v_new_transliteration_ids integer[];
  v_new_sign_nos            integer[];
  v_new_valid               boolean[];

  v_transliteration_id      integer;
  v_old_sign_nos_t          integer[];
  v_new_sign_nos_t          integer[];
  v_complete                boolean;

BEGIN

  IF TG_OP = 'UPDATE' THEN
    -- only rows in which columns used by corpus_search_view have changed
    SELECT
      array_agg(transliteration_id),
      array_agg(sign_no)
    INTO
      v_old_transliteration_ids,
      v_old_sign_nos
    FROM (
      SELECT transliteration_id, sign_no, line_no, word_no, value_id, sign_variant_id, custom_value, type, indicator_type, phonographic FROM old_table
      EXCEPT ALL
      SELECT transliteration_id, sign_no, line_no, word_no, value_id, sign_variant_id, custom_value, type, indicator_type, phonographic FROM new_table
    ) _;
    SELECT
      array_agg(transliteration_id),
      array_agg(sign_no),
      array_agg(sign_no >= 0 AND line_no >= 0 AND word_no >= 0)
    INTO
      v_new_transliteration_ids,
      v_new_sign_nos,
      v_new_valid
    FROM (
      SELECT transliteration_id, sign_no, line_no, word_no, value_id, sign_variant_id, custom_value, type, indicator_type, phonographic FROM new_table
      EXCEPT ALL
      SELECT transliteration_id, sign_no, line_no, word_no, value_id, sign_variant_id, custom_value, type, indicator_type, phonographic FROM old_table
    ) _;
  ELSIF TG_OP = 'INSERT' THEN
    SELECT
      array_agg(transliteration_id),
      array_agg(sign_no),
      array_agg(sign_no >= 0 AND line_no >= 0 AND word_no >= 0)
    INTO
      v_new_transliteration_ids,
      v_new_sign_nos,
      v_new_valid
    FROM
      new_table;
  ELSE
    SELECT
      array_agg(transliteration_id),
      array_agg(sign_no)
    INTO
      v_old_transliteration_ids,
      v_old_sign_nos
    FROM
      old_table;
  END IF;

  -- marginals are only rebuilt if no rows of the transliteration are left in an intermediate state
  FOR v_transliteration_id, v_old_sign_nos_t, v_new_sign_nos_t, v_complete IN
    SELECT
      transliteration_id,
      array_agg(sign_no) FILTER (WHERE is_old),
      array_agg(sign_no) FILTER (WHERE NOT is_old AND is_valid),
      bool_and(is_valid)
    FROM (
      SELECT transliteration_id, sign_no, TRUE AS is_old, TRUE AS is_valid FROM unnest(v_old_transliteration_ids, v_old_sign_nos) AS _(transliteration_id, sign_no)
      UNION ALL
      SELECT transliteration_id, sign_no, FALSE AS is_old, is_valid FROM unnest(v_new_transliteration_ids, v_new_sign_nos, v_new_valid) AS _(transliteration_id, sign_no, is_valid)
    ) _
    GROUP BY
      transliteration_id
  LOOP
    PERFORM @extschema@.corpus_search_update_signs(v_transliteration_id, v_old_sign_nos_t, v_new_sign_nos_t);
    IF v_complete THEN
      PERFORM @extschema@.corpus_search_update_marginals(v_transliteration_id);
    END IF;
  END LOOP;

  RETURN NULL;

END;
$BODY$;


CREATE OR REPLACE FUNCTION corpus_search_corpus_truncate_trigger_fun ()
  RETURNS trigger
  VOLATILE
  LANGUAGE PLPGSQL
  AS
$BODY$
BEGIN
  TRUNCATE @extschema@.corpus_search;
  RETURN NULL;
END;
$BODY$;


CREATE OR REPLACE FUNCTION corpus_search_words_trigger_fun ()
  RETURNS trigger
  VOLATILE
  LANGUAGE PLPGSQL
  AS
$BODY$
DECLARE

  v_transliteration_ids integer[];
  v_word_nos            integer[];

  v_transliteration_id  integer;
  v_word_nos_t          integer[];
  v_row_count           integer;

BEGIN

  IF TG_OP = 'UPDATE' THEN
    -- only rows in which word_no or compound_no have changed, old and new word_nos are both affected
    SELECT
      array_agg(transliteration_id),
      array_agg(word_no)
    INTO
      v_transliteration_ids,
      v_word_nos
    FROM (
      (SELECT transliteration_id, word_no, compound_no FROM old_table
      EXCEPT ALL
      SELECT transliteration_id, word_no, compound_no FROM new_table)
      UNION ALL
      (SELECT transliteration_id, word_no, compound_no FROM new_table
      EXCEPT ALL
      SELECT transliteration_id, word_no, compound_no FROM old_table)
    ) _;
  ELSIF TG_OP = 'INSERT' THEN
    SELECT
      array_agg(transliteration_id),
      array_agg(word_no)
    INTO
      v_transliteration_ids,
      v_word_nos
    FROM
      new_table;
  ELSE
    SELECT
      array_agg(transliteration_id),
      array_agg(word_no)
    INTO
      v_transliteration_ids,
      v_word_nos
    FROM
      old_table;
  END IF;

  -- corpus_search has no entries with negative word_nos, so these can be skipped
  FOR v_transliteration_id, v_word_nos_t IN
    SELECT
      transliteration_id,
      array_agg(DISTINCT word_no)
    FROM
      unnest(v_transliteration_ids, v_word_nos) AS _(transliteration_id, word_no)
    WHERE
      word_no >= 0
    GROUP BY
      transliteration_id
  LOOP
    UPDATE @extschema@.corpus_search SET
      compound_no = (
        SELECT
          compound_no
        FROM
          @extschema:cuneiform_corpus@.words
        WHERE
          words.transliteration_id = v_transliteration_id
          AND words.word_no = corpus_search.word_no)
    WHERE
      transliteration_id = v_transliteration_id
      AND word_no = ANY(v_word_nos_t)
      AND sign_no IS NOT NULL;

    GET DIAGNOSTICS v_row_count = ROW_COUNT;
    IF v_row_count > 0 THEN
      PERFORM @extschema@.corpus_search_update_marginals(v_transliteration_id);
    END IF;
  END LOOP;

  RETURN NULL;

END;
$BODY$;


CREATE OR REPLACE FUNCTION corpus_search_sign_variants_composition_trigger_fun ()
  RETURNS trigger
  VOLATILE
  LANGUAGE PLPGSQL
  AS
$BODY$
DECLARE

  v_sign_variant_ids      integer[];

  v_transliteration_id    integer;
  v_sign_nos              integer[];

BEGIN

  -- only rows in which columns used by corpus_search_view have changed
  SELECT
    array_agg(DISTINCT sign_variant_id)
  INTO
    v_sign_variant_ids
  FROM (
    (SELECT sign_variant_id, sign_id, grapheme_ids, glyph_ids FROM old_table
    EXCEPT
    SELECT sign_variant_id, sign_id, grapheme_ids, glyph_ids FROM new_table)
    UNION ALL
    (SELECT sign_variant_id, sign_id, grapheme_ids, glyph_ids FROM new_table
    EXCEPT
    SELECT sign_variant_id, sign_id, grapheme_ids, glyph_ids FROM old_table)
  ) _;

  IF v_sign_variant_ids IS NULL THEN
    RETURN NULL;
  END IF;

  FOR v_transliteration_id, v_sign_nos IN
    SELECT
      transliteration_id,
      array_agg(sign_no)
    FROM
      @extschema:cuneiform_corpus@.corpus
    WHERE
      sign_variant_id = ANY(v_sign_variant_ids)
      AND sign_no >= 0
      AND line_no >= 0
      AND word_no >= 0
    GROUP BY
      transliteration_id
  LOOP
    PERFORM @extschema@.corpus_search_update_signs(v_transliteration_id, v_sign_nos, v_sign_nos);
  END LOOP;

  RETURN NULL;

END;
$BODY$;


CREATE OR REPLACE PROCEDURE corpus_search_create_triggers()
  LANGUAGE SQL
  AS
$BODY$
  CREATE TRIGGER corpus_search_corpus_insert_trigger
    AFTER INSERT ON @extschema:cuneiform_corpus@.corpus
    REFERENCING NEW TABLE AS new_table
    FOR EACH STATEMENT
    EXECUTE FUNCTION @extschema@.corpus_search_corpus_trigger_fun();

  CREATE TRIGGER corpus_search_corpus_update_trigger
    AFTER UPDATE ON @extschema:cuneiform_corpus@.corpus
    REFERENCING OLD TABLE AS old_table NEW TABLE AS new_table
    FOR EACH STATEMENT
    EXECUTE FUNCTION @extschema@.corpus_search_corpus_trigger_fun();

  CREATE TRIGGER corpus_search_corpus_delete_trigger
    AFTER DELETE ON @extschema:cuneiform_corpus@.corpus
    REFERENCING OLD TABLE AS old_table
    FOR EACH STATEMENT
    EXECUTE FUNCTION @extschema@.corpus_search_corpus_trigger_fun();

  CREATE TRIGGER corpus_search_corpus_truncate_trigger
    AFTER TRUNCATE ON @extschema:cuneiform_corpus@.corpus
    FOR EACH STATEMENT
    EXECUTE FUNCTION @extschema@.corpus_search_corpus_truncate_trigger_fun();

  CREATE TRIGGER corpus_search_words_insert_trigger
    AFTER INSERT ON @extschema:cuneiform_corpus@.words
    REFERENCING NEW TABLE AS new_table
    FOR EACH STATEMENT
    EXECUTE FUNCTION @extschema@.corpus_search_words_trigger_fun();

  CREATE TRIGGER corpus_search_words_update_trigger
    AFTER UPDATE ON @extschema:cuneiform_corpus@.words
    REFERENCING OLD TABLE AS old_table NEW TABLE AS new_table
    FOR EACH STATEMENT
    EXECUTE FUNCTION @extschema@.corpus_search_words_trigger_fun();

  CREATE TRIGGER corpus_search_words_delete_trigger
    AFTER DELETE ON @extschema:cuneiform_corpus@.words
    REFERENCING OLD TABLE AS old_table
    FOR EACH STATEMENT
    EXECUTE FUNCTION @extschema@.corpus_search_words_trigger_fun();

  CREATE TRIGGER corpus_search_sign_variants_composition_update_trigger
    AFTER UPDATE ON @extschema:cuneiform_signlist@.sign_variants_composition
    REFERENCING OLD TABLE AS old_table NEW TABLE AS new_table
    FOR EACH STATEMENT
    EXECUTE FUNCTION @extschema@.corpus_search_sign_variants_composition_trigger_fun();
$BODY$;

CREATE OR REPLACE PROCEDURE corpus_search_drop_triggers()
  LANGUAGE SQL
  AS
$BODY$
  DROP TRIGGER corpus_search_corpus_insert_trigger ON @extschema:cuneiform_corpus@.corpus;
  DROP TRIGGER corpus_search_corpus_update_trigger ON @extschema:cuneiform_corpus@.corpus;
  DROP TRIGGER corpus_search_corpus_delete_trigger ON @extschema:cuneiform_corpus@.corpus;
  DROP TRIGGER corpus_search_corpus_truncate_trigger ON @extschema:cuneiform_corpus@.corpus;
  DROP TRIGGER corpus_search_words_insert_trigger ON @extschema:cuneiform_corpus@.words;
  DROP TRIGGER corpus_search_words_update_trigger ON @extschema:cuneiform_corpus@.words;
  DROP TRIGGER corpus_search_words_delete_trigger ON @extschema:cuneiform_corpus@.words;
  DROP TRIGGER corpus_search_sign_variants_composition_update_trigger ON @extschema:cuneiform_signlist@.sign_variants_composition;
$BODY$;


CREATE OR REPLACE VIEW corpus_search_view AS (
WITH x AS NOT MATERIALIZED (
  SELECT
    corpus.*,
    compound_no
  FROM
    @extschema:cuneiform_corpus@.corpus
    LEFT JOIN @extschema:cuneiform_corpus@.words USING (transliteration_id, word_no)
)
SELECT * FROM (
  SELECT 
    transliteration_id,
    sign_no,
    @extschema:cuneiform_search@.cun_position(
      greatest(sign_no + 1, 0),
      a.pos::integer - 1, 
      row_number() OVER (PARTITION BY transliteration_id, sign_no ORDER BY pos DESC) = 1
      ) AS position,
    word_no,
    compound_no,
    line_no,
    NULL::integer AS value_id,
    FALSE AS sign,
    grapheme_id AS meaning_id,
    glyph_id AS form_id,
    type,
    indicator_type,
    phonographic
  FROM 
    x
    JOIN @extschema:cuneiform_signlist@.sign_variants_composition USING (sign_variant_id)
    LEFT JOIN LATERAL unnest(grapheme_ids, glyph_ids) WITH ORDINALITY a(grapheme_id, glyph_id, pos) ON TRUE
  UNION ALL
  SELECT 
    transliteration_id,
    sign_no,
    @extschema:cuneiform_search@.cun_position(
      greatest(sign_no + 1, 0),
      0, 
      TRUE) AS position,
    word_no,
    compound_no,
    line_no,
    NULL AS value_id,
    FALSE AS sign,
    NULL AS meaning_id,
    NULL AS form_id,
    type,
    indicator_type,
    phonographic
  FROM 
    x
  WHERE
    type = 'damage' AND custom_value != '…'
  UNION ALL
  SELECT
    transliteration_id,
    sign_no,
    @extschema:cuneiform_search@.cun_position(
      greatest(sign_no + 1, 0),
      0, 
      TRUE) AS position,
    word_no,
    compound_no,
    line_no,
    value_id,
    CASE WHEN type = 'sign' OR type = 'number' OR (type = 'damage' AND custom_value != '…') THEN TRUE ELSE NULL END AS sign,
    sign_id AS meaning_id,
    sign_variant_id AS form_id,
    type,
    indicator_type,
    phonographic
  FROM 
    x
    LEFT JOIN @extschema:cuneiform_signlist@.sign_variants_composition USING (sign_variant_id)
  UNION ALL
  SELECT                      -- pseudo first row
    transliteration_id,
    NULL AS sign_no,
    @extschema:cuneiform_search@.cun_position(greatest(min(sign_no), 0), 0, TRUE) AS position,
    min(word_no)-1 AS word_no,
    min(compound_no)-1 AS compound_no,
    min(line_no)-1 AS line_no,
    NULL AS value_id,
    NULL AS sign,
    NULL AS meaning_id,
    NULL AS form_id,
    NULL AS type,
    NULL AS indicator_type,
    NULL AS phonographic
  FROM 
    x
  GROUP BY 
    transliteration_id
  UNION ALL
  SELECT                      -- pseudo final row
    transliteration_id,
    NULL AS sign_no,
    @extschema:cuneiform_search@.cun_position(
      greatest(max(sign_no)+2, 0),
      0,
      TRUE) AS position,
    max(word_no)+1 AS word_no,
    max(compound_no)+1 AS compound_no,
    max(line_no)+1 AS line_no,
    NULL AS value_id,
    NULL AS sign,
    NULL AS meaning_id,
    NULL AS form_id,
    NULL AS type,
    NULL AS indicator_type,
    NULL AS phonographic
  FROM 
    x
  GROUP BY 
    transliteration_id
  UNION ALL
  SELECT                      -- placeholder row
    transliteration_id,
    NULL AS sign_no,
    NULL AS position,
    NULL AS word_no,
    NULL AS compound_no,
    NULL AS line_no,
    NULL AS value_id,
    NULL AS sign,
    NULL AS meaning_id,
    NULL AS form_id,
    NULL AS type,
    NULL AS indicator_type,
    NULL AS phonographic
  FROM 
    x
  GROUP BY 
    transliteration_id)
  a
ORDER BY transliteration_id, position);


CREATE PROCEDURE corpus_search_update_transliteration(v_transliteration_id integer)
  LANGUAGE SQL
  AS
$BODY$
  DELETE FROM @extschema@.corpus_search WHERE transliteration_id = v_transliteration_id;
  INSERT INTO @extschema@.corpus_search SELECT * FROM @extschema@.corpus_search_view WHERE transliteration_id = v_transliteration_id;
$BODY$;

CALL corpus_search_create_triggers();


CREATE TYPE search_result AS (
    transliteration_id integer,
    text_id integer,
    corpus_id integer,
    period_id integer,
    provenience_id integer,
    genre_id integer,
    sign_nos integer[],
    word_nos integer[],
    line_nos integer[],
    wildcards @extschema:cuneiform_search@.search_wildcard[]
);


CREATE OR REPLACE FUNCTION search (
    v_search_term text,
    v_period_ids integer[] DEFAULT ARRAY[]::integer[],
    v_provenience_ids integer[] DEFAULT ARRAY[]::integer[],
    v_genre_ids integer[] DEFAULT ARRAY[]::integer[]
  )
  RETURNS SETOF search_result
  LANGUAGE PLPGSQL
  COST 100 
  STABLE 
  ROWS 1000
  AS $BODY$
BEGIN
  RETURN QUERY EXECUTE 
    $$
    SELECT
        transliteration_id,
        text_id,
        corpus_id,
        period_id,
        provenience_id,
        genre_id,
        signs,
        words,
        lines,
        wildcards
    FROM ($$ || @extschema:cuneiform_search@.parse_search (v_search_term, 'corpus_search', ARRAY['transliteration_id'], '@extschema@') || $$) _
        LEFT JOIN @extschema:cuneiform_corpus@.transliterations USING (transliteration_id)
        LEFT JOIN @extschema:cuneiform_corpus@.texts USING (text_id)
    WHERE 
        (cardinality($1) = 0 OR period_id = ANY($1)) AND
        (cardinality($2) = 0 OR provenience_id = ANY($2)) AND
        (cardinality($3) = 0 OR genre_id = ANY($3))
    $$
    USING v_period_ids, v_provenience_ids, v_genre_ids;
END;
$BODY$;


CREATE OR REPLACE FUNCTION search_signs_clean (v_search_term text)
  RETURNS TABLE (
    transliteration_id integer,
    signs text,
    sign_nos integer[])
  LANGUAGE SQL
  COST 100 STABLE ROWS 1000
  AS $BODY$
  SELECT
    transliteration_id,
    (@extschema:cuneiform_serialize@.cun_agg(value, sign_no, word_no, compound_no, NULL, 0, type, indicator_type, phonographic, stem, 'intact', LANGUAGE, 
            FALSE, FALSE, FALSE, NULL, NULL, FALSE, NULL, NULL, NULL ORDER BY sign_no))[1],
    signs
  FROM (
    SELECT
      row_number() OVER (),
      transliteration_id,
      signs,
      UNNEST(signs) AS sign_no
    FROM
      @extschema@.search (v_search_term)) a
  JOIN @extschema:cuneiform_serialize_corpus@.corpus_code_clean USING (transliteration_id, sign_no)
GROUP BY
  row_number,
  signs,
  transliteration_id
ORDER BY
  transliteration_id
$BODY$;


CREATE OR REPLACE FUNCTION search_words_clean (v_search_term text)
  RETURNS TABLE (
    transliteration_id integer,
    word text)
  LANGUAGE SQL
  COST 100 STABLE ROWS 1000
  AS $BODY$
  WITH res AS (
    SELECT DISTINCT
      row_number,
      transliteration_id,
      word_no
    FROM (
      SELECT
        row_number() OVER (),
        transliteration_id,
        UNNEST(signs) AS sign_no
      FROM
        @extschema@.search (v_search_term)) a
    JOIN @extschema:cuneiform_corpus@.corpus USING (transliteration_id, sign_no)
),
found_words AS (
  SELECT
    row_number,
    transliteration_id,
    array_agg(word_no) AS word_nos
  FROM
    res
  GROUP BY
    transliteration_id,
    row_number
)
SELECT
  corpus_code_clean.transliteration_id,
  (@extschema:cuneiform_serialize@.cun_agg (value, sign_no, corpus_code_clean.word_no, compound_no, NULL, 0, type, indicator_type, phonographic, stem, 'intact', LANGUAGE, 
            FALSE, FALSE, FALSE, NULL, NULL, FALSE, NULL, NULL, NULL ORDER BY sign_no))[1]
FROM
  found_words
  JOIN @extschema:cuneiform_serialize_corpus@.corpus_code_clean ON found_words.transliteration_id = corpus_code_clean.transliteration_id
    AND word_no = ANY (word_nos)
GROUP BY
  corpus_code_clean.transliteration_id,
  row_number
ORDER BY
  corpus_code_clean.transliteration_id
$BODY$;


CREATE OR REPLACE FUNCTION search_lines (v_search_term text)
  RETURNS TABLE (
    transliteration_id integer,
    line text,
    line_no integer)
  LANGUAGE SQL
  COST 100 STABLE ROWS 1000
  AS $BODY$
  WITH found_lines AS (
    SELECT DISTINCT
      row_number,
      transliteration_id,
      line_no
    FROM (
      SELECT
        row_number() OVER (),
        transliteration_id,
        UNNEST(signs) AS sign_no
    FROM
      @extschema@.search (v_search_term)) a
    JOIN @extschema:cuneiform_corpus@.corpus USING (transliteration_id, sign_no))
SELECT
  transliteration_id,
  array_to_string(@extschema:cuneiform_serialize@.cun_agg(value, sign_no, word_no, compound_no, section_no, line_no, type, indicator_type, phonographic, stem, condition, LANGUAGE, 
      inverted, newline, ligature, crits, comment, capitalized, pn_type, section_name, compound_comment ORDER BY sign_no), '\n'),
  line_no
FROM
  found_lines
  JOIN @extschema:cuneiform_serialize_corpus@.corpus_code USING (transliteration_id, line_no)
GROUP BY
  row_number,
  transliteration_id,
  line_no
ORDER BY
  transliteration_id
$BODY$;