CREATE OR REPLACE FUNCTION cun_agg_html_sfunc (
    internal, 
    text, 
    integer, 
    integer, 
    integer, 
    integer, 
    integer,
    @extschema:cuneiform_sign_properties@.sign_type,
    @extschema:cuneiform_sign_properties@.indicator_type,
    boolean,
    boolean, 
    @extschema:cuneiform_sign_properties@.sign_condition, 
    language, 
    boolean, 
    boolean, 
    boolean,
    text, 
    text,
    boolean,
    @extschema:cuneiform_sign_properties@.pn_type,
    text,
    text,
    boolean,
    VARIADIC integer[]
    )
    RETURNS internal
    AS 'cuneiform_print_html'
,
    'cuneiform_cun_agg_html_sfunc'
    LANGUAGE C
    IMMUTABLE
    COST 10000;

CREATE OR REPLACE FUNCTION cun_agg_html_finalfunc (internal)
    RETURNS text[]
    AS 'cuneiform_print_html'
,
    'cuneiform_cun_agg_html_finalfunc'
    LANGUAGE C
    STRICT 
    IMMUTABLE
    COST 100;

CREATE AGGREGATE cun_agg_html (
    text, 
    integer, 
    integer, 
    integer, 
    integer, 
    integer,
    @extschema:cuneiform_sign_properties@.sign_type,
    @extschema:cuneiform_sign_properties@.indicator_type,
    boolean,
    boolean, 
    @extschema:cuneiform_sign_properties@.sign_condition, 
    language, 
    boolean, 
    boolean, 
    boolean,
    text, 
    text,
    boolean,
    @extschema:cuneiform_sign_properties@.pn_type,
    text,
    text,
    boolean,
    VARIADIC integer[]
    ) (
    SFUNC = cun_agg_html_sfunc,
    STYPE = internal,
    FINALFUNC = cun_agg_html_finalfunc
);



CREATE OR REPLACE FUNCTION placeholder_html (v_type @extschema:cuneiform_sign_properties@.sign_type)
    RETURNS text
    STRICT
    IMMUTABLE
    LANGUAGE SQL
BEGIN ATOMIC
    SELECT
        '<span class="placeholder">' 
        ||
        CASE v_type
        WHEN 'number' THEN
            'N'
        WHEN 'description' THEN
            'DESC'
        WHEN 'punctuation' THEN
            '|'
        WHEN 'damage' THEN
            '…'
        ELSE
            'X'
        END 
        ||
        '</span>';
END;


CREATE OR REPLACE FUNCTION print_value_html(v_value text)
    RETURNS text
    IMMUTABLE
    LANGUAGE SQL
BEGIN ATOMIC
    SELECT regexp_replace(v_value, '(?<=[^0-9x])([0-9x]+)$', '<span class=''index''>\1</span>');
END;

CREATE OR REPLACE FUNCTION print_sign_html(v_sign text)
    RETURNS text
    IMMUTABLE
    LANGUAGE SQL
BEGIN ATOMIC
    SELECT compose_sign_html(@extschema:cuneiform_signlist@.parse_sign(v_sign));
END;

CREATE OR REPLACE FUNCTION print_unknown_value_html(v_segments text)
    RETURNS text
    IMMUTABLE
    LANGUAGE SQL
BEGIN ATOMIC
    SELECT '<span class=''unknown_value''>' || v_segments || '</span>';
END;

CREATE OR REPLACE FUNCTION print_spec_html (
        v_variant_type @extschema:cuneiform_signlist@.sign_variant_type,
        v_graphemes text, 
        v_glyphs text
    )
    RETURNS text
    IMMUTABLE
    LANGUAGE SQL
BEGIN ATOMIC
    SELECT 
        CASE 
            WHEN v_variant_type = 'default' THEN '<span class=''signspec''>' || v_graphemes || '</span>'
            WHEN v_variant_type = 'nondefault' THEN '<span class=''signspec''>' || v_glyphs || '</span>' 
            ELSE '<span class=''critic''>!</span><span class=''signspec''>' || v_glyphs || '</span>'
        END;
END;

CALL @extschema:cuneiform_print_core@.create_signlist_print(
    'html', 
    '@extschema@', 
    'print_value_html', 
    'print_spec_html', 
    'print_sign_html', 
    'print_sign_html',
    'print_unknown_value_html'
);


CREATE OR REPLACE FUNCTION print_number_html(v_number text)
  RETURNS text
  STABLE
  COST 1000
  LANGUAGE SQL
BEGIN ATOMIC
    SELECT 
        string_agg(
            regexp_replace(part, '([!?*]+)', '<span class=''critics''>\1</span>', 'g') 
                || COALESCE('<span class=''signspec''>' || @extschema@.print_sign_html(spec) || '</span>', ''), 
            '' 
            ORDER BY ordinality
        ) 
    FROM @extschema:cuneiform_print_core@.extract_number_specs(v_number) WITH ORDINALITY;
END;


CREATE OR REPLACE FUNCTION print_sign_meanings_html (v_sign_meanings @extschema:cuneiform_sign_meanings@.sign_meaning[])
  RETURNS text
  STABLE
  COST 1000
  LANGUAGE SQL
BEGIN ATOMIC
    SELECT
        (cun_agg_html (character_print, ordinality::integer, word_no, 0, NULL, 0, 'sign'::@extschema:cuneiform_sign_properties@.sign_type, indicator_type, phonographic, stem, 'intact'::@extschema:cuneiform_sign_properties@.sign_condition, NULL, 
            FALSE, FALSE, FALSE, NULL, NULL, capitalized, NULL, NULL, NULL, FALSE, VARIADIC ARRAY[]::integer[] ORDER BY ordinality))[1]
    FROM
        unnest(v_sign_meanings) WITH ORDINALITY
        LEFT JOIN @extschema:cuneiform_signlist@.sign_variants USING (sign_id)
        LEFT JOIN characters_html ON characters_html.sign_variant_id = sign_variants.sign_variant_id AND unnest.value_id IS NOT DISTINCT FROM characters_html.value_id
    WHERE
        variant_type = 'default';
END;