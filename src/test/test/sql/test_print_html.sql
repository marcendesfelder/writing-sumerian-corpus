
CREATE OR REPLACE FUNCTION print_html_lines (v_signs jsonb)
    RETURNS text[]
    STABLE
    LANGUAGE SQL
AS $BODY$
SELECT
    @extschema:cuneiform_print_html@.cun_agg_html(
        value,
        ordinality::integer - 1,
        COALESCE(word_no, 0),
        COALESCE(compound_no, 0),
        NULL,
        COALESCE(line_no, 0),
        COALESCE(type, 'sign'),
        COALESCE(indicator_type, 'none'),
        phonographic,
        stem,
        COALESCE(condition, 'intact'),
        language,
        COALESCE(inverted, FALSE),
        COALESCE(newline, FALSE),
        COALESCE(ligature, FALSE),
        crits,
        comment,
        COALESCE(capitalized, FALSE),
        pn_type,
        NULL,
        compound_comment,
        COALESCE(highlight, FALSE),
        VARIADIC ARRAY[]::integer[]
        ORDER BY ordinality)
FROM
    ROWS FROM (jsonb_to_recordset(v_signs) AS (
        value text,
        word_no integer,
        compound_no integer,
        line_no integer,
        type @extschema:cuneiform_sign_properties@.sign_type,
        indicator_type @extschema:cuneiform_sign_properties@.indicator_type,
        phonographic boolean,
        stem boolean,
        condition @extschema:cuneiform_sign_properties@.sign_condition,
        language @extschema:cuneiform_sign_properties@.language,
        inverted boolean,
        newline boolean,
        ligature boolean,
        crits text,
        comment text,
        capitalized boolean,
        pn_type @extschema:cuneiform_sign_properties@.pn_type,
        compound_comment text,
        highlight boolean)) WITH ORDINALITY;
$BODY$;


CREATE OR REPLACE FUNCTION html_lines_balanced (v_lines text[])
    RETURNS boolean
    IMMUTABLE
    LANGUAGE SQL
AS $BODY$
SELECT
    bool_and((length(line) - length(replace(line, '<span', ''))) / length('<span') = (length(line) - length(replace(line, '</span>', ''))) / length('</span>'))
FROM
    unnest(v_lines) AS _(line);
$BODY$;


CREATE OR REPLACE FUNCTION test_print_html_internal_conditions ()
    RETURNS SETOF text
    STABLE
    LANGUAGE PLPGSQL
    AS
$BODY$
BEGIN
RETURN NEXT is(
    @extschema@.print_html_lines('[{"value": "lu⸢gal⸣"}]'),
    ARRAY['lu<span class=''open-damaged''></span><span class=''damaged''>gal</span><span class=''close-damaged''></span>'],
    'multi-byte condition markers inside a value are replaced completely');
RETURN NEXT is(
    @extschema@.print_html_lines('[{"value": "e‹ša›"}, {"value": "a«a»", "word_no": 1}]'),
    ARRAY['e<span class=''open-inserted''></span><span class=''inserted''>ša</span><span class=''close-inserted''></span>–a<span class=''open-deleted''></span><span class=''deleted''>a</span><span class=''close-deleted''></span>'],
    'opening markers inside a value open, closing markers close');
END;
$BODY$;


CREATE OR REPLACE FUNCTION test_print_html_line_break ()
    RETURNS SETOF text
    STABLE
    LANGUAGE PLPGSQL
    AS
$BODY$
DECLARE
v_lines text[] := @extschema@.print_html_lines('[
    {"value": "a", "language": "akkadian", "condition": "lost"},
    {"value": "na", "language": "akkadian", "condition": "lost", "line_no": 1}
]');
BEGIN
RETURN NEXT is(
    v_lines,
    ARRAY[
        '<span class=''open-lost''></span><span class=''akkadian''><span class=''lost''>a</span></span><span class=''close-lost''></span>-',
        '<span class=''open-lost''></span><span class=''akkadian''><span class=''lost''>na</span></span><span class=''close-lost''></span>'],
    'spans running across a line break are closed and reopened');
RETURN NEXT ok(@extschema@.html_lines_balanced(v_lines), 'every line is balanced');
END;
$BODY$;


CREATE OR REPLACE FUNCTION test_print_html_inversion ()
    RETURNS SETOF text
    STABLE
    LANGUAGE PLPGSQL
    AS
$BODY$
BEGIN
RETURN NEXT is(
    @extschema@.print_html_lines('[
        {"value": "d", "indicator_type": "left", "phonographic": false},
        {"value": "en", "indicator_type": "left", "phonographic": true, "inverted": true}
    ]'),
    ARRAY['<span class=''logographic''><span class=''indicator''>d</span></span><span class=''indicator''>:</span><span class=''phonographic''><span class=''indicator''>en</span></span>'],
    'an inverted mixed indicator is marked as indicator');
END;
$BODY$;


CREATE OR REPLACE FUNCTION test_print_html_markup_size ()
    RETURNS SETOF text
    STABLE
    LANGUAGE PLPGSQL
    AS
$BODY$
DECLARE
v_lines text[];
BEGIN
-- Every sign changes every attribute and carries critics, comments and internal conditions,
-- so each one produces close to the maximum markup on a single line.
SELECT
    @extschema@.print_html_lines(
        jsonb_agg(
            jsonb_build_object(
                'value', CASE WHEN i % 2 = 0 THEN 'lu⸢gal⸣' ELSE '[KA]' END,
                'word_no', i,
                'compound_no', i,
                'language', CASE WHEN i % 2 = 0 THEN 'akkadian' ELSE 'hurrian' END,
                'stem', i % 2 = 0,
                'highlight', i % 2 = 1,
                'phonographic', i % 2 = 0,
                'indicator_type', CASE WHEN i % 2 = 0 THEN 'none' ELSE 'right' END,
                'condition', CASE i % 3 WHEN 0 THEN 'damaged' WHEN 1 THEN 'inserted' ELSE 'lost' END,
                'crits', '!?',
                'comment', 'comment',
                'compound_comment', 'compound comment',
                'newline', true)
            ORDER BY i))
INTO v_lines
FROM generate_series(0, 499) AS _(i);
RETURN NEXT is(cardinality(v_lines), 1, 'all signs are printed on one line');
RETURN NEXT ok(@extschema@.html_lines_balanced(v_lines), 'the line is balanced');
END;
$BODY$;
