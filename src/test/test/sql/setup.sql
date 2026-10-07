
CREATE OR REPLACE FUNCTION startup ()
    RETURNS void
    VOLATILE
    LANGUAGE SQL
    AS 
$BODY$
INSERT INTO @extschema:cuneiform_corpus@.corpora OVERRIDING SYSTEM VALUE VALUES (-1, 'test', 'test', false, null, null, true);
INSERT INTO @extschema:cuneiform_context@.genres OVERRIDING SYSTEM VALUE VALUES (-1, 'test');
INSERT INTO @extschema:cuneiform_corpus@.ensembles OVERRIDING SYSTEM VALUE VALUES (-1, 'test');
INSERT INTO @extschema:cuneiform_corpus@.texts OVERRIDING SYSTEM VALUE VALUES (-1, -1, null, null, 'test', null, null, null, null, null, -1, null, null, null, null);
INSERT INTO @extschema:cuneiform_corpus@.transliterations OVERRIDING SYSTEM VALUE VALUES (-1, -1, -1);
INSERT INTO @extschema:cuneiform_corpus@.compositions OVERRIDING SYSTEM VALUE (VALUES (-1, 'a', 'copy'), (-2, 'b', 'print'));
CREATE TABLE @extschema:cuneiform_corpus@.errors (
    LIKE @extschema:cuneiform_parser@.errors_type
);
CREATE TABLE @extschema:cuneiform_corpus@.corpus_parsed_unencoded (
    LIKE @extschema:cuneiform_parser@.corpus_parsed_unencoded_type,
    PRIMARY KEY (transliteration_id, sign_no)
);
CALL @extschema:cuneiform_encoder@.create_corpus_encoder('corpus_encoder', 'corpus_parsed_unencoded', '{transliteration_id}', '@extschema:cuneiform_corpus@');

$BODY$;


CREATE OR REPLACE FUNCTION shutdown ()
    RETURNS void
    VOLATILE
    LANGUAGE SQL
    AS 
$BODY$
DELETE FROM @extschema:cuneiform_corpus@.transliterations WHERE transliteration_id = -1;
DELETE FROM @extschema:cuneiform_corpus@.texts WHERE text_id = -1;
DELETE FROM @extschema:cuneiform_corpus@.ensembles WHERE ensemble_id = -1;
DELETE FROM @extschema:cuneiform_context@.genres WHERE genre_id = -1;
DELETE FROM @extschema:cuneiform_corpus@.corpora WHERE corpus_id = -1;
DELETE FROM @extschema:cuneiform_corpus@.compositions WHERE composition_id = -1 OR composition_id = -2;
DROP TABLE @extschema:cuneiform_corpus@.errors;
DROP TABLE @extschema:cuneiform_corpus@.corpus_parsed_unencoded CASCADE;
$BODY$;