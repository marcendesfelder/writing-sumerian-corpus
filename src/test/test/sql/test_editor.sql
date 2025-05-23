CREATE OR REPLACE FUNCTION test_editor ()
    RETURNS SETOF text
    VOLATILE
    LANGUAGE PLPGSQL
    AS 
$BODY$
BEGIN
CALL @extschema:cuneiform_parser@.parse(E'@obverse\n@column 1\n1\ta %sec=a [&a--a!]-/a (a?) 5+6 %person {d}«A»⸢<a>⸣--\n2\t‹&a› a:A &|A.A|;-a+a', -1, '@extschema:cuneiform_corpus@');
CALL @extschema:cuneiform_edit_corpus@.edit_transliteration(E'@surface C\n@block b\n3\t%god &<e?>E--&e+E\n# blah\n@block c\n1\t[e]-;|E|-e %sec=b e:‹e›{ki}', -1, -1, true);
RETURN NEXT is(content, E'@surface C\n@block b\n3\t%god &<e?>E--&e+E\n# blah\n@block c\n1\t%st+ [e]-;E-e %sec=b %st- e:‹e›{ki}') FROM @extschema:cuneiform_serialize_corpus@.transliterations_serialized WHERE transliteration_id = -1;
CALL @extschema:cuneiform_log_corpus@.revert_to(-1, '-infinity', '@extschema:cuneiform_corpus@');
RETURN NEXT is(content, E'@obverse\n@column 1\n1\ta %sec=a [&a--a!]-/a (a?) 5+6 %person &{d}«A»⸢<a>⸣--\n2\t‹&a› a:A %st+ &|A.A|;-a+a') FROM @extschema:cuneiform_serialize_corpus@.transliterations_serialized WHERE transliteration_id = -1;
END;
$BODY$;