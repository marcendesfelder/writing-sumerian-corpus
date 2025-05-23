CREATE OR REPLACE PROCEDURE replace (
    v_search_term text, 
    v_pattern text,
    v_user_id integer,
    v_internal boolean,
    v_subcommit boolean DEFAULT false,
    v_period_ids integer[] DEFAULT ARRAY[]::integer[],
    v_provenience_ids integer[] DEFAULT ARRAY[]::integer[],
    v_genre_ids integer[] DEFAULT ARRAY[]::integer[]
    )
    LANGUAGE PLPGSQL
AS $BODY$

DECLARE

    v_search_term_norm text;
    v_wildcards_explicit integer[];
    v_pattern_id integer;
    v_transliteration_id integer;
    v_sign_nos integer[];
    v_match_nos integer[];
    v_reference_ids integer[];
    v_reference_sign_nos integer[];
    v_reference_match_nos integer[];
    v_overlap boolean;
    v_invalid_sign_nos integer[];
    v_invalid_compound_nos integer[];

BEGIN

    CREATE TEMPORARY TABLE IF NOT EXISTS corpus_replace (LIKE @extschema:cuneiform_replace@.corpus_replace_type);
    CREATE TEMPORARY TABLE IF NOT EXISTS words (LIKE @extschema:cuneiform_corpus@.words);
    CREATE TEMPORARY TABLE IF NOT EXISTS compounds (LIKE @extschema:cuneiform_corpus@.compounds);
    CREATE OR REPLACE TEMPORARY VIEW corpus AS SELECT transliteration_id, sign_no, line_no, word_no, value_id, sign_variant_id, custom_value, type, indicator_type, phonographic, stem, condition, crits, comment, newline, inverted, ligature FROM pg_temp.corpus_replace;
    CREATE OR REPLACE TEMPORARY VIEW lines AS SELECT * FROM @extschema:cuneiform_corpus@.lines;
    CREATE OR REPLACE TEMPORARY VIEW blocks AS SELECT * FROM @extschema:cuneiform_corpus@.blocks;
    CREATE OR REPLACE TEMPORARY VIEW surfaces AS SELECT * FROM @extschema:cuneiform_corpus@.surfaces;
    CREATE OR REPLACE TEMPORARY VIEW sections AS SELECT * FROM @extschema:cuneiform_corpus@.sections;

    CALL @extschema:cuneiform_replace@.parse_replacement(v_pattern, v_pattern_id);

    SELECT 
        preparse_search.code,
        preparse_search.wildcards_explicit
    INTO
        v_search_term_norm,
        v_wildcards_explicit
    FROM
        @extschema:cuneiform_search@.preparse_search(v_search_term);

    FOR v_transliteration_id, v_sign_nos, v_match_nos, v_reference_ids, v_reference_sign_nos, v_reference_match_nos, v_overlap IN 
        WITH 
        results AS (
            SELECT 
                row_number() OVER (PARTITION BY transliteration_id ORDER BY sign_nos[1]) AS match_no, 
                * 
            FROM 
                @extschema:cuneiform_search_corpus@.search(v_search_term_norm, v_period_ids, v_provenience_ids, v_genre_ids)
        ),
        sign_nos_ AS (
            SELECT
                transliteration_id,
                sign_no,
                match_no,
                count(*) OVER (PARTITION BY transliteration_id, sign_no) AS count
            FROM
                results
                LEFT JOIN LATERAL unnest(sign_nos) AS a(sign_no) ON TRUE
        ),
        sign_nos AS (
            SELECT
                transliteration_id,
                array_agg(sign_no) AS sign_nos,
                array_agg(match_no) AS match_nos,
                max(count) > 1 AS overlap
            FROM
                sign_nos_
            GROUP BY
                transliteration_id
        ),
        "references" AS (
            SELECT 
                transliteration_id, 
                array_agg(reference_id ORDER BY reference_id, ord) FILTER (WHERE reference_id IS NOT NULL) AS reference_ids, 
                array_agg(c.sign_no ORDER BY reference_id, ord) FILTER (WHERE reference_id IS NOT NULL) AS reference_sign_nos,
                array_agg(match_no ORDER BY reference_id, ord) FILTER (WHERE reference_id IS NOT NULL) AS reference_match_nos
            FROM    
                results
                LEFT JOIN LATERAL unnest(wildcards) AS b ON TRUE
                LEFT JOIN LATERAL unnest(b.sign_nos) WITH ORDINALITY AS c(sign_no, ord) ON TRUE
                LEFT JOIN LATERAL unnest(v_wildcards_explicit) WITH ORDINALITY AS _(wildcard_id, reference_id) USING (wildcard_id)
            GROUP BY
                transliteration_id
        )
        SELECT
            transliteration_id,
            sign_nos,
            match_nos,
            reference_ids,
            reference_sign_nos,
            reference_match_nos,
            overlap
        FROM
            sign_nos
            LEFT JOIN "references" USING (transliteration_id)
    LOOP
        IF v_overlap THEN
            RAISE NOTICE 'Skipping %, %: Overlapping match', v_transliteration_id, v_sign_nos;
            CONTINUE;
        END IF;
        BEGIN
            INSERT INTO pg_temp.corpus_replace SELECT * FROM @extschema:cuneiform_replace@.corpus_replace(v_transliteration_id, v_pattern_id, v_sign_nos, v_match_nos, v_reference_ids, v_reference_sign_nos, v_reference_match_nos, '@extschema:cuneiform_corpus@');
            INSERT INTO pg_temp.words SELECT * FROM @extschema:cuneiform_replace@.words_replace(v_transliteration_id, 'corpus_replace', 'pg_temp', '@extschema:cuneiform_corpus@');
            INSERT INTO pg_temp.compounds SELECT * FROM @extschema:cuneiform_replace@.compounds_replace(v_transliteration_id, 'corpus_replace', 'pg_temp', '@extschema:cuneiform_corpus@');
            
            SELECT array_agg(sign_no) INTO v_invalid_sign_nos FROM pg_temp.corpus_replace WHERE NOT valid;
            SELECT array_agg(compound_no) INTO v_invalid_compound_nos 
            FROM (
                SELECT compound_no FROM @extschema:cuneiform_corpus@.compounds WHERE transliteration_id = v_transliteration_id AND compound_comment IS NOT NULL
                EXCEPT SELECT compound_no_ref FROM pg_temp.corpus_replace WHERE NOT pattern_compound
            )_;
                
            IF NOT v_invalid_sign_nos IS NULL THEN
                RAISE NOTICE 'Skipping %, %: Invalid replacement near %', v_transliteration_id, v_sign_nos, v_invalid_sign_nos;
            ELSIF NOT v_invalid_compound_nos IS NULL THEN
                RAISE NOTICE 'Skipping %, %: Cannot remove compounds %', v_transliteration_id, v_sign_nos, v_invalid_compound_nos;
            ELSE
                RAISE NOTICE 'Replacing signs % in %...', v_sign_nos, v_transliteration_id;
                CALL @extschema:cuneiform_search_corpus@.corpus_search_drop_triggers();
                CALL @extschema:cuneiform_edit_corpus@.edit_corpus('pg_temp', v_transliteration_id, v_user_id, v_internal);
                CALL @extschema:cuneiform_search_corpus@.corpus_search_create_triggers();
                CALL @extschema:cuneiform_search_corpus@.corpus_search_update_transliteration(v_transliteration_id);
                RAISE NOTICE 'Done.';
            END IF;

        EXCEPTION
            WHEN not_null_violation THEN RAISE NOTICE 'Skipping %: Signs missing in replacement', v_transliteration_id;
        END;

        TRUNCATE pg_temp.corpus_replace;
        TRUNCATE pg_temp.words;
        TRUNCATE pg_temp.compounds;

        IF v_subcommit THEN
            COMMIT;
        END IF;

    END LOOP;

    DROP VIEW pg_temp.corpus;
    DROP TABLE pg_temp.corpus_replace;
    DROP TABLE pg_temp.words;
    DROP TABLE pg_temp.compounds;

END;
$BODY$;