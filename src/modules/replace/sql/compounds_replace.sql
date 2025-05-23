CREATE OR REPLACE FUNCTION compounds_replace (
        v_transliteration_id integer,
        v_corpus_table text,
        v_corpus_schema text,
        v_source_schema text
    )
    RETURNS SETOF @extschema:cuneiform_create_corpus@.compounds_type
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
            (row_number() OVER (PARTITION BY transliteration_id ORDER BY sign_no) - 1)::integer AS compound_no,
            pattern_compound,
            compound_no_orig,
            compound_no_pattern
        FROM
            %1$I.%2$I
        WHERE
            COALESCE(compound_no_orig, compound_no_pattern) IS NOT NULL   
            AND transliteration_id = %3$s
    )
    SELECT
        x.transliteration_id,
        x.compound_no,
        COALESCE(b.pn_type, CASE WHEN x.compound_no_pattern > 0 THEN NULL ELSE a.pn_type END) AS pn_type,  --only preserve pn_type for the first compound in the pattern
        COALESCE(b.language, a.language) AS language,
        a.section_no,
        a.compound_comment
    FROM
        x
        LEFT JOIN %4$I.compounds a ON (x.transliteration_id = a.transliteration_id AND x.compound_no_orig = a.compound_no)
        LEFT JOIN @extschema@.replace_pattern_compounds b ON (x.pattern_id = b.pattern_id AND x.compound_no_pattern = b.compound_no);
    $$,
    v_corpus_schema,
    v_corpus_table,
    v_transliteration_id,
    v_source_schema);
RETURN;
END;
$BODY$;