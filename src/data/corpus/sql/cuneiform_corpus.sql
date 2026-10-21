CALL @extschema:cuneiform_create_corpus@.create_corpus('@extschema@');


CREATE TABLE corpora (
    corpus_id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    name_short text NOT NULL UNIQUE,
    name_long text NOT NULL,
    core boolean NOT NULL,
    date date,
    reference text,
    public boolean NOT NULL
);


CREATE TABLE ensembles (
    ensemble_id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    ensemble text
);



CREATE TYPE witness_type AS ENUM (
    'original',
    'print',
    'copy',
    'variant'
);

CREATE TABLE compositions (
    composition_id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    composition_name text UNIQUE NOT NULL,
    witness_type witness_type NOT NULL,
    parent_composition_id integer REFERENCES compositions (composition_id) DEFERRABLE INITIALLY IMMEDIATE
);

CREATE VIEW compositions_flat AS 
WITH RECURSIVE t(composition_id, composition_id_2) AS (
    SELECT
        composition_id,
        composition_id
    FROM
        compositions
    UNION
    SELECT 
        t.composition_id,
        b.parent_composition_id
    FROM
        t
        JOIN compositions b ON t.composition_id_2 = b.composition_id
    WHERE
        b.parent_composition_id IS NOT NULL
)
SELECT * FROM t;


CREATE TABLE texts (
    text_id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    ensemble_id integer NOT NULL REFERENCES ensembles (ensemble_id) DEFERRABLE INITIALLY IMMEDIATE,
    cdli_no text,
    bdtns_no text,
    citation text,
    provenience_id integer REFERENCES @extschema:cuneiform_context@.proveniences (provenience_id) DEFERRABLE INITIALLY IMMEDIATE,
    provenience_comment text,
    period_id integer REFERENCES @extschema:cuneiform_context@.periods (period_id) DEFERRABLE INITIALLY IMMEDIATE,
    period_year integer,
    period_comment text,
    genre_id integer REFERENCES @extschema:cuneiform_context@.genres (genre_id) DEFERRABLE INITIALLY IMMEDIATE,
    genre_comment text,
    object_id integer REFERENCES @extschema:cuneiform_context@.objects (object_id) DEFERRABLE INITIALLY IMMEDIATE,
    object_subtype_id integer,
    object_comment text,
    archive text,
    composition_id integer REFERENCES compositions (composition_id) DEFERRABLE INITIALLY IMMEDIATE,
    FOREIGN KEY (object_id, object_subtype_id) REFERENCES @extschema:cuneiform_context@.object_subtypes (object_id, object_subtype_id)
);


CREATE TABLE transliterations (
    transliteration_id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    text_id integer NOT NULL REFERENCES texts (text_id) DEFERRABLE INITIALLY IMMEDIATE,
    corpus_id integer NOT NULL REFERENCES corpora (corpus_id) DEFERRABLE INITIALLY IMMEDIATE,
    reference text
);


ALTER TABLE compounds ADD FOREIGN KEY (transliteration_id) REFERENCES transliterations DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE words ADD FOREIGN KEY (transliteration_id) REFERENCES transliterations DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE surfaces ADD FOREIGN KEY (transliteration_id) REFERENCES transliterations DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE blocks ADD FOREIGN KEY (transliteration_id) REFERENCES transliterations DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE lines ADD FOREIGN KEY (transliteration_id) REFERENCES transliterations DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE corpus ADD FOREIGN KEY (transliteration_id) REFERENCES transliterations DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE sections ADD FOREIGN KEY (composition_id) REFERENCES compositions (composition_id) DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE sections ADD FOREIGN KEY (transliteration_id) REFERENCES transliterations DEFERRABLE INITIALLY IMMEDIATE;

CLUSTER corpus USING corpus_pkey;


CREATE OR REPLACE VIEW texts_compositions AS 
WITH x AS (
    SELECT 
        text_id,
        composition_id
    FROM
        texts
    WHERE
        composition_id IS NOT NULL
    UNION
    SELECT
        text_id, 
        composition_id
    FROM
        sections
        JOIN transliterations USING (transliteration_id)
    WHERE
        composition_id IS NOT NULL
)
SELECT
    text_id,
    composition_id_2 AS composition_id
FROM
    x
    JOIN compositions_flat USING (composition_id);


-- Performance

CREATE OR REPLACE PROCEDURE database_create_indexes ()
LANGUAGE SQL
AS $BODY$
    CREATE INDEX texts_provenience_id_ix ON @extschema@.texts(provenience_id);
    CREATE INDEX texts_period_id_ix ON @extschema@.texts(period_id);
    CREATE INDEX texts_genre_id_ix ON @extschema@.texts(genre_id);
    CREATE INDEX texts_object_id_ix ON @extschema@.texts(object_id);
    CREATE INDEX texts_composition_id_ix ON @extschema@.texts(composition_id);
    CREATE INDEX transliterations_text_id_ix ON @extschema@.transliterations(text_id);
    CREATE INDEX compositions_parent_composition_id_ix ON @extschema@.compositions(parent_composition_id);
    CREATE INDEX sections_composition_id_ix ON @extschema@.sections(composition_id);
$BODY$;

CREATE OR REPLACE PROCEDURE database_drop_indexes ()
LANGUAGE SQL
AS $BODY$
    DROP INDEX @extschema@.texts_provenience_id_ix;
    DROP INDEX @extschema@.texts_period_id_ix;
    DROP INDEX @extschema@.texts_genre_id_ix;
    DROP INDEX @extschema@.texts_object_id_ix;
    DROP INDEX @extschema@.texts_composition_id_ix;
    DROP INDEX @extschema@.transliterations_text_id_ix;
    DROP INDEX @extschema@.compositions_parent_composition_id_ix;
    DROP INDEX @extschema@.sections_composition_id_ix;
$BODY$;

CALL database_create_indexes ();


SELECT pg_catalog.pg_extension_config_dump('@extschema@.corpora', '');
SELECT pg_catalog.pg_extension_config_dump('@extschema@.ensembles', '');
SELECT pg_catalog.pg_extension_config_dump('@extschema@.texts', '');
SELECT pg_catalog.pg_extension_config_dump('@extschema@.transliterations', '');
SELECT pg_catalog.pg_extension_config_dump('@extschema@.compositions', '');
SELECT pg_catalog.pg_extension_config_dump('@extschema@.sections', '');
SELECT pg_catalog.pg_extension_config_dump('@extschema@.compounds', '');
SELECT pg_catalog.pg_extension_config_dump('@extschema@.words', '');
SELECT pg_catalog.pg_extension_config_dump('@extschema@.surfaces', '');
SELECT pg_catalog.pg_extension_config_dump('@extschema@.blocks', '');
SELECT pg_catalog.pg_extension_config_dump('@extschema@.lines', '');
SELECT pg_catalog.pg_extension_config_dump('@extschema@.corpus', '');
SELECT pg_catalog.pg_extension_config_dump(pg_get_serial_sequence('@extschema@.corpora', 'corpus_id'), '');
SELECT pg_catalog.pg_extension_config_dump(pg_get_serial_sequence('@extschema@.ensembles', 'ensemble_id'), '');
SELECT pg_catalog.pg_extension_config_dump(pg_get_serial_sequence('@extschema@.texts', 'text_id'), '');
SELECT pg_catalog.pg_extension_config_dump(pg_get_serial_sequence('@extschema@.transliterations', 'transliteration_id'), '');
SELECT pg_catalog.pg_extension_config_dump(pg_get_serial_sequence('@extschema@.compositions', 'composition_id'), '');


CREATE OR REPLACE PROCEDURE load_corpus(v_path text)
 LANGUAGE plpgsql
AS 
$BODY$

 BEGIN

 TRUNCATE @extschema@.compositions CASCADE;
 EXECUTE format('COPY @extschema@.compositions FROM %L CSV NULL ''\N''', v_path || 'compositions.csv');
 COMMIT;
 TRUNCATE @extschema@.corpora CASCADE;
 EXECUTE format('COPY @extschema@.corpora FROM %L CSV NULL ''\N''', v_path || 'corpora.csv');
 COMMIT;
 TRUNCATE @extschema@.ensembles CASCADE;
 EXECUTE format('COPY @extschema@.ensembles FROM %L CSV NULL ''\N''', v_path || 'ensembles.csv');
 COMMIT;
 TRUNCATE @extschema@.texts CASCADE;
 EXECUTE format('COPY @extschema@.texts FROM %L CSV NULL ''\N''', v_path || 'texts.csv');
 COMMIT;
 TRUNCATE @extschema@.transliterations CASCADE;
 EXECUTE format('COPY @extschema@.transliterations FROM %L CSV NULL ''\N''', v_path || 'transliterations.csv');      
 COMMIT;
 TRUNCATE @extschema@.surfaces CASCADE;   
 EXECUTE format('COPY @extschema@.surfaces FROM %L CSV NULL ''\N''', v_path || 'surfaces.csv');
 COMMIT;
 TRUNCATE @extschema@.blocks CASCADE;
 EXECUTE format('COPY @extschema@.blocks FROM %L CSV NULL ''\N''', v_path || 'blocks.csv');
 COMMIT;
 TRUNCATE @extschema@.lines CASCADE;
 EXECUTE format('COPY @extschema@.lines FROM %L CSV NULL ''\N''', v_path || 'lines.csv');
 COMMIT;
 TRUNCATE @extschema@.sections CASCADE;
 EXECUTE format('COPY @extschema@.sections FROM %L CSV NULL ''\N''', v_path || 'sections.csv');
 COMMIT;
 TRUNCATE @extschema@.compounds CASCADE;
 EXECUTE format('COPY @extschema@.compounds FROM %L CSV NULL ''\N''', v_path || 'compounds.csv');
 COMMIT;
 TRUNCATE @extschema@.words CASCADE;
 EXECUTE format('COPY @extschema@.words FROM %L CSV NULL ''\N''', v_path || 'words.csv');
 COMMIT;
 TRUNCATE @extschema@.corpus CASCADE;
 EXECUTE format('COPY @extschema@.corpus FROM %L CSV NULL ''\N''', v_path || 'corpus.csv');
 COMMIT;

 PERFORM setval(pg_get_serial_sequence('@extschema@.compositions', 'composition_id'), max(composition_id)) FROM @extschema@.compositions;
 PERFORM setval(pg_get_serial_sequence('@extschema@.corpora', 'corpus_id'), max(corpus_id)) FROM @extschema@.corpora;
 PERFORM setval(pg_get_serial_sequence('@extschema@.ensembles', 'ensemble_id'), max(ensemble_id)) FROM @extschema@.ensembles;
 PERFORM setval(pg_get_serial_sequence('@extschema@.texts', 'text_id'), max(text_id)) FROM @extschema@.texts;
 PERFORM setval(pg_get_serial_sequence('@extschema@.transliterations', 'transliteration_id'), max(transliteration_id)) FROM @extschema@.transliterations;

 END
 $BODY$;