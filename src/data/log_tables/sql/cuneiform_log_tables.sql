CREATE TABLE edits (
    transliteration_id integer REFERENCES @extschema:cuneiform_corpus@.transliterations(transliteration_id) ON DELETE CASCADE,
    edit_no integer,
    timestamp timestamp with time zone,
    user_id integer,
    internal boolean,
    PRIMARY KEY (transliteration_id, edit_no)
);


CREATE TABLE edit_log (
    transliteration_id integer,
    edit_no integer,
    log_no integer,
    entry_no integer,
    key_col text,
    target text,
    action text,
    val text,
    val_old text,
    PRIMARY KEY (transliteration_id, edit_no, log_no),
    FOREIGN KEY (transliteration_id, edit_no) REFERENCES edits(transliteration_id, edit_no) ON DELETE CASCADE
);


SELECT pg_catalog.pg_extension_config_dump('@extschema@.edits', '');
SELECT pg_catalog.pg_extension_config_dump('@extschema@.edit_log', '');


CREATE OR REPLACE PROCEDURE load_log (path text)
    LANGUAGE PLPGSQL
    AS $BODY$

BEGIN

EXECUTE format('COPY @extschema@.edits(transliteration_id, edit_no, timestamp, user_id, internal) FROM %L CSV NULL ''\N''', path || 'edits.csv');
EXECUTE format('COPY @extschema@.edit_log(transliteration_id, edit_no, log_no, entry_no, key_col, target, action, val, val_old) FROM %L CSV NULL ''\N''', path || 'edit_log.csv');

END
$BODY$;