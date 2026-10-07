CREATE TYPE corpus_parsed_unencoded_type AS (
    transliteration_id integer,
    sign_no integer,
    value text,
    sign_spec text,
    type @extschema:cuneiform_sign_properties@.sign_type,
    line_no_code integer,
    start_col_code integer,
    stop_col_code integer
);

CREATE TYPE errors_type AS (
    transliteration_id integer,
    line integer,
    col integer,
    symbol text,
    message text
);


CREATE TYPE sections_parser_type AS (
    section_name text,
    composition text
);

CREATE TYPE compounds_parser_type AS (
    pn_type @extschema:cuneiform_sign_properties@.pn_type,
    language @extschema:cuneiform_sign_properties@.language,
    section_no integer,
    comment text
);

CREATE TYPE words_parser_type AS (
    compound_no integer,
    capitalized boolean
);

CREATE TYPE surfaces_parser_type AS (
    surface @extschema:cuneiform_create_corpus@.surface_type, 
    data text,
    comment text
);

CREATE TYPE blocks_parser_type AS (
    surface_no integer, 
    block @extschema:cuneiform_create_corpus@.block_type, 
    data text, 
    comment text
);

CREATE TYPE lines_parser_type AS (
    block_no integer, 
    line text, 
    comment text
);

CREATE TYPE corpus_parser_type AS (
    line_no integer, 
    word_no integer, 
    value text, 
    sign_spec text, 
    type @extschema:cuneiform_sign_properties@.sign_type,  
    indicator_type @extschema:cuneiform_sign_properties@.indicator_type,
    phonographic boolean,
    condition @extschema:cuneiform_sign_properties@.sign_condition,
    stem boolean,
    crits text, 
    comment text,
    newline boolean,
    inverted boolean,
    ligature boolean,
    start_col integer,
    stop_col integer
);

CREATE TYPE corpus_parser_ext_type AS (
    line_no integer, 
    word_no integer, 
    value text, 
    sign_spec text, 
    type @extschema:cuneiform_sign_properties@.sign_type,  
    indicator_type @extschema:cuneiform_sign_properties@.indicator_type,
    phonographic boolean,
    condition @extschema:cuneiform_sign_properties@.sign_condition,
    stem boolean,
    crits text, 
    comment text,
    newline boolean,
    inverted boolean,
    ligature boolean,
    start_col integer,
    stop_col integer,
    line_no_code integer, 
    start_col_code integer, 
    stop_col_code integer
);

CREATE TYPE errors_parser_type AS (
    line_no integer, 
    "column" integer, 
    symbol text, 
    msg text
);



CREATE OR REPLACE PROCEDURE parse (
        code text, 
        id integer,
        schema text,
        compositions_schema text DEFAULT NULL
    )
    LANGUAGE PLPYTHON3U
    AS $BODY$

from writingsumerianparser import parseText
import pandas as pd

compositionsSchema = schema if compositions_schema is None else compositions_schema

corpus_plan = plpy.prepare(
    f"""
    INSERT INTO {schema}.corpus 
    SELECT 
        {id}, 
        ordinality::integer-1, 
        line_no, 
        word_no, 
        value_id, 
        sign_variant_id, 
        CASE WHEN sign_variant_id IS NOT NULL THEN 
            NULL 
        ELSE 
            value  || COALESCE('(' || sign_spec || ')', '') 
        END, 
        a.type, 
        indicator_type, 
        phonographic, 
        stem, 
        condition, 
        crits, 
        comment, 
        newline, 
        inverted, 
        ligature
    FROM
        UNNEST($1) WITH ORDINALITY AS a
        LEFT JOIN {schema}.corpus_encoder ON transliteration_id = {id} AND sign_no = ordinality-1
    """,
    ['@extschema@.corpus_parser_ext_type[]']
)

corpus_unencoded_plan = plpy.prepare(
    f"""
    INSERT INTO {schema}.corpus_parsed_unencoded
    SELECT
        {id},
        ordinality::integer-1, 
        value, 
        sign_spec, 
        type,
        line_no_code,
        start_col_code,
        stop_col_code
    FROM
        UNNEST($1) WITH ORDINALITY
    WHERE
        type = 'value' OR type = 'sign'
        """, 
    ['@extschema@.corpus_parser_ext_type[]']
)

words_plan = plpy.prepare(
    f"""
    INSERT INTO {schema}.words 
    SELECT 
        {id}, 
        ordinality::integer-1, 
        compound_no, 
        capitalized
    FROM
        UNNEST($1) WITH ORDINALITY
    """,
    ['@extschema@.words_parser_type[]']
)

compounds_plan = plpy.prepare(
    f"""
    INSERT INTO {schema}.compounds 
    SELECT 
        {id}, 
        ordinality::integer-1, 
        pn_type,
        language,
        section_no,
        comment
    FROM
        UNNEST($1) WITH ORDINALITY
    """,
    ['@extschema@.compounds_parser_type[]']
)

sections_plan = plpy.prepare(
    f"""
    INSERT INTO {schema}.sections 
    SELECT 
        {id}, 
        ordinality::integer-1, 
        section_name, 
        composition_id
    FROM
        UNNEST($1) WITH ORDINALITY
        LEFT JOIN {compositionsSchema}.compositions ON composition_name = composition
    """,
    ['@extschema@.sections_parser_type[]']
)

surfaces_plan = plpy.prepare(
    f"""
    INSERT INTO {schema}.surfaces 
    SELECT 
        {id}, 
        ordinality::integer-1, 
        surface, 
        data,
        comment
    FROM
        UNNEST($1) WITH ORDINALITY
    """,
    ['@extschema@.surfaces_parser_type[]']
)

blocks_plan = plpy.prepare(
    f"""
    INSERT INTO {schema}.blocks 
    SELECT 
        {id}, 
        ordinality::integer-1, 
        surface_no,
        block, 
        data,
        comment
    FROM
        UNNEST($1) WITH ORDINALITY
    """,
    ['@extschema@.blocks_parser_type[]']
)

lines_plan = plpy.prepare(
    f"""
    INSERT INTO {schema}.lines 
    SELECT 
        {id}, 
        ordinality::integer-1, 
        block_no, 
        line,
        comment
    FROM
        UNNEST($1) WITH ORDINALITY
    """,
    ['@extschema@.lines_parser_type[]']
)

errors_plan = plpy.prepare(
    f"""
    INSERT INTO {schema}.errors 
    SELECT 
        {id}, 
        line_no, 
        "column", 
        symbol, 
        msg
    FROM
        UNNEST($1)
    """,
    ['@extschema@.errors_parser_type[]']
)

surfaces, blocks, lines, signs, compounds, words, sections, errors = parseText(code)

plpy.execute(f"DELETE FROM {schema}.corpus_parsed_unencoded WHERE transliteration_id = {id}")

plpy.execute(sections_plan, [list(sections.to_records(index=False))])
plpy.execute(compounds_plan, [[(x[0], x[1], x[2] if x[2] is not pd.NA else None, x[3]) for x in compounds.itertuples(index=False)]])
plpy.execute(words_plan, [list(words.to_records(index=False))])

plpy.execute(surfaces_plan, [list(surfaces.to_records(index=False))])
plpy.execute(blocks_plan, [list(blocks.to_records(index=False))])
plpy.execute(lines_plan, [list(lines.to_records(index=False))])

signs_tup = list(signs.to_records(index=False))
plpy.execute(corpus_unencoded_plan, [signs_tup])
plpy.execute(corpus_plan, [signs_tup])

plpy.execute(errors_plan, [list(errors.to_records(index=False))])

plpy.execute(f"""
    DELETE FROM {schema}.corpus_parsed_unencoded
    USING {schema}.corpus
    WHERE
        corpus.transliteration_id = corpus_parsed_unencoded.transliteration_id AND 
        corpus.transliteration_id = {id} AND
        corpus.sign_no = corpus_parsed_unencoded.sign_no AND
        sign_variant_id IS NOT NULL
    """)

$BODY$;



CREATE OR REPLACE FUNCTION parse_to_sign_meanings (
        code text
    )
    RETURNS @extschema:cuneiform_sign_properties@.sign_meaning[]
    STABLE
    LANGUAGE PLPYTHON3U
    AS 
$BODY$

from writingsumerianparser import parse

plan = plpy.prepare(
        f"""
        WITH corpus AS (
            SELECT
                *,
                ordinality = min(ordinality) OVER (PARTITION BY word_no) AS new_word
            FROM
                UNNEST($1) WITH ORDINALITY
        )
        SELECT 
            array_agg(
                (
                    word_no, 
                    value_id,
                    sign_id,
                    indicator_type, 
                    phonographic, 
                    stem,
                    CASE WHEN new_word THEN capitalized ELSE FALSE END
                )::@extschema:cuneiform_sign_properties@.sign_meaning
                ORDER BY corpus.ordinality
            ) AS sign_meanings
        FROM
            corpus
            LEFT JOIN UNNEST($2) WITH ORDINALITY AS words ON corpus.word_no = words.ordinality-1
            LEFT JOIN LATERAL @extschema:cuneiform_signlist@.normalize_glyphs(sign_spec) AS _(sign_spec_normlized) ON TRUE
            LEFT JOIN LATERAL @extschema:cuneiform_signlist@.normalize_glyphs(value) AS __(sign_normalized) ON type = 'sign'
            LEFT JOIN @extschema:cuneiform_encoder@.values_encoded ON type = 'value' AND corpus.value = values_encoded.value AND sign_spec_normlized IS NOT DISTINCT FROM values_encoded.sign_spec
            LEFT JOIN @extschema:cuneiform_encoder@.signs_encoded ON type = 'sign' AND sign_normalized = signs_encoded.sign AND sign_spec_normlized IS NOT DISTINCT FROM signs_encoded.sign_spec
            LEFT JOIN @extschema:cuneiform_signlist@.sign_variants ON sign_variants.sign_variant_id = COALESCE(values_encoded.sign_variant_id, signs_encoded.sign_variant_id)
        GROUP BY
            compound_no
        HAVING
            bool_and(sign_id IS NOT NULL)
        """,
        ['@extschema@.corpus_parser_type[]', '@extschema@.words_parser_type[]']
)

signs, compounds, words, _, errors = parse(code)

if len(errors.index):
    plpy.error('cuneiform_parser syntax error', sqlstate=22000)
if len(compounds.index) != 1:
    plpy.error('cuneiform_parser compound error', sqlstate=22000)

r = plpy.execute(plan, [list(signs.to_records(index=False)), list(words.to_records(index=False))])

if r.nrows() != 1:
    plpy.error('cuneiform_parse encoding error', sqlstate=22000)

return r[0]['sign_meanings']

$BODY$;