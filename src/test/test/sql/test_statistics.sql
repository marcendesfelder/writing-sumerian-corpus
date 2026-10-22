CREATE OR REPLACE FUNCTION test_statistics ()
    RETURNS SETOF text
    VOLATILE
    LANGUAGE PLPGSQL
    AS
$BODY$
BEGIN
-- tests run inside a transaction, so the flush that normally happens at commit is called explicitly

CALL @extschema:cuneiform_parser@.parse(E'@obverse\n@column 1\n1\ta %sec=a [&a--a!]-/a (a?) 5+6 %person {d}«A»⸢<a>⸣--\n2\t‹&a› a:A &|A.A|;-a+a', -1, '@extschema:cuneiform_corpus@');
PERFORM @extschema:cuneiform_corpus_statistics@.statistics_flush();
RETURN NEXT isnt_empty('SELECT * FROM @extschema:cuneiform_corpus_statistics@.texts_snapshot_values WHERE text_id = -1', 'statistics: parse adds counts');
RETURN NEXT is_empty('SELECT * FROM @extschema:cuneiform_corpus_statistics@.statistics_check()', 'statistics: parse');

CALL @extschema:cuneiform_edit_corpus@.edit_transliteration(E'@surface C\n@block b\n3\t%god &<e?>E--&e+E\n# blah\n@block c\n1\t[e]-;|E|-e %sec=b e:‹e›{ki}', -1, -1, true);
PERFORM @extschema:cuneiform_corpus_statistics@.statistics_flush();
RETURN NEXT is_empty('SELECT * FROM @extschema:cuneiform_corpus_statistics@.statistics_check()', 'statistics: edit');

UPDATE @extschema:cuneiform_corpus@.texts SET genre_id = NULL WHERE text_id = -1;
PERFORM @extschema:cuneiform_corpus_statistics@.statistics_flush();
RETURN NEXT is_empty('SELECT * FROM @extschema:cuneiform_corpus_statistics@.statistics_check()', 'statistics: dimension set to NULL');

UPDATE @extschema:cuneiform_corpus@.texts SET genre_id = -1 WHERE text_id = -1;
PERFORM @extschema:cuneiform_corpus_statistics@.statistics_flush();
RETURN NEXT is_empty('SELECT * FROM @extschema:cuneiform_corpus_statistics@.statistics_check()', 'statistics: dimension set from NULL');

INSERT INTO @extschema:cuneiform_corpus@.transliterations OVERRIDING SYSTEM VALUE VALUES (-2, -1, -1);
PERFORM @extschema:cuneiform_corpus_statistics@.statistics_flush();
RETURN NEXT is_empty('SELECT * FROM @extschema:cuneiform_corpus_statistics@.statistics_check()', 'statistics: transliteration added');

DELETE FROM @extschema:cuneiform_corpus@.transliterations WHERE transliteration_id = -2;
PERFORM @extschema:cuneiform_corpus_statistics@.statistics_flush();
RETURN NEXT is_empty('SELECT * FROM @extschema:cuneiform_corpus_statistics@.statistics_check()', 'statistics: transliteration deleted');

INSERT INTO @extschema:cuneiform_corpus@.texts OVERRIDING SYSTEM VALUE VALUES (-2, -1, null, null, 'test 2', null, null, null, null, null, null, null, null, null, null);
UPDATE @extschema:cuneiform_corpus@.transliterations SET text_id = -2 WHERE transliteration_id = -1;
PERFORM @extschema:cuneiform_corpus_statistics@.statistics_flush();
RETURN NEXT is_empty('SELECT * FROM @extschema:cuneiform_corpus_statistics@.texts_snapshot_values WHERE text_id = -1', 'statistics: transliteration moved away');
RETURN NEXT is_empty('SELECT * FROM @extschema:cuneiform_corpus_statistics@.statistics_check()', 'statistics: transliteration moved');

UPDATE @extschema:cuneiform_corpus@.transliterations SET text_id = -1 WHERE transliteration_id = -1;
DELETE FROM @extschema:cuneiform_corpus@.texts WHERE text_id = -2;
PERFORM @extschema:cuneiform_corpus_statistics@.statistics_flush();
RETURN NEXT is_empty('SELECT * FROM @extschema:cuneiform_corpus_statistics@.statistics_check()', 'statistics: text deleted');

-- transliteration missing while its corpus rows still exist
SET CONSTRAINTS ALL DEFERRED;
DELETE FROM @extschema:cuneiform_corpus@.transliterations WHERE transliteration_id = -1;
PERFORM @extschema:cuneiform_corpus_statistics@.statistics_flush();
RETURN NEXT is_empty('SELECT * FROM @extschema:cuneiform_corpus_statistics@.texts_snapshot_values WHERE text_id = -1', 'statistics: transliteration deleted before corpus');
RETURN NEXT is_empty('SELECT * FROM @extschema:cuneiform_corpus_statistics@.statistics_check()', 'statistics: transliteration deleted before corpus');

INSERT INTO @extschema:cuneiform_corpus@.transliterations OVERRIDING SYSTEM VALUE VALUES (-1, -1, -1);
PERFORM @extschema:cuneiform_corpus_statistics@.statistics_flush();
RETURN NEXT isnt_empty('SELECT * FROM @extschema:cuneiform_corpus_statistics@.texts_snapshot_values WHERE text_id = -1', 'statistics: transliteration inserted after corpus');
RETURN NEXT is_empty('SELECT * FROM @extschema:cuneiform_corpus_statistics@.statistics_check()', 'statistics: transliteration inserted after corpus');
SET CONSTRAINTS ALL IMMEDIATE;
END;
$BODY$;
