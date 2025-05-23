CREATE OR REPLACE PROCEDURE add_value (
    v_sign_id integer, 
    v_value text,
    v_phonographic boolean DEFAULT NULL,
    v_value_id INOUT integer DEFAULT NULL,
    v_value_variant_id INOUT integer DEFAULT NULL
  )
  LANGUAGE PLPGSQL
AS $BODY$
BEGIN
  INSERT INTO @extschema@.values VALUES (default, v_sign_id, -1, v_phonographic) RETURNING value_id INTO v_value_id;
  INSERT INTO @extschema@.value_variants VALUES (default, v_value_id, v_value) RETURNING value_variant_id INTO v_value_variant_id;
  UPDATE @extschema@.values SET main_variant_id = v_value_variant_id WHERE value_id = v_value_id;
END;
$BODY$;


CREATE OR REPLACE PROCEDURE add_value (
    v_sign text, 
    v_value text,
    v_phonographic boolean DEFAULT NULL,
    v_value_id INOUT integer DEFAULT NULL,
    v_value_variant_id INOUT integer DEFAULT NULL
  )
  LANGUAGE PLPGSQL
AS $BODY$
DECLARE
  v_sign_id integer;
BEGIN
  SELECT 
    sign_id 
  INTO 
    v_sign_id 
  FROM 
    @extschema@.sign_variants_composition 
  WHERE 
    graphemes = v_sign 
    AND specific;
  CALL @extschema@.add_value(v_sign_id, v_value, v_phonographic, v_value_id, v_value_variant_id);
END;
$BODY$;


CREATE OR REPLACE PROCEDURE add_allograph (
    v_grapheme_id integer,
    v_glyph_id integer,
    v_variant_type sign_variant_type DEFAULT 'nondefault',
    v_specific boolean DEFAULT FALSE,
    v_allograph_id INOUT integer DEFAULT NULL
  )
  LANGUAGE PLPGSQL
AS $BODY$
BEGIN
  INSERT INTO @extschema@.allographs VALUES (default, v_grapheme_id, v_glyph_id, v_variant_type, v_specific) RETURNING allograph_id INTO v_allograph_id;
END;
$BODY$;


CREATE OR REPLACE PROCEDURE add_allograph (
    v_grapheme text,
    v_glyph text,
    v_variant_type sign_variant_type DEFAULT 'nondefault',
    v_specific boolean DEFAULT FALSE,
    v_allograph_id INOUT integer DEFAULT NULL
  )
  LANGUAGE PLPGSQL
AS $BODY$
DECLARE
  v_grapheme_id integer;
  v_glyph_id integer;
BEGIN
  SELECT grapheme_id INTO v_grapheme_id FROM @extschema@.graphemes WHERE grapheme = v_grapheme;
  SELECT glyph_id INTO v_glyph_id FROM @extschema@.glyphs WHERE glyph = v_glyph;
  CALL @extschema@.add_allograph(v_grapheme_id, v_glyph_id, v_variant_type, v_specific, v_allograph_id);
END;
$BODY$;


CREATE OR REPLACE PROCEDURE add_default_grapheme (
    v_grapheme text,
    v_grapheme_id INOUT integer DEFAULT NULL,
    v_glyph_id INOUT integer DEFAULT NULL,
    v_allograph_id INOUT integer DEFAULT NULL
  )
  LANGUAGE PLPGSQL
AS $BODY$
BEGIN
  INSERT INTO @extschema@.glyphs(glyph) VALUES (v_grapheme) RETURNING glyph_id INTO v_glyph_id;
  INSERT INTO @extschema@.graphemes(grapheme) VALUES (v_grapheme) RETURNING grapheme_id INTO v_grapheme_id;
  CALL @extschema@.add_allograph(v_grapheme_id, v_glyph_id, 'default', true, v_allograph_id);
END;
$BODY$;


CREATE OR REPLACE PROCEDURE add_allomorph (
    v_sign_id integer,
    v_grapheme_ids integer[],
    v_variant_type sign_variant_type DEFAULT 'nondefault',
    v_specific boolean DEFAULT FALSE,
    v_allomorph_id INOUT integer DEFAULT NULL
  )
  LANGUAGE PLPGSQL
AS $BODY$
BEGIN

  CALL @extschema@.signlist_drop_triggers();

  INSERT INTO @extschema@.allomorphs VALUES (default, v_sign_id, v_variant_type, v_specific) RETURNING allomorph_id INTO v_allomorph_id;
  INSERT INTO @extschema@.allomorph_components
    SELECT
        v_allomorph_id,
        pos,
        grapheme_id
    FROM
        LATERAL UNNEST(v_grapheme_ids) WITH ORDINALITY a(grapheme_id, pos);

  CALL @extschema@.signlist_create_triggers();
  UPDATE @extschema@.allomorphs SET sign_id = sign_id WHERE allomorph_id = v_allomorph_id; -- trigger trigger

END;
$BODY$;


CREATE OR REPLACE PROCEDURE add_allomorph (
    v_sign_id integer,
    v_graphemes text,
    v_variant_type sign_variant_type DEFAULT 'nondefault',
    v_specific boolean DEFAULT FALSE,
    v_allomorph_id INOUT integer DEFAULT NULL
  )
  LANGUAGE PLPGSQL
AS $BODY$
BEGIN

  CALL @extschema@.signlist_drop_triggers();

  INSERT INTO @extschema@.allomorphs VALUES (default, v_sign_id, v_variant_type, v_specific) RETURNING allomorph_id INTO v_allomorph_id;
  INSERT INTO @extschema@.allomorph_components
    SELECT
        v_allomorph_id,
        pos,
        grapheme_ids[1]
    FROM
        LATERAL @extschema@.split_glyphs(v_graphemes) WITH ORDINALITY a(grapheme_identifier, pos)
        LEFT JOIN @extschema@.sign_map ON identifier = grapheme_identifier AND array_length(grapheme_ids, 1) = 1;

  CALL @extschema@.signlist_create_triggers();
  UPDATE @extschema@.allomorphs SET sign_id = sign_id WHERE allomorph_id = v_allomorph_id; -- trigger trigger

END;
$BODY$;


CREATE OR REPLACE PROCEDURE add_allomorph (
    v_sign text, 
    v_graphemes text,
    v_variant_type sign_variant_type DEFAULT 'nondefault',
    v_specific boolean DEFAULT FALSE,
    v_allomorph_id INOUT integer DEFAULT NULL
  )
  LANGUAGE PLPGSQL
AS $BODY$
DECLARE
  v_sign_id integer;
BEGIN
  SELECT 
    sign_id 
  INTO 
    v_sign_id 
  FROM 
    @extschema@.sign_variants_composition 
    JOIN @extschema@.allomorphs USING (sign_id, allomorph_id) 
  WHERE 
    graphemes = v_sign 
    AND sign_variants_composition.specific;
  CALL @extschema@.add_allomorph(v_sign_id, v_graphemes, v_variant_type, v_specific, v_allomorph_id);
END;
$BODY$;


CREATE OR REPLACE PROCEDURE add_sign (
    v_graphemes text,
    v_sign_id INOUT integer DEFAULT NULL,
    v_allomorph_id INOUT integer DEFAULT NULL
  )
  LANGUAGE PLPGSQL
AS $BODY$
BEGIN
  INSERT INTO @extschema@.signs VALUES (default) RETURNING sign_id INTO v_sign_id;
  CALL @extschema@.add_allomorph(v_sign_id, v_graphemes, 'default', TRUE, v_allomorph_id);
END;
$BODY$;


CREATE OR REPLACE PROCEDURE add_sign (
    v_grapheme_ids integer[],
    v_sign_id INOUT integer DEFAULT NULL,
    v_allomorph_id INOUT integer DEFAULT NULL
  )
  LANGUAGE PLPGSQL
AS $BODY$
BEGIN
  INSERT INTO @extschema@.signs VALUES (default) RETURNING sign_id INTO v_sign_id;
  CALL @extschema@.add_allomorph(v_sign_id, v_grapheme_ids, 'default', TRUE, v_allomorph_id);
END;
$BODY$;


CREATE OR REPLACE PROCEDURE delete_value (
    v_value_id integer
  )
  LANGUAGE PLPGSQL
AS $BODY$
BEGIN
  DELETE FROM @extschema@.value_variants WHERE value_id = v_value_id;
  DELETE FROM @extschema@.values WHERE value_id = v_value_id;
END;
$BODY$;


CREATE OR REPLACE PROCEDURE delete_allomorph (
    v_allomorph_id integer
  )
  LANGUAGE PLPGSQL
AS $BODY$
BEGIN
  --DELETE FROM @extschema@.sign_variants WHERE sign_variants.allomorph_id = v_allomorph_id;
  DELETE FROM @extschema@.allomorph_components WHERE allomorph_components.allomorph_id = v_allomorph_id;
  DELETE FROM @extschema@.allomorphs WHERE allomorphs.allomorph_id = v_allomorph_id;
END;
$BODY$;


CREATE OR REPLACE PROCEDURE delete_grapheme (
    v_grapheme_id integer
  )
  LANGUAGE PLPGSQL
AS $BODY$
BEGIN
  DELETE FROM @extschema@.allographs WHERE grapheme_id = v_grapheme_id;
  DELETE FROM @extschema@.graphemes WHERE grapheme_id = v_grapheme_id;
END;
$BODY$;


CREATE OR REPLACE PROCEDURE delete_sign (
  v_sign_id integer
  )
  LANGUAGE PLPGSQL
AS $BODY$
DECLARE
  v_id integer;
BEGIN
  FOR v_id IN SELECT value_id FROM @extschema@.values WHERE sign_id = v_sign_id LOOP
      CALL @extschema@.delete_value(v_id);
  END LOOP;
  FOR v_id IN SELECT allomorph_id FROM @extschema@.allomorphs WHERE sign_id = v_sign_id LOOP
      CALL @extschema@.delete_allomorph(v_id);
  END LOOP;
  DELETE FROM @extschema@.signs WHERE sign_id = v_sign_id;
END;
$BODY$;


CREATE OR REPLACE PROCEDURE merge_values (
    v_value_id_1 integer, 
    v_value_id_2 integer
  )
  LANGUAGE PLPGSQL
AS $BODY$
DECLARE
  v_same_sign bool;
BEGIN
  SELECT 
    a.sign_id = b.sign_id 
  INTO v_same_sign 
  FROM 
    (SELECT sign_id FROM @extschema@.values WHERE value_id = v_value_id_1) a, 
    (SELECT sign_id FROM @extschema@.values WHERE value_id = v_value_id_2) b; 
  ASSERT v_same_sign;
  UPDATE @extschema@.value_variants SET value_id = v_value_id_1 WHERE value_id = v_value_id_2;
  DELETE FROM @extschema@.values WHERE value_id = v_value_id_2;
END;
$BODY$;


CREATE OR REPLACE PROCEDURE merge_signs (
    v_sign_id_1 integer, 
    v_sign_id_2 integer
  )
  LANGUAGE PLPGSQL
AS $BODY$
DECLARE
  v_value_id integer;
BEGIN
  FOR v_value_id IN 
      WITH value_list AS (
          SELECT * FROM @extschema@.value_variants JOIN @extschema@.values USING (value_id)
      )
      SELECT 
          a.value_id
      FROM value_list a 
          JOIN value_list b ON replace(a.value, 'x', '') = regexp_replace(b.value, '[0-9x]+$', '')
      WHERE 
          a.value ~ 'x' AND a.sign_id = v_sign_id_2 AND b.sign_id = v_sign_id_1
  LOOP
      CALL @extschema@.delete_value(v_value_id);
  END LOOP;
  FOR v_value_id IN 
      WITH value_list AS (
          SELECT * FROM @extschema@.value_variants JOIN @extschema@.values USING (value_id)
      )
      SELECT 
          a.value_id
      FROM value_list a 
          JOIN value_list b ON replace(a.value, 'x', '') = regexp_replace(b.value, '[0-9x]+$', '')
      WHERE 
          a.value ~ 'x' AND a.sign_id = v_sign_id_1 AND b.sign_id = v_sign_id_2
  LOOP
      CALL @extschema@.delete_value(v_value_id);
  END LOOP;
  UPDATE @extschema@.values SET sign_id = v_sign_id_1 WHERE sign_id = v_sign_id_2;
  UPDATE @extschema@.allomorphs SET variant_type = 'nondefault' WHERE sign_id = v_sign_id_2 AND variant_type = 'default';
  UPDATE @extschema@.allomorphs SET sign_id = v_sign_id_1 WHERE sign_id = v_sign_id_2;
  DELETE FROM @extschema@.signs WHERE sign_id = v_sign_id_2;
END;
$BODY$;


CREATE OR REPLACE PROCEDURE allomorph_to_allograph (
    v_allomorph_id integer,
    v_allgraph_id INOUT integer DEFAULT NULL
  )
  LANGUAGE PLPGSQL
AS $BODY$
DECLARE

  v_variant_type @extschema@.sign_variant_type;
  v_specific boolean;
  v_grapheme_id integer;
  v_allograph_specific boolean;
  v_glyph_id integer;
  v_allograph_id integer;
  v_sign_variant_id integer;
  v_grapheme_id_new integer;
  v_allomorph_id_new integer;
  v_allograph_id_new integer;
  v_sign_id integer;

BEGIN

  SELECT sign_id INTO v_sign_id FROM @extschema@.allomorphs WHERE allomorph_id = v_allomorph_id;

  SELECT 
    grapheme_id,
    glyph_id,
    allograph_id,
    specific
  INTO STRICT 
    v_grapheme_id,
    v_glyph_id,
    v_allograph_id,
    v_allograph_specific
  FROM 
    @extschema@.allomorph_components 
    JOIN @extschema@.allographs USING (grapheme_id)
  WHERE 
    allomorph_id = v_allomorph_id
    AND variant_type = 'default';

  SELECT 
    allomorph_id, 
    grapheme_id 
  INTO STRICT
    v_allomorph_id_new,
    v_grapheme_id_new
  FROM 
    @extschema@.allomorphs
    JOIN @extschema@.allomorph_components USING (allomorph_id) 
  WHERE
    sign_id = v_sign_id
    AND variant_type = 'default';

  SELECT variant_type, specific AND v_allograph_specific INTO v_variant_type, v_specific FROM @extschema@.allomorphs WHERE allomorph_id = v_allomorph_id; 
  SELECT sign_variant_id INTO v_sign_variant_id FROM @extschema@.sign_variants WHERE allomorph_id = v_allomorph_id AND allograph_ids = ARRAY[v_allograph_id];

  SET CONSTRAINTS ALL DEFERRED;

  CALL @extschema@.delete_allomorph(v_allomorph_id);
  IF v_specific THEN
    CALL @extschema@.delete_grapheme(v_grapheme_id);
  END IF;
  INSERT INTO @extschema@.allographs VALUES (default, v_grapheme_id_new, v_glyph_id, v_variant_type, v_specific) RETURNING allograph_id INTO v_allograph_id_new;
  DELETE FROM @extschema@.sign_variants WHERE allomorph_id = v_allomorph_id_new AND allograph_ids = ARRAY[v_allograph_id_new];
  INSERT INTO @extschema@.sign_variants OVERRIDING SYSTEM VALUE VALUES (v_sign_variant_id, v_sign_id, v_allomorph_id_new, ARRAY[v_allograph_id_new], v_variant_type, v_specific);

  --SET CONSTRAINTS ALL IMMEDIATE;

END;
$BODY$;


CREATE OR REPLACE PROCEDURE make_glyph_value (
    v_value_id integer,
    v_value_id_new integer
  )
  LANGUAGE PLPGSQL
AS $BODY$
BEGIN
    INSERT INTO @extschema@.glyph_values 
        SELECT 
            value, 
            v_value_id_new, 
            glyph_ids 
        FROM 
            @extschema@.value_variants 
            JOIN @extschema@.values USING (value_id) 
            JOIN @extschema@.sign_variants_composition USING (sign_id)
        WHERE
            value_id = v_value_id AND 
            value !~ 'x' AND
            sign_variants_composition.variant_type = 'default';
    CALL @extschema@.delete_value(v_value_id);
END;
$BODY$;


CREATE OR REPLACE PROCEDURE make_glyph_value (
    v_value text,
    v_value_new text
  )
  LANGUAGE PLPGSQL
AS $BODY$
DECLARE
  v_value_id integer;
  v_value_id_new integer;
BEGIN
  SELECT value_id INTO v_value_id FROM @extschema@.value_variants WHERE value = v_value;
  SELECT value_id INTO v_value_id_new FROM @extschema@.value_variants WHERE value = v_value_new;
  CALL @extschema@.make_glyph_value(v_value_id, v_value_id_new);
END;
$BODY$;