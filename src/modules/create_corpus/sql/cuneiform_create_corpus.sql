CREATE TYPE surface_type AS ENUM (
    'obverse',
    'reverse',
    'top',
    'bottom',
    'left',
    'right',
    'fragment',
    'surface'
);

CREATE TYPE block_type AS ENUM (
    'column',
    'summary',
    'date',
    'caption',
    'legend',
    'bottom_column',
    'block'
);



CREATE TYPE sections_type AS (
    transliteration_id integer,
    section_no integer,
    section_name text,
    composition_id integer
);

CREATE TYPE compounds_type AS (
    transliteration_id integer,
    compound_no integer,
    pn_type pn_type,
    language @extschema:cuneiform_sign_properties@.language,
    section_no integer,
    compound_comment text
);

CREATE TYPE words_type AS (
    transliteration_id integer,
    word_no integer,
    compound_no integer,
    capitalized boolean
);

CREATE TYPE surfaces_type AS (
    transliteration_id integer,
    surface_no integer,
    surface_type surface_type,
    surface_data text,
    surface_comment text
);

CREATE TYPE blocks_type AS (
    transliteration_id integer,
    block_no integer,
    surface_no integer,
    block_type block_type,
    block_data text,
    block_comment text
);

CREATE TYPE lines_type AS (
    transliteration_id integer,
    line_no integer,
    block_no integer,
    line text,
    line_comment text
);

CREATE TYPE corpus_type AS (
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
    ligature boolean
);


CREATE OR REPLACE PROCEDURE create_corpus (v_schema text, v_temp boolean DEFAULT FALSE)
    LANGUAGE PLPGSQL
    AS 
$BODY$
DECLARE

v_temp_clause text := CASE WHEN v_temp THEN 'TEMPORARY' ELSE '' END;
v_on_commit_clause text := CASE WHEN v_temp THEN 'ON COMMIT DROP' ELSE '' END;

BEGIN

EXECUTE format(
    $$
    CREATE %1$s TABLE %2$I.sections (
        LIKE @extschema@.sections_type,
        PRIMARY KEY (transliteration_id, section_no)
    ) %3$s
    $$,
    v_temp_clause,
    v_schema,
    v_on_commit_clause);
EXECUTE format(
    $$
    ALTER TABLE %1$I.sections 
        ALTER COLUMN section_name SET NOT NULL
    $$,
    v_schema);

EXECUTE format(
    $$
    CREATE %1$s TABLE %2$I.compounds (
        LIKE @extschema@.compounds_type,
        PRIMARY KEY (transliteration_id, compound_no),
        FOREIGN KEY (transliteration_id, section_no) REFERENCES %2$I.sections (transliteration_id, section_no) DEFERRABLE INITIALLY IMMEDIATE
    ) %3$s
    $$,
    v_temp_clause,
    v_schema,
    v_on_commit_clause);

EXECUTE format(
    $$
    CREATE %1$s TABLE %2$I.words (
        LIKE @extschema@.words_type,
        PRIMARY KEY (transliteration_id, word_no),
        FOREIGN KEY (transliteration_id, compound_no) REFERENCES %2$I.compounds (transliteration_id, compound_no) DEFERRABLE INITIALLY IMMEDIATE
    ) %3$s
    $$,
    v_temp_clause,
    v_schema,
    v_on_commit_clause);
EXECUTE format(
    $$
    ALTER TABLE %1$I.words 
        ALTER COLUMN compound_no SET NOT NULL,
        ALTER COLUMN capitalized SET NOT NULL
    $$,
    v_schema);

EXECUTE format(
    $$
    CREATE %1$s TABLE %2$I.surfaces (
        LIKE @extschema@.surfaces_type,
        PRIMARY KEY (transliteration_id, surface_no)
    ) %3$s
    $$,
    v_temp_clause,
    v_schema,
    v_on_commit_clause);
EXECUTE format(
    $$
    ALTER TABLE %1$I.surfaces 
        ALTER COLUMN surface_type SET NOT NULL
    $$,
    v_schema);

EXECUTE format(
    $$
    CREATE %1$s TABLE %2$I.blocks (
        LIKE @extschema@.blocks_type,
        PRIMARY KEY (transliteration_id, block_no),
        FOREIGN KEY (transliteration_id, surface_no) REFERENCES %2$I.surfaces (transliteration_id, surface_no) DEFERRABLE INITIALLY IMMEDIATE
    ) %3$s
    $$,
    v_temp_clause,
    v_schema,
    v_on_commit_clause);
EXECUTE format(
    $$
    ALTER TABLE %1$I.blocks 
        ALTER COLUMN surface_no SET NOT NULL,
        ALTER COLUMN block_type SET NOT NULL
    $$,
    v_schema);

EXECUTE format(
    $$
    CREATE %1$s TABLE %2$I.lines (
        LIKE @extschema@.lines_type,
        PRIMARY KEY (transliteration_id, line_no),
        FOREIGN KEY (transliteration_id, block_no) REFERENCES %2$I.blocks (transliteration_id, block_no) DEFERRABLE INITIALLY IMMEDIATE
    ) %3$s
    $$,
    v_temp_clause,
    v_schema,
    v_on_commit_clause);
EXECUTE format(
    $$
    ALTER TABLE %1$I.lines 
        ALTER COLUMN block_no SET NOT NULL
    $$,
    v_schema);

EXECUTE format(
    $$
    CREATE %1$s TABLE %2$I.corpus (
        LIKE @extschema@.corpus_type,
        PRIMARY KEY (transliteration_id, sign_no),
         %4$s
         %5$s
        FOREIGN KEY (transliteration_id, word_no) REFERENCES %2$I.words (transliteration_id, word_no) DEFERRABLE INITIALLY IMMEDIATE,
        FOREIGN KEY (transliteration_id, line_no) REFERENCES %2$I.lines (transliteration_id, line_no) DEFERRABLE INITIALLY IMMEDIATE
    ) %3$s
    $$,
    v_temp_clause,
    v_schema,
    v_on_commit_clause,
    CASE WHEN v_temp THEN '' ELSE 'FOREIGN KEY (value_id) REFERENCES @extschema:cuneiform_signlist@.values DEFERRABLE INITIALLY IMMEDIATE,' END,
    CASE WHEN v_temp THEN '' ELSE 'FOREIGN KEY (sign_variant_id) REFERENCES @extschema:cuneiform_signlist@.sign_variants DEFERRABLE INITIALLY IMMEDIATE,' END);
EXECUTE format(
    $$
    ALTER TABLE %1$I.corpus 
        ALTER COLUMN line_no SET NOT NULL,
        ALTER COLUMN word_no SET NOT NULL,
        ALTER COLUMN type SET NOT NULL,
        ALTER COLUMN condition SET NOT NULL,
        ALTER COLUMN newline SET NOT NULL,
        ALTER COLUMN inverted SET NOT NULL,
        ALTER COLUMN ligature SET NOT NULL
    $$,
    v_schema);

END;

$BODY$;