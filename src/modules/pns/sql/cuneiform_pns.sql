CREATE VIEW pns_serialized AS (
    SELECT
        pn_id,
        pn_variant_no,
        (@extschema:cuneiform_serialize@.cun_agg (character_print, sign_no, word_no, 0, NULL, 0, (CASE WHEN pn_variants_unnest.value_id IS NULL THEN 'sign' ELSE 'value' END)::@extschema:cuneiform_sign_properties@.sign_type, indicator_type, phonographic, stem, 'intact'::@extschema:cuneiform_sign_properties@.sign_condition, language, 
            FALSE, FALSE, FALSE, NULL, NULL, capitalized, NULL, NULL, NULL ORDER BY sign_no))[1] AS pn
    FROM
        @extschema:cuneiform_pn_tables@.pn_variants_unnest
        LEFT JOIN @extschema:cuneiform_pn_tables@.pns USING (pn_id)
        LEFT JOIN @extschema:cuneiform_signlist@.sign_variants USING (sign_id)
        LEFT JOIN @extschema:cuneiform_serialize@.characters_code ON characters_code.sign_variant_id = sign_variants.sign_variant_id AND pn_variants_unnest.value_id IS NOT DISTINCT FROM characters_code.value_id
    WHERE
        variant_type = 'default'
    GROUP BY
        pn_id,
        pn_variant_no
);


CREATE TABLE pns_search (
  pn_id integer NOT NULL,
  pn_variant_no integer NOT NULL,
  sign_no integer,
  position @extschema:cuneiform_search@.cun_position,
  word_no integer,
  compound_no integer,
  line_no integer,
  value_id integer,
  sign_variant_id integer,
  grapheme_id integer,
  glyph_id integer,
  type @extschema:cuneiform_sign_properties@.sign_type,
  indicator_type @extschema:cuneiform_sign_properties@.indicator_type,
  phonographic boolean
);

CREATE INDEX ON pns_search (pn_id, pn_variant_no);
CREATE INDEX ON pns_search (value_id) WHERE value_id IS NOT NULL;
CREATE INDEX ON pns_search (sign_variant_id);


CREATE OR REPLACE VIEW pns_search_view AS (
SELECT * FROM (
  SELECT 
    pn_id,
    pn_variant_no,
    ordinality-1,
    @extschema:cuneiform_search@.cun_position(
      greatest(ordinality, 0),
      a.pos::integer - 1, 
      row_number() OVER (PARTITION BY pn_id, pn_variant_no, ordinality ORDER BY pos DESC) = 1
      ) AS position,
    word_no,
    0 AS compound_no,
    0 AS line_no,
    NULL AS value_id,
    NULL AS sign_variant_id,
    grapheme_id,
    glyph_id,
    (CASE WHEN value_id IS NULL THEN 'sign' ELSE 'value' END)::@extschema:cuneiform_sign_properties@.sign_type,
    indicator_type,
    phonographic
  FROM 
    @extschema:cuneiform_pn_tables@.pn_variants
    LEFT JOIN LATERAL UNNEST(sign_meanings) WITH ORDINALITY ON TRUE
    LEFT JOIN @extschema:cuneiform_signlist@.sign_variants_composition USING (sign_id)
    LEFT JOIN LATERAL unnest(grapheme_ids, glyph_ids) WITH ORDINALITY a(grapheme_id, glyph_id, pos) ON TRUE
  WHERE
    variant_type = 'default'
  UNION ALL
  SELECT
    pn_id,
    pn_variant_no,
    ordinality-1,
    @extschema:cuneiform_search@.cun_position(
      greatest(ordinality, 0),
      0, 
      TRUE) AS position,
    word_no,
    0 AS compound_no,
    0 AS line_no,
    value_id,
    sign_variant_id,
    NULL AS grapheme_id,
    NULL AS glyph_id,
    (CASE WHEN value_id IS NULL THEN 'sign' ELSE 'value' END)::@extschema:cuneiform_sign_properties@.sign_type,
    indicator_type,
    phonographic
  FROM 
    @extschema:cuneiform_pn_tables@.pn_variants
    LEFT JOIN LATERAL UNNEST(sign_meanings) WITH ORDINALITY ON TRUE
    LEFT JOIN @extschema:cuneiform_signlist@.sign_variants_composition USING (sign_id)
  WHERE
    variant_type = 'default'
  UNION ALL
  SELECT                      -- pseudo first row
    pn_id,
    pn_variant_no,
    NULL AS sign_no,
    @extschema:cuneiform_search@.cun_position(0, 0, TRUE) AS position,
    -1 AS word_no,
    -1 AS compound_no,
    -1 AS line_no,
    NULL AS value_id,
    NULL AS sign_variant_id,
    NULL AS grapheme_id,
    NULL AS glyph_id,
    NULL AS type,
    NULL AS indicator_type,
    NULL AS phonographic
  FROM 
    @extschema:cuneiform_pn_tables@.pn_variants
  UNION ALL
  SELECT                      -- pseudo final row
    pn_id,
    pn_variant_no,
    NULL AS sign_no,
    @extschema:cuneiform_search@.cun_position(
      greatest(cardinality(sign_meanings)+1, 0),
      0,
      TRUE) AS position,
    (sign_meanings[cardinality(sign_meanings)]).word_no+1 AS word_no,
    1 AS compound_no,
    1 AS line_no,
    NULL AS value_id,
    NULL AS sign_variant_id,
    NULL AS grapheme_id,
    NULL AS glyph_id,
    NULL AS type,
    NULL AS indicator_type,
    NULL AS phonographic
  FROM 
    @extschema:cuneiform_pn_tables@.pn_variants
  UNION ALL
  SELECT                      -- placeholder row
    pn_id,
    pn_variant_no,
    NULL AS sign_no,
    NULL AS position,
    NULL AS word_no,
    NULL AS compound_no,
    NULL AS line_no,
    NULL AS value_id,
    NULL AS sign_variant_id,
    NULL AS grapheme_id,
    NULL AS glyph_id,
    NULL AS type,
    NULL AS indicator_type,
    NULL AS phonographic
  FROM 
    @extschema:cuneiform_pn_tables@.pn_variants)
  a);


CREATE OR REPLACE FUNCTION pns_search_trigger_fun () 
  RETURNS trigger 
  VOLATILE
  LANGUAGE PLPGSQL
  AS
$BODY$
BEGIN
  DELETE FROM @extschema@.pns_search WHERE pn_id = (OLD).pn_id AND pn_variant_no = (OLD).pn_variant_no;
  INSERT INTO @extschema@.pns_search SELECT * FROM @extschema@.pns_search_view WHERE pn_id = (NEW).pn_id AND pn_variant_no = (NEW).pn_variant_no;
  RETURN NULL;
END;
$BODY$;

CREATE TRIGGER pns_search_trigger
  AFTER UPDATE OR INSERT OR DELETE ON @extschema:cuneiform_pn_tables@.pn_variants
  FOR EACH ROW
  EXECUTE FUNCTION pns_search_trigger_fun();

INSERT INTO pns_search SELECT * FROM pns_search_view;


CREATE OR REPLACE FUNCTION search_pns (
    v_search_term text,
    v_period_ids integer[] DEFAULT ARRAY[]::integer[],
    v_provenience_ids integer[] DEFAULT ARRAY[]::integer[],
    v_genre_ids integer[] DEFAULT ARRAY[]::integer[],
    v_object_ids integer[] DEFAULT ARRAY[]::integer[]
  )
  RETURNS TABLE (
    pn_id integer,
    pn_variant_no integer
  )
  LANGUAGE PLPGSQL
  COST 100 
  STABLE 
  ROWS 1000
  AS $BODY$
BEGIN
  RETURN QUERY EXECUTE 
    $$
    SELECT
        pn_id,
        pn_variant_no
    FROM ($$ || @extschema:cuneiform_search@.parse_search (v_search_term, 'pns_search', ARRAY['pn_id', 'pn_variant_no'], '@extschema@') || $$) _
    $$
    USING v_period_ids, v_provenience_ids, v_genre_ids, v_object_ids;
END;
$BODY$;


CREATE OR REPLACE PROCEDURE edit_pn_variant (v_code text, v_pn_id integer, v_pn_variant_no integer)
    LANGUAGE SQL
BEGIN  ATOMIC

UPDATE @extschema:cuneiform_pn_tables@.pn_variants
  SET sign_meanings = @extschema:cuneiform_parser@.parse_to_sign_meanings(v_code)
  WHERE pn_id = v_pn_id AND pn_variant_no = v_pn_variant_no;

END;


CREATE OR REPLACE PROCEDURE add_pn_variant (v_code text, v_pn_id integer, INOUT v_pn_variant_no integer DEFAULT NULL)
    LANGUAGE SQL
BEGIN ATOMIC

INSERT INTO @extschema:cuneiform_pn_tables@.pn_variants
  SELECT v_pn_id, COALESCE(max(pn_variant_no)+1, 0), @extschema:cuneiform_parser@.parse_to_sign_meanings(v_code) FROM @extschema:cuneiform_pn_tables@.pn_variants WHERE pn_id = v_pn_id
  RETURNING pn_variant_no;

END;


CREATE OR REPLACE PROCEDURE add_pn (
      v_pn_type @extschema:cuneiform_sign_properties@.pn_type, 
      v_language @extschema:cuneiform_sign_properties@.language,
      v_normal_form text,
      v_code text)
    LANGUAGE PLPGSQL
    AS $BODY$

DECLARE

v_pn_id integer;

BEGIN

INSERT INTO @extschema:cuneiform_pn_tables@.pns VALUES (default, v_pn_type, v_language, v_normal_form) RETURNING pn_id INTO v_pn_id;
CALL @extschema@.add_pn_variant(v_code, v_pn_id);

END
$BODY$;