from py2plpy import plpy, InOut, sql_properties

class language:
    pass

@sql_properties(procedure=True)
def parse_replacement(code: str, id: InOut[int]):
    from writingsumerianparser import parse
    import pandas as pd

    id = plpy.execute("SELECT nextval('@extschema@.replace_id_seq') AS id")[0]['id']

    corpus_plan = plpy.prepare(
    f"""
        INSERT INTO @extschema@.replace_pattern_corpus
        SELECT 
            {id}, 
            ordinality::integer-1, 
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
            stem
        FROM
            UNNEST($1) WITH ORDINALITY AS a
            LEFT JOIN @extschema@.replace_pattern_corpus_encoder ON pattern_id = {id} AND sign_no = ordinality-1
        """,
        ['@extschema:cuneiform_parser@.corpus_parser_type[]']
    )

    corpus_unencoded_plan = plpy.prepare(
        f"""
        INSERT INTO @extschema@.replace_pattern_corpus_unencoded
        SELECT
            {id},
            ordinality::integer-1, 
            value, 
            sign_spec, 
            unknown_reading
        FROM
            UNNEST($1) WITH ORDINALITY
        WHERE
            type = 'sign'
            """, 
        ['@extschema:cuneiform_parser@.corpus_parser_type[]']
    )

    words_plan = plpy.prepare(
        f"""
        INSERT INTO @extschema@.replace_pattern_words
        SELECT 
            {id}, 
            ordinality::integer-1, 
            compound_no, 
            capitalized
        FROM
            UNNEST($1) WITH ORDINALITY
        """,
        ['@extschema:cuneiform_parser@.words_parser_type[]']
    )

    compounds_plan = plpy.prepare(
        f"""
        INSERT INTO @extschema@.replace_pattern_compounds 
        SELECT 
            {id}, 
            ordinality::integer-1, 
            pn_type,
            language
        FROM
            UNNEST($1) WITH ORDINALITY
        """,
        ['@extschema:cuneiform_parser@.compounds_parser_type[]']
    )

    signs, compounds, words, _, errors = parse(code)

    plpy.execute(f"DELETE FROM @extschema@.replace_pattern_corpus_unencoded WHERE pattern_id = {id}")

    plpy.execute(compounds_plan, [[(x[0], x[1], x[2] if x[2] is not pd.NA else None, x[3]) for x in compounds.itertuples(index=False)]])
    plpy.execute(words_plan, [list(words.to_records(index=False))])
    signs_tup = list(signs.to_records(index=False))
    plpy.execute(corpus_unencoded_plan, [signs_tup])
    plpy.execute(corpus_plan, [signs_tup])

    r = plpy.execute(f"""
        SELECT 
            count(*)
        FROM 
            @extschema@.replace_pattern_corpus
        WHERE
            pattern_id = {id}
            AND type = 'sign'
            AND sign_variant_id IS NULL
        """)

    if len(errors.index):
        plpy.error('cuneiform_replace syntax error', sqlstate=22000)
    if r[0]['count']:
        plpy.error('cuneiform_replace encoding error', sqlstate=22000)

    return {'id': id}