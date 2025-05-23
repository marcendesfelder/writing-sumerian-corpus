CREATE OR REPLACE FUNCTION words_replace (
        v_transliteration_id integer,
        v_corpus_table text,
        v_corpus_schema text,
        v_source_schema text
    )
    RETURNS SETOF @extschema:cuneiform_create_corpus@.words_type
    STABLE
    ROWS 100
    LANGUAGE PLPGSQL
    AS
$BODY$
BEGIN
RETURN QUERY EXECUTE format($$
    WITH x AS (
        SELECT
            transliteration_id,
            pattern_id,
            word_no,
            pattern_word,
            word_no_orig,
            word_no_pattern,
            (sum((COALESCE(compound_no_orig, compound_no_pattern) IS NOT NULL)::integer) OVER (PARTITION BY transliteration_id ORDER BY sign_no) - 1)::integer AS compound_no
        FROM
            %1$I.%2$I
        WHERE
            COALESCE(word_no_orig, word_no_pattern) IS NOT NULL
            AND transliteration_id = %3$s
    )
    SELECT
        x.transliteration_id,
        x.word_no,
        x.compound_no,
        COALESCE(b.capitalized, FALSE) OR (COALESCE(x.word_no_pattern = 0, TRUE) AND COALESCE(a.capitalized, FALSE)) AS capitalized
    FROM
        x
        LEFT JOIN %4$I.words a ON (x.transliteration_id = a.transliteration_id AND x.word_no_orig = a.word_no)
        LEFT JOIN @extschema@.replace_pattern_words b ON (x.pattern_id = b.pattern_id AND x.word_no_pattern = b.word_no)
    $$,
    v_corpus_schema,
    v_corpus_table,
    v_transliteration_id,
    v_source_schema);
RETURN;
END;
$BODY$;