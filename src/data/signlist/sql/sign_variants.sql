CREATE OR REPLACE FUNCTION merge_variant_types (
    a sign_variant_type,
    b sign_variant_type
  )
  RETURNS sign_variant_type
  LANGUAGE SQL
  IMMUTABLE
  STRICT
BEGIN ATOMIC
  SELECT 
    CASE
      WHEN a = b THEN a
      WHEN GREATEST(a, b) = ANY('{reduced, augmented}') AND LEAST(a, b) = ANY('{default, nondefault}') THEN GREATEST(a, b)
      WHEN GREATEST(a, b) = ANY('{nonstandard, reduced, augmented}') THEN 'nonstandard'::sign_variant_type
      ELSE 'nondefault'::sign_variant_type
    END;
END;

CREATE VIEW sign_variants_view AS
WITH RECURSIVE 
    a AS (
        SELECT * FROM allomorph_components LEFT JOIN allographs USING (grapheme_id)
    ), 
    x(sign_id, allomorph_id, pos, allograph_ids, grapheme_ids, glyph_ids, variant_type, allomorph_variant_type, specific) AS (
        SELECT 
            sign_id,
            allomorph_id,
            a.pos,
            ARRAY[a.allograph_id],
            ARRAY[a.grapheme_id],
            ARRAY[a.glyph_id],
            merge_variant_types(a.variant_type, allomorphs.variant_type),
            allomorphs.variant_type,
            a.specific AND allomorphs.specific
        FROM a
            JOIN allomorphs USING (allomorph_id) 
        WHERE a.pos = 1
    UNION ALL
        SELECT
            sign_id,
            allomorph_id,
            a.pos,
            allograph_ids || allograph_id,
            grapheme_ids || grapheme_id,
            glyph_ids || glyph_id,
            merge_variant_types(a.variant_type, x.variant_type),
            allomorph_variant_type,
            a.specific AND x.specific
        FROM x
            JOIN a USING (allomorph_id)
        WHERE (x.pos + 1) = a.pos
    )
SELECT 
    sign_id,
    allomorph_id,
    allograph_ids,
    variant_type,
    specific
FROM (
    SELECT
        *,
        rank() OVER (PARTITION BY sign_id, glyph_ids ORDER BY variant_type, allomorph_variant_type DESC, grapheme_ids ASC) AS rank2
    FROM (
        SELECT 
            *,
            rank() OVER (PARTITION BY x.allomorph_id ORDER BY x.pos DESC) AS rank1
        FROM x) _
    WHERE rank1 = 1) __
WHERE rank2 = 1;


CREATE OR REPLACE FUNCTION sign_variants_sync_signs (v_sign_ids integer[])
  RETURNS void 
  VOLATILE
  LANGUAGE PLPGSQL
  AS
$BODY$
BEGIN
    DELETE FROM @extschema@.sign_variants 
    WHERE 
        sign_id = ANY(v_sign_ids)
        AND (allomorph_id, allograph_ids) NOT IN (SELECT allomorph_id, allograph_ids FROM @extschema@.sign_variants_view WHERE sign_id = ANY(v_sign_ids));

    INSERT INTO @extschema@.sign_variants (sign_id, allomorph_id, allograph_ids, variant_type, specific)
    SELECT * FROM @extschema@.sign_variants_view WHERE sign_id = ANY(v_sign_ids)
    ON CONFLICT (allomorph_id, allograph_ids) DO UPDATE SET
        sign_id = EXCLUDED.sign_id,
        variant_type = EXCLUDED.variant_type,
        specific = EXCLUDED.specific
    WHERE
        sign_variants.sign_id != EXCLUDED.sign_id
        OR sign_variants.variant_type != EXCLUDED.variant_type
        OR sign_variants.specific != EXCLUDED.specific;
END;
$BODY$;


CREATE OR REPLACE FUNCTION sign_variants_allomorphs_trigger_fun () 
  RETURNS trigger 
  VOLATILE
  LANGUAGE PLPGSQL
  AS
$BODY$
BEGIN
    PERFORM @extschema@.sign_variants_sync_signs(ARRAY[(OLD).sign_id, (NEW).sign_id]);
    RETURN NULL;
END;
$BODY$;


CREATE OR REPLACE FUNCTION sign_variants_allomorph_components_trigger_fun () 
  RETURNS trigger 
  VOLATILE
  LANGUAGE PLPGSQL
  AS
$BODY$
BEGIN
    PERFORM 
        @extschema@.sign_variants_sync_signs(array_agg(DISTINCT sign_id)) 
    FROM 
        @extschema@.allomorphs
    WHERE 
        allomorph_id = (OLD).allomorph_id 
        OR allomorph_id = (NEW).allomorph_id;
    RETURN NULL;
END;
$BODY$;


CREATE OR REPLACE FUNCTION sign_variants_allographs_trigger_fun () 
  RETURNS trigger 
  VOLATILE
  LANGUAGE PLPGSQL
  AS
$BODY$
BEGIN
    PERFORM 
        @extschema@.sign_variants_sync_signs(array_agg(DISTINCT sign_id)) 
    FROM 
        @extschema@.allomorphs
        JOIN @extschema@.allomorph_components USING (allomorph_id)
    WHERE 
        grapheme_id = (OLD).grapheme_id 
        OR grapheme_id = (NEW).grapheme_id;
    RETURN NULL;
END;
$BODY$;



CREATE TABLE sign_variants_composition (
    sign_variant_id integer PRIMARY KEY,
    sign_id integer NOT NULL REFERENCES signs (sign_id) DEFERRABLE INITIALLY DEFERRED,
    allomorph_id integer NOT NULL REFERENCES allomorphs (allomorph_id) DEFERRABLE INITIALLY DEFERRED,
    allograph_ids integer[] NOT NULL,
    grapheme_ids integer[] NOT NULL,
    glyph_ids integer[] NOT NULL,
    graphemes text NOT NULL,
    glyphs text NOT NULL,
    unicode text NOT NULL,
    tree jsonb NOT NULL,
    variant_type sign_variant_type NOT NULL,
    specific boolean NOT NULL
);


CREATE VIEW sign_variants_composition_view AS
WITH _ AS (
    SELECT
        sign_variant_id,
        array_agg(grapheme_id ORDER BY ord) AS grapheme_ids,
        array_agg(glyph_id ORDER BY ord) AS glyph_ids,
        string_agg(grapheme, '.' ORDER BY ord) AS graphemes,
        string_agg(glyph, '.' ORDER BY ord) AS glyphs,
        string_agg(COALESCE(unicode, '□'), '' ORDER BY ord) AS unicode
    FROM
        sign_variants
        LEFT JOIN LATERAL unnest(allograph_ids) WITH ORDINALITY AS a(allograph_id, ord) ON TRUE
        LEFT JOIN allographs USING (allograph_id)
        LEFT JOIN graphemes USING (grapheme_id)
        LEFT JOIN glyphs USING (glyph_id)
    GROUP BY
        sign_variant_id
)
SELECT
    sign_variant_id,
    sign_id,
    allomorph_id,
    allograph_ids,
    grapheme_ids,
    glyph_ids,
    graphemes,
    glyphs,
    unicode,
    parse_sign(glyphs) AS tree,
    variant_type,
    specific
FROM _
    LEFT JOIN sign_variants USING (sign_variant_id);


CREATE OR REPLACE FUNCTION sign_variants_composition_sign_variants_trigger_fun () 
  RETURNS trigger 
  VOLATILE
  LANGUAGE PLPGSQL
  AS
$BODY$
BEGIN
    IF NEW IS NULL THEN
        DELETE FROM @extschema@.sign_variants_composition WHERE sign_variant_id = (OLD).sign_variant_id;
    ELSE
        INSERT INTO @extschema@.sign_variants_composition
        SELECT
            *
        FROM
            @extschema@.sign_variants_composition_view
        WHERE
            sign_variant_id = (NEW).sign_variant_id
        ON CONFLICT (sign_variant_id) DO UPDATE SET
            sign_id = EXCLUDED.sign_id,
            allomorph_id = EXCLUDED.allomorph_id,
            allograph_ids = EXCLUDED.allograph_ids,
            grapheme_ids = EXCLUDED.grapheme_ids,
            glyph_ids = EXCLUDED.glyph_ids,
            graphemes = EXCLUDED.graphemes,
            glyphs = EXCLUDED.glyphs,
            unicode = EXCLUDED.unicode,
            tree = EXCLUDED.tree,
            variant_type = EXCLUDED.variant_type,
            specific = EXCLUDED.specific;
    END IF;
    RETURN NULL;
END;
$BODY$;


CREATE OR REPLACE FUNCTION sign_variants_composition_graphemes_trigger_fun () 
  RETURNS trigger 
  VOLATILE
  LANGUAGE PLPGSQL
  AS
$BODY$
BEGIN
    UPDATE @extschema@.sign_variants_composition SET
        graphemes = sign_variants_composition_view.graphemes
    FROM
        @extschema@.sign_variants_composition_view
    WHERE
        sign_variants_composition_view.sign_variant_id = sign_variants_composition.sign_variant_id
        AND (NEW).grapheme_id = ANY(sign_variants_composition.grapheme_ids);
    RETURN NULL;
END;
$BODY$;


CREATE OR REPLACE FUNCTION sign_variants_composition_glyphs_trigger_fun () 
  RETURNS trigger 
  VOLATILE
  LANGUAGE PLPGSQL
  AS
$BODY$
BEGIN
    UPDATE @extschema@.sign_variants_composition SET
        glyphs = sign_variants_composition_view.glyphs,
        unicode = sign_variants_composition_view.unicode,
        tree = sign_variants_composition_view.tree
    FROM
        @extschema@.sign_variants_composition_view
    WHERE
        sign_variants_composition_view.sign_variant_id = sign_variants_composition.sign_variant_id
        AND (NEW).glyph_id = ANY(sign_variants_composition.glyph_ids);
    RETURN NULL;
END;
$BODY$;


CREATE OR REPLACE FUNCTION sign_variants_composition_allographs_trigger_fun () 
  RETURNS trigger 
  VOLATILE
  LANGUAGE PLPGSQL
  AS
$BODY$
BEGIN
    UPDATE @extschema@.sign_variants_composition SET
        graphemes = sign_variants_composition_view.graphemes,
        glyphs = sign_variants_composition_view.glyphs,
        unicode = sign_variants_composition_view.unicode,
        tree = sign_variants_composition_view.tree
    FROM
        @extschema@.sign_variants_composition_view
    WHERE
        sign_variants_composition_view.sign_variant_id = sign_variants_composition.sign_variant_id
        AND (NEW).allograph_id = ANY(sign_variants_composition.allograph_ids);
    RETURN NULL;
END;
$BODY$;


CREATE OR REPLACE PROCEDURE signlist_create_triggers()
    LANGUAGE SQL
AS $BODY$

  CREATE TRIGGER sign_variants_allomorphs_trigger
    AFTER UPDATE OR INSERT OR DELETE ON @extschema@.allomorphs 
    FOR EACH ROW
    EXECUTE FUNCTION @extschema@.sign_variants_allomorphs_trigger_fun();
  CREATE TRIGGER sign_variants_allomorph_components_trigger
    AFTER UPDATE OR INSERT OR DELETE ON @extschema@.allomorph_components 
    FOR EACH ROW
    EXECUTE FUNCTION @extschema@.sign_variants_allomorph_components_trigger_fun();
  CREATE TRIGGER sign_variants_allographs_trigger
    AFTER UPDATE OR INSERT OR DELETE ON @extschema@.allographs
    FOR EACH ROW
    EXECUTE FUNCTION @extschema@.sign_variants_allographs_trigger_fun();
  CREATE TRIGGER sign_variants_composition_sign_variants_trigger
    AFTER UPDATE OR INSERT OR DELETE ON @extschema@.sign_variants 
    FOR EACH ROW
    EXECUTE FUNCTION @extschema@.sign_variants_composition_sign_variants_trigger_fun();
  CREATE TRIGGER sign_variants_composition_graphemes_trigger
    AFTER UPDATE ON @extschema@.graphemes 
    FOR EACH ROW
    EXECUTE FUNCTION @extschema@.sign_variants_composition_graphemes_trigger_fun();
  CREATE TRIGGER sign_variants_composition_glyphs_trigger
    AFTER UPDATE ON @extschema@.glyphs 
    FOR EACH ROW
    EXECUTE FUNCTION @extschema@.sign_variants_composition_glyphs_trigger_fun();
  CREATE TRIGGER sign_variants_composition_allographs_trigger
    AFTER UPDATE ON @extschema@.allographs 
    FOR EACH ROW
    EXECUTE FUNCTION @extschema@.sign_variants_composition_allographs_trigger_fun();
$BODY$;


CREATE OR REPLACE PROCEDURE signlist_drop_triggers()
    LANGUAGE SQL
AS $BODY$
  DROP TRIGGER sign_variants_allomorphs_trigger ON @extschema@.allomorphs;
  DROP TRIGGER sign_variants_allomorph_components_trigger ON @extschema@.allomorph_components;
  DROP TRIGGER sign_variants_allographs_trigger ON @extschema@.allographs;
  DROP TRIGGER sign_variants_composition_sign_variants_trigger ON @extschema@.sign_variants;
  DROP TRIGGER sign_variants_composition_graphemes_trigger ON @extschema@.graphemes;
  DROP TRIGGER sign_variants_composition_glyphs_trigger ON @extschema@.glyphs;
  DROP TRIGGER sign_variants_composition_allographs_trigger ON @extschema@.allographs;
$BODY$;


CALL signlist_create_triggers();