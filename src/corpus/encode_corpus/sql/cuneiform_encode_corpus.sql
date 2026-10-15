
-- corpus

CREATE TABLE corpus_unencoded (
    transliteration_id integer,
    LIKE @extschema:cuneiform_encoder@.corpus_unencoded_type,
    PRIMARY KEY (transliteration_id, sign_no)
);


CREATE OR REPLACE VIEW corpus_unencoded_view AS
SELECT
    transliteration_id,
    sign_no,
    a[1] AS value,
    left(a[2], -1) AS sign_spec,
    a[1] !~ '^’?[bdgĝhḫjklmnpqrřsšṣtṭwyzaeiu]|^II$' AS unknown_reading
FROM
    @extschema:cuneiform_corpus@.corpus
    LEFT JOIN LATERAL regexp_split_to_array(custom_value, '(?<=[0-9a-zA-ZŠšḪḫŘřĝĜṣṢṭṬ])\(') AS _(a) ON TRUE
WHERE
    custom_value IS NOT NULL
    AND type = 'sign';


CALL create_corpus_encoder('corpus_encoder', 'corpus_unencoded', '{transliteration_id}', '@extschema@');


CREATE OR REPLACE PROCEDURE encode_corpus ()
    LANGUAGE PLPGSQL
    AS $BODY$
    
BEGIN

UPDATE @extschema:cuneiform_corpus@.corpus SET 
    value_id = corpus_encoder.value_id, 
    sign_variant_id = corpus_encoder.sign_variant_id,
    custom_value = NULL
FROM
    @extschema@.corpus_encoder
WHERE
    corpus.sign_variant_id IS NULL
    AND corpus_encoder.sign_variant_id IS NOT NULL
    AND corpus.transliteration_id = corpus_encoder.transliteration_id
    AND corpus.sign_no = corpus_encoder.sign_no
    AND corpus.type = 'sign';

DELETE FROM @extschema@.corpus_unencoded 
USING @extschema:cuneiform_corpus@.corpus 
WHERE 
    corpus.transliteration_id = corpus_unencoded.transliteration_id AND
    corpus.sign_no = corpus_unencoded.sign_no AND
    corpus.sign_variant_id IS NOT NULL;

END;

$BODY$;


CREATE OR REPLACE PROCEDURE unencode_corpus ()
    LANGUAGE PLPGSQL
    AS $BODY$
    
BEGIN

INSERT INTO @extschema@.corpus_unencoded 
SELECT
    transliteration_id,
    sign_no,
    COALESCE(value, graphemes),
    glyphs,
    value_id IS NULL
FROM
    @extschema:cuneiform_corpus@.corpus 
    LEFT JOIN @extschema:cuneiform_signlist@.sign_variants_composition USING (sign_variant_id)
    LEFT JOIN @extschema:cuneiform_signlist@.values USING (value_id)
    LEFT JOIN @extschema:cuneiform_signlist@.value_variants ON (main_variant_id = value_variant_id)
WHERE
    sign_variant_id IS NOT NULL;

UPDATE @extschema:cuneiform_corpus@.corpus SET 
    value_id = NULL, 
    sign_variant_id = NULL
WHERE
    corpus.sign_variant_id IS NOT NULL;

END;

$BODY$;