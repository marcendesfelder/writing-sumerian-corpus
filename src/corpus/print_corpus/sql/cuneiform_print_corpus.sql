CREATE OR REPLACE VIEW corpus_html AS
SELECT
    transliteration_id,
    COALESCE(
        character_print, 
        CASE
            WHEN type = 'number' THEN @extschema:cuneiform_print_html@.print_number_html(custom_value)
            WHEN type != 'punctuation' and type != 'description' THEN @extschema:cuneiform_print_html@.print_sign_html(custom_value)
        END
    ) AS value,
    sign_no, 
    word_no, 
    compound_no, 
    section_no,
    line_no, 
    type,
    indicator_type,
    phonographic, 
    stem, 
    condition, 
    language, 
    inverted, 
    newline,
    ligature,
    crits, 
    comment, 
    capitalized,
    pn_type,
    section_name,
    compound_comment
FROM
    @extschema:cuneiform_corpus@.corpus
    LEFT JOIN @extschema:cuneiform_corpus@.words USING (transliteration_id, word_no) 
    LEFT JOIN @extschema:cuneiform_corpus@.compounds USING (transliteration_id, compound_no) 
    LEFT JOIN @extschema:cuneiform_corpus@.sections USING (transliteration_id, section_no)
    LEFT JOIN @extschema:cuneiform_print_html@.characters_html ON (corpus.sign_variant_id = characters_html.sign_variant_id AND corpus.value_id IS NOT DISTINCT FROM characters_html.value_id);

CREATE VIEW corpus_html_clean AS
SELECT
    transliteration_id,
    COALESCE(character_print, placeholder_html(type)) AS value,
    sign_no, 
    word_no, 
    compound_no, 
    type,
    indicator_type,
    phonographic, 
    stem,
    language
FROM
    @extschema:cuneiform_corpus@.corpus
    LEFT JOIN @extschema:cuneiform_corpus@.words USING (transliteration_id, word_no) 
    LEFT JOIN @extschema:cuneiform_corpus@.compounds USING (transliteration_id, compound_no) 
    LEFT JOIN @extschema:cuneiform_print_html@.characters_html ON (corpus.sign_variant_id = characters_html.sign_variant_id AND corpus.value_id IS NOT DISTINCT FROM characters_html.value_id);


CREATE VIEW corpus_html_range AS
SELECT
    a.transliteration_id,
    RANGE,
    @extschema:cuneiform_print_html@.cun_agg_html (value, sign_no, word_no, compound_no, section_no, line_no, type, indicator_type, phonographic, stem, condition, language, 
        inverted, newline, ligature, crits, comment, capitalized, pn_type, section_name, compound_comment, FALSE, VARIADIC ARRAY[]::integer[] ORDER BY sign_no)  AS content
FROM (
    SELECT
        a.transliteration_id,
        int4range(a.sign_no, b.sign_no, '[]') AS RANGE
    FROM
        @extschema:cuneiform_corpus@.corpus a
        JOIN @extschema:cuneiform_corpus@.corpus b ON a.transliteration_id = b.transliteration_id
            AND a.sign_no <= b.sign_no) a
JOIN corpus_html ON a.transliteration_id = corpus_html.transliteration_id
    AND RANGE @> corpus_html.sign_no
GROUP BY
    a.transliteration_id,
    RANGE;


CREATE VIEW corpus_html_transliterations AS
WITH a AS (
SELECT
    transliteration_id,
    @extschema:cuneiform_print_html@.cun_agg_html (value, sign_no, word_no, compound_no, section_no, line_no, type, indicator_type, phonographic, stem, condition, language, 
        inverted, newline, ligature, crits, comment, capitalized, pn_type, section_name, compound_comment, FALSE, VARIADIC ARRAY[]::integer[] ORDER BY sign_no) AS lines
FROM corpus_html
GROUP BY
    transliteration_id
)
SELECT transliteration_id, line_no-1 AS line_no, line FROM a, LATERAL UNNEST(lines) WITH ORDINALITY AS content(line, line_no);