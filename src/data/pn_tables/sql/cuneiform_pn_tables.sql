CREATE TABLE pns (
  pn_id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  pn_type @extschema:cuneiform_sign_properties@.pn_type NOT NULL,
  language @extschema:cuneiform_sign_properties@.language,
  normal_form text
);


CREATE TABLE pn_variants (
  pn_id integer REFERENCES pns (pn_id) ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
  pn_variant_no integer,
  sign_meanings @extschema:cuneiform_sign_meanings@.sign_meaning[],
  PRIMARY KEY (pn_id, pn_variant_no)
);


CREATE TABLE pn_variants_suffixes (
  pn_id integer, 
  pn_variant_no integer, 
  value_ids integer[], 
  FOREIGN KEY (pn_id, pn_variant_no) REFERENCES pn_variants ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
  PRIMARY KEY (pn_id, pn_variant_no, value_ids)
);


SELECT pg_catalog.pg_extension_config_dump('@extschema@.pns', '');
SELECT pg_catalog.pg_extension_config_dump(pg_get_serial_sequence('@extschema@.pns', 'pn_id'), '');
SELECT pg_catalog.pg_extension_config_dump('@extschema@.pn_variants', '');
SELECT pg_catalog.pg_extension_config_dump('@extschema@.pn_variants_suffixes', '');

CREATE TABLE pn_variants_unnest (
  pn_id integer,
  pn_variant_no integer,
  sign_no integer,
  LIKE @extschema:cuneiform_sign_meanings@.sign_meaning,
  PRIMARY KEY (pn_id, pn_variant_no, sign_no),
  FOREIGN KEY (pn_id, pn_variant_no) REFERENCES pn_variants (pn_id, pn_variant_no) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
  FOREIGN KEY (value_id) REFERENCES values (value_id) DEFERRABLE INITIALLY IMMEDIATE,
  FOREIGN KEY (sign_id) REFERENCES signs (sign_id) DEFERRABLE INITIALLY IMMEDIATE
);

CREATE VIEW pn_variants_unnest_view AS
  SELECT
    pn_id,
    pn_variant_no,
    ordinality-1,
    word_no, 
    value_id, 
    sign_id, 
    indicator_type, 
    phonographic, 
    stem,
    capitalized
  FROM
    pn_variants
    JOIN UNNEST(sign_meanings) WITH ORDINALITY ON TRUE;


CREATE OR REPLACE FUNCTION pn_variants_unnest_trigger_fun () 
  RETURNS trigger 
  VOLATILE
  LANGUAGE PLPGSQL
  AS
$BODY$
BEGIN
  DELETE FROM @extschema@.pn_variants_unnest 
    USING 
      new_table 
    WHERE 
      pn_variants_unnest.pn_id = new_table.pn_id 
      AND pn_variants_unnest.pn_variant_no = new_table.pn_variant_no;
  INSERT INTO @extschema@.pn_variants_unnest 
    SELECT 
      pn_variants_unnest_view.* 
    FROM 
      @extschema@.pn_variants_unnest_view
      JOIN new_table USING (pn_id, pn_variant_no);
  RETURN NULL;
END;
$BODY$;

CREATE TRIGGER pn_variants_unnest_update_trigger 
  AFTER UPDATE ON pn_variants
  REFERENCING NEW TABLE AS new_table
  FOR EACH STATEMENT
  EXECUTE FUNCTION pn_variants_unnest_trigger_fun ();
CREATE TRIGGER pn_variants_unnest_insert_trigger 
  AFTER INSERT ON pn_variants
  REFERENCING NEW TABLE AS new_table
  FOR EACH STATEMENT
  EXECUTE FUNCTION pn_variants_unnest_trigger_fun ();


CREATE OR REPLACE FUNCTION update_pn_variants_unnest_trigger_fun () 
  RETURNS trigger 
  VOLATILE
  LANGUAGE PLPGSQL
  AS
$BODY$
BEGIN
    UPDATE @extschema@.pn_variants
    SET sign_meanings = a.sign_meanings
    FROM
      (
        SELECT
          pn_id,
          pn_variant_no,
          array_agg(
            ROW(word_no, value_id, sign_id, indicator_type, phonographic, stem, capitalized)::@extschema:cuneiform_sign_meanings@.sign_meaning
            ORDER BY sign_no
          ) AS sign_meanings
        FROM
          @extschema@.pn_variants_unnest
          JOIN (SELECT DISTINCT pn_id, pn_variant_no FROM new_table) _ USING (pn_id, pn_variant_no)
        GROUP BY
          pn_id,
          pn_variant_no
      )
      a
    WHERE
        pn_variants.pn_id = a.pn_id
        AND pn_variants.pn_variant_no = a.pn_variant_no
        AND pn_variants.sign_meanings IS DISTINCT FROM a.sign_meanings;
    RETURN NULL;
END;
$BODY$;

CREATE TRIGGER update_pn_variants_unnest_trigger
  AFTER UPDATE ON pn_variants_unnest
  REFERENCING NEW TABLE AS new_table
  FOR EACH STATEMENT
  EXECUTE FUNCTION update_pn_variants_unnest_trigger_fun ();


CREATE OR REPLACE PROCEDURE load_pns (v_path text)
    LANGUAGE PLPGSQL
    AS $BODY$

BEGIN

SET CONSTRAINTS ALL DEFERRED;

EXECUTE format('COPY @extschema@.pns FROM %L CSV NULL ''\N''', v_path || 'pns.csv');
EXECUTE format('COPY @extschema@.pn_variants FROM %L CSV NULL ''\N''', v_path || 'pn_variants.csv');
EXECUTE format('COPY @extschema@.pn_variants_suffixes FROM %L CSV NULL ''\N''', v_path || 'pn_variants_suffixes.csv');
PERFORM setval(pg_get_serial_sequence('@extschema@.pns', 'pn_id'), max(pn_id)) FROM @extschema@.pns;

END
$BODY$;


CREATE OR REPLACE VIEW pn_variants_suffixes_sign_meanings AS
SELECT
  pn_id,
  pn_variant_no,
  array_agg((0, value_id, sign_id, 'none', TRUE, FALSE, FALSE)::@extschema:cuneiform_sign_meanings@.sign_meaning ORDER BY ord) AS sign_meanings
FROM
  @extschema@.pn_variants_suffixes
  LEFT JOIN LATERAL unnest(value_ids) WITH ORDINALITY AS _(value_id, ord) ON TRUE
  JOIN @extschema:cuneiform_signlist@.values USING (value_id)
GROUP BY
  pn_id,
  pn_variant_no,
  value_ids;


CREATE OR REPLACE VIEW pn_variants_grapheme_ids AS
WITH RECURSIVE
a AS (
  SELECT
    pn_id,
    pn_variant_no,
    1 AS sign_no,
    grapheme_ids,
    ARRAY[sign_variant_id] AS sign_variant_ids,
    variant_type
  FROM
    @extschema@.pn_variants_unnest
    JOIN @extschema:cuneiform_signlist@.sign_variants_composition USING (sign_id)
  WHERE
    sign_no = 0
  UNION ALL
  SELECT
    pn_id,
    pn_variant_no,
    sign_no+1,
    a.grapheme_ids || sign_variants_composition.grapheme_ids,
    sign_variant_ids || sign_variant_id,
    @extschema:cuneiform_signlist@.merge_variant_types(a.variant_type, sign_variants_composition.variant_type)
  FROM
    a
    JOIN @extschema@.pn_variants_unnest USING (pn_id, pn_variant_no, sign_no)
    JOIN @extschema:cuneiform_signlist@.sign_variants_composition USING (sign_id)
)
SELECT
  pn_id,
  pn_variant_no,
  grapheme_ids,
  sign_variant_ids,
  variant_type
FROM
  a
  JOIN @extschema@.pn_variants USING (pn_id, pn_variant_no)
WHERE
  sign_no = cardinality(sign_meanings);