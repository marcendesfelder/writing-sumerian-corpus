CREATE VIEW values_encoded_view AS
WITH a(value, sign_spec, value_id, sign_variant_id) AS (
    SELECT
        value,
        glyphs,
        value_id,
        sign_variant_id,
        variant_type
    FROM
        value_variants
        JOIN values USING (value_id)
        JOIN sign_variants_composition USING (sign_id)
    UNION ALL
    SELECT
        value,
        null,
        value_id,
        sign_variant_id,
        variant_type
    FROM
        value_variants
        JOIN values USING (value_id)
        JOIN sign_variants_composition USING (sign_id)
    WHERE
        variant_type = 'default'
        AND NOT value ~ 'x'
    UNION ALL
    SELECT
        regexp_replace(value, '[0-9]*$', 'x'),
        glyphs,
        value_id,
        sign_variant_id,
        variant_type
    FROM
        value_variants
        JOIN values USING (value_id)
        JOIN sign_variants_composition USING (sign_id)
    WHERE
        NOT value ~ 'x'
    UNION ALL
    SELECT
        value,
        glyphs,
        value_id,
        sign_variant_id,
        variant_type
    FROM
        glyph_values 
        JOIN values USING (value_id)
        JOIN sign_variants_composition USING (sign_id, glyph_ids)
    UNION ALL
    SELECT
        value,
        null,
        value_id,
        sign_variant_id,
        variant_type
    FROM
        glyph_values 
        JOIN values USING (value_id)
        JOIN sign_variants_composition USING (sign_id, glyph_ids)
)
SELECT DISTINCT ON (value, sign_spec)
    value,
    sign_spec,
    value_id,
    sign_variant_id
FROM
    a
ORDER BY
    value,
    sign_spec,
    variant_type,
    value_id,
    sign_variant_id;



CREATE VIEW signs_encoded_view (sign, sign_spec, sign_variant_id) AS
SELECT
    glyphs,
    null,
    sign_variant_id
FROM
    sign_variants_composition
WHERE
    specific
UNION ALL
SELECT
    a.glyphs,
    b.glyphs,
    b.sign_variant_id
FROM
    sign_variants_composition a
    JOIN sign_variants_composition b USING (sign_id)
WHERE
    a.variant_type = 'default';


CREATE TABLE values_encoded (
    value text NOT NULL,
    sign_spec text,
    value_id integer NOT NULL,
    sign_variant_id integer NOT NULL,
    UNIQUE NULLS NOT DISTINCT (value, sign_spec)
);

CREATE TABLE signs_encoded (
    sign text NOT NULL,
    sign_spec text,
    sign_variant_id integer NOT NULL
);

CREATE INDEX ON signs_encoded (sign, sign_spec);


CREATE OR REPLACE FUNCTION encoder_rebuild ()
  RETURNS void
  VOLATILE
  LANGUAGE PLPGSQL
  AS
$BODY$
BEGIN
    DELETE FROM @extschema@.values_encoded;
    INSERT INTO @extschema@.values_encoded SELECT * FROM @extschema@.values_encoded_view;
    DELETE FROM @extschema@.signs_encoded;
    INSERT INTO @extschema@.signs_encoded SELECT * FROM @extschema@.signs_encoded_view;
    PERFORM set_config('cuneiform_encoder.stale', 'false', true);
END;
$BODY$;


-- changes to the signlist only mark the tables as stale, they are rebuilt once at commit
CREATE OR REPLACE FUNCTION encoder_mark_stale_trigger_fun ()
  RETURNS trigger
  VOLATILE
  LANGUAGE PLPGSQL
  AS
$BODY$
BEGIN
    PERFORM set_config('cuneiform_encoder.stale', 'true', true);
    RETURN NULL;
END;
$BODY$;


CREATE OR REPLACE FUNCTION encoder_rebuild_trigger_fun ()
  RETURNS trigger
  VOLATILE
  LANGUAGE PLPGSQL
  AS
$BODY$
BEGIN
    IF current_setting('cuneiform_encoder.stale', true) = 'true' THEN
        PERFORM @extschema@.encoder_rebuild();
    END IF;
    RETURN NULL;
END;
$BODY$;


CREATE OR REPLACE PROCEDURE encoder_create_triggers()
    LANGUAGE PLPGSQL
AS $BODY$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY['values', 'value_variants', 'glyph_values', 'sign_variants_composition'] LOOP
        EXECUTE format(
            $$
            CREATE TRIGGER %2$I
                AFTER INSERT OR UPDATE OR DELETE ON @extschema:cuneiform_signlist@.%1$I
                FOR EACH STATEMENT
                EXECUTE FUNCTION @extschema@.encoder_mark_stale_trigger_fun();
            CREATE CONSTRAINT TRIGGER %3$I
                AFTER INSERT OR UPDATE OR DELETE ON @extschema:cuneiform_signlist@.%1$I
                DEFERRABLE INITIALLY DEFERRED
                FOR EACH ROW
                EXECUTE FUNCTION @extschema@.encoder_rebuild_trigger_fun();
            $$,
            v_table,
            'encoder_' || v_table || '_stale_trigger',
            'encoder_' || v_table || '_rebuild_trigger'
        );
    END LOOP;
END;
$BODY$;


CREATE OR REPLACE PROCEDURE encoder_drop_triggers()
    LANGUAGE PLPGSQL
AS $BODY$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY['values', 'value_variants', 'glyph_values', 'sign_variants_composition'] LOOP
        EXECUTE format('DROP TRIGGER %I ON @extschema:cuneiform_signlist@.%I', 'encoder_' || v_table || '_stale_trigger', v_table);
        EXECUTE format('DROP TRIGGER %I ON @extschema:cuneiform_signlist@.%I', 'encoder_' || v_table || '_rebuild_trigger', v_table);
    END LOOP;
END;
$BODY$;


SELECT encoder_rebuild();

CALL encoder_create_triggers();


CREATE TYPE corpus_unencoded_type AS (
    sign_no integer,
    value text,
    sign_spec text,
    unknown_reading boolean
);


CREATE OR REPLACE PROCEDURE create_corpus_encoder (v_name text, v_source text, v_key text[], v_schema text = 'public')
    LANGUAGE PLPGSQL
    AS 
$BODY$
DECLARE
    v_key_str text;
BEGIN

    SELECT string_agg(format('%I', val), ', ') INTO v_key_str FROM unnest(v_key) AS _(val);

    EXECUTE format(
        $$
        CREATE OR REPLACE VIEW %3$I.%4$I AS
            WITH normalized_signs AS NOT MATERIALIZED (
                    WITH x AS (
                        SELECT
                            %1$s,
                            sign_no,
                            glyph_no,
                            @extschema:cuneiform_signlist@.normalize_operators(string_agg(op||COALESCE('('||glyphs||')', ''), '' ORDER BY component_no)) AS glyphs
                        FROM
                            %3$I.%2$I
                            LEFT JOIN LATERAL @extschema:cuneiform_signlist@.split_glyphs(value) WITH ORDINALITY AS a(glyph, glyph_no) ON TRUE
                            LEFT JOIN LATERAL @extschema:cuneiform_signlist@.split_sign(glyph) WITH ORDINALITY AS b(component, op, component_no) ON TRUE
                            LEFT JOIN @extschema:cuneiform_signlist@.sign_map ON component = identifier
                        WHERE unknown_reading
                        GROUP BY 
                            %1$s,
                            sign_no,
                            glyph_no
                    )
                    SELECT 
                        %1$s,
                        sign_no,
                        string_agg(glyphs, '.' ORDER BY glyph_no) AS glyphs
                    FROM
                        x
                    GROUP BY
                        %1$s,
                        sign_no),
                normalized_sign_specs AS NOT MATERIALIZED (
                    WITH x AS (
                        SELECT
                            %1$s,
                            sign_no,
                            glyph_no,
                            @extschema:cuneiform_signlist@.normalize_operators(string_agg(op||COALESCE('('||glyphs||')', ''), '' ORDER BY component_no)) AS glyphs
                        FROM
                            %3$I.%2$I
                            LEFT JOIN LATERAL @extschema:cuneiform_signlist@.split_glyphs(sign_spec) WITH ORDINALITY AS a(glyph, glyph_no) ON TRUE
                            LEFT JOIN LATERAL @extschema:cuneiform_signlist@.split_sign(glyph) WITH ORDINALITY AS b(component, op, component_no) ON TRUE
                            LEFT JOIN @extschema:cuneiform_signlist@.sign_map ON component = identifier
                        WHERE sign_spec IS NOT NULL
                        GROUP BY 
                            %1$s,
                            sign_no,
                            glyph_no
                    )
                    SELECT 
                        %1$s,
                        sign_no,
                        string_agg(glyphs, '.' ORDER BY glyph_no) AS glyphs
                    FROM
                        x
                    GROUP BY
                        %1$s,
                        sign_no)
                SELECT
                    %1$s,
                    sign_no,
                    value_id,
                    sign_variant_id
                FROM
                    %3$I.%2$I s
                    LEFT JOIN normalized_sign_specs USING (%1$s, sign_no)
                    JOIN @extschema@.values_encoded ON normalized_sign_specs.glyphs IS NOT DISTINCT FROM values_encoded.sign_spec AND s.value = values_encoded.value
                WHERE 
                    NOT s.unknown_reading
                UNION ALL
                SELECT
                    %1$s,
                    sign_no,
                    NULL,
                    sign_variant_id
                FROM
                    %3$I.%2$I s
                    LEFT JOIN normalized_signs USING (%1$s, sign_no)
                    LEFT JOIN normalized_sign_specs USING (%1$s, sign_no)
                    JOIN @extschema@.signs_encoded ON normalized_signs.glyphs = signs_encoded.sign AND normalized_sign_specs.glyphs IS NOT DISTINCT FROM signs_encoded.sign_spec
                WHERE 
                    s.unknown_reading
        $$,
        v_key_str,
        v_source,
        v_schema,
        v_name
    );
END
$BODY$;