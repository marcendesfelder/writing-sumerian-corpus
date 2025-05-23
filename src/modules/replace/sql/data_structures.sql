CREATE SEQUENCE replace_id_seq CYCLE;

CREATE TABLE replace_pattern_corpus (
    pattern_id integer,
    sign_no integer,
    word_no integer,
    value_id integer,
    sign_variant_id integer,
    custom_value text,
    type @extschema:cuneiform_sign_properties@.sign_type,
    indicator_type @extschema:cuneiform_sign_properties@.indicator_type,
    phonographic boolean,
    stem boolean,
    PRIMARY KEY (pattern_id, sign_no)
);

CREATE TABLE replace_pattern_words (
    pattern_id integer,
    word_no integer,
    compound_no integer,
    capitalized boolean,
    PRIMARY KEY (pattern_id, word_no)
);

CREATE TABLE replace_pattern_compounds (
    pattern_id integer,
    compound_no integer,
    pn_type pn_type,
    language @extschema:cuneiform_sign_properties@.language,
    PRIMARY KEY (pattern_id, compound_no)
);

CREATE TABLE replace_pattern_corpus_unencoded (
    pattern_id integer,
    LIKE @extschema:cuneiform_encoder@.corpus_unencoded_type,
    PRIMARY KEY (pattern_id, sign_no)
);

CREATE TYPE corpus_replace_type AS (
    transliteration_id integer,
    sign_no integer,
    line_no integer,
    word_no integer,
    value_id integer,
    sign_variant_id integer,
    custom_value text,
    type @extschema:cuneiform_sign_properties@.sign_type,
    indicator_type @extschema:cuneiform_sign_properties@.indicator_type,
    phonographic boolean,
    stem boolean,
    condition @extschema:cuneiform_sign_properties@.sign_condition,
    crits text,
    comment text,
    newline boolean,
    inverted boolean,
    ligature boolean,
    pattern_id integer,
    pattern_word boolean,
    word_no_pattern integer,
    word_no_orig integer,
    pattern_compound boolean,
    compound_no_pattern integer,
    compound_no_orig integer,
    valid boolean
);

CALL @extschema:cuneiform_encoder@.create_corpus_encoder('replace_pattern_corpus_encoder', 'replace_pattern_corpus_unencoded', '{pattern_id}', '@extschema@');
