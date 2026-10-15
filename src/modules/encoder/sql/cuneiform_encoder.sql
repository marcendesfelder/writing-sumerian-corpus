CREATE OR REPLACE VIEW values_encoded AS
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
    variant_type;



CREATE VIEW signs_encoded (sign, sign_spec, sign_variant_id) AS
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