CREATE TYPE log_data AS (
    transliteration_id integer,
    entry_no integer,
    key_col text,
    target text,
    action text,
    val text,
    val_old text
);


-- change value of a key column based the table's key column (do not use to change the table's key column itself!)
CREATE OR REPLACE FUNCTION adjust_key_col (
    transliteration_id integer,
    entry_no integer,
    target text,
    key_col text,
    key_col_to_adjust text,
    val integer,
    schema text
    )
    RETURNS SETOF log_data
    VOLATILE
    ROWS 1
    LANGUAGE PLPGSQL
    AS 
$BODY$

BEGIN

RETURN QUERY EXECUTE format(
    $$
    SELECT
        %1$s,
        %2$s,
        %3$L,
        %4$L,
        'adjust %5$s',
        %6$L,
        %7$L
    $$,
    transliteration_id,
    entry_no,
    key_col,
    target,
    key_col_to_adjust,
    val,
    -val);

SET CONSTRAINTS ALL DEFERRED;

EXECUTE format(
    $$
    UPDATE %I.%I SET
        %3$I = -(%3$I + %4$s)
    WHERE
        transliteration_id = %5$s AND
        %6$I >= %7$s
    $$,
    schema,
    target,
    key_col_to_adjust,
    val,
    transliteration_id,
    key_col,
    entry_no
    );

EXECUTE format(
    $$
    UPDATE %I.%I SET
        %3$I = -%3$I
    WHERE
        transliteration_id = %4$s AND
        %3$I < 0
    $$,
    schema,
    target,
    key_col_to_adjust,
    transliteration_id);

RETURN;

END;
$BODY$;


-- change value of a key column based on the key column itself
CREATE OR REPLACE FUNCTION shift_key_col (
    transliteration_id integer,
    entry_no integer,
    target text,
    key_col text,
    val integer,
    schema text
    )
    RETURNS SETOF log_data
    VOLATILE
    ROWS 1
    LANGUAGE PLPGSQL
    AS 
$BODY$

BEGIN

RETURN QUERY EXECUTE format(
    $$
    SELECT
        %1$s,
        %2$s,
        %3$L,
        %4$L,
        'shift',
        %5$L,
        %6$L
    $$,
    transliteration_id,
    entry_no,
    key_col,
    target,
    val,
    -val);

SET CONSTRAINTS ALL DEFERRED;

EXECUTE format(
    $$
    UPDATE %I.%I SET
        %3$I = -(%3$I + %4$s)
    WHERE
        transliteration_id = %5$s AND
        %3$I >= %6$s
    $$,
    schema,
    target,
    key_col,
    val,
    transliteration_id,
    entry_no
    );

EXECUTE format(
    $$
    UPDATE %I.%I SET
        %3$I = -%3$I
    WHERE
        transliteration_id = %4$s AND
        %3$I < 0
    $$,
    schema,
    target,
    key_col,
    transliteration_id);

RETURN;

END;
$BODY$;


CREATE OR REPLACE FUNCTION update_entry (
    v_transliteration_id integer,
    v_entry_no integer,
    v_target text,
    v_key_col text,
    v_value record,
    v_schema text
    )
    RETURNS SETOF log_data
    VOLATILE
    ROWS 1
    LANGUAGE PLPGSQL
    AS 
$BODY$
DECLARE

v_value_old record;
v_cols text;

BEGIN

EXECUTE format(
    $$
    SELECT 
        *
    FROM
        %5$I.%4$I
    WHERE
        transliteration_id = %1$s AND
        %3$I = %2$s
    $$,
    v_transliteration_id,
    v_entry_no,
    v_key_col,
    v_target,
    v_schema)
    INTO v_value_old;

IF v_value = v_value_old THEN
    RETURN;
END IF;

RETURN QUERY EXECUTE format(
    $$
    SELECT
        %1$s,
        %2$s,
        %3$L,
        %4$L,
        'update',
        %5$L,
        %6$L
    $$,
    v_transliteration_id,
    v_entry_no,
    v_key_col,
    v_target,
    v_value,
    v_value_old);

EXECUTE format(
    $$
    SELECT 
        string_agg(quote_ident(attname), ', ' ORDER BY attnum) 
    FROM 
        pg_attribute 
    WHERE 
        attrelid = '%2$I.%1$I'::regclass 
        AND attnum > 0 
        AND NOT attisdropped
    $$,
    v_target,
    v_schema)
    INTO v_cols;

EXECUTE format(
    $$
    UPDATE %5$I.%4$I SET
        (%7$s) = (SELECT (%6$L::%5$I.%4$I).*)
    WHERE
        transliteration_id = %1$s AND
        %3$I = %2$s
    $$,
    v_transliteration_id,
    v_entry_no,
    v_key_col,
    v_target,
    v_schema,
    v_value,
    v_cols);

RETURN;

END;
$BODY$;


CREATE OR REPLACE FUNCTION insert_entry (
    transliteration_id integer,
    entry_no integer,
    target text,
    key_col text,
    vals record,
    schema text
    )
    RETURNS SETOF log_data
    VOLATILE
    ROWS 1
    LANGUAGE PLPGSQL
    AS 
$BODY$

BEGIN

RETURN QUERY EXECUTE format(
    $$
    SELECT
        %1$s,
        %2$s,
        %3$L,
        %4$L,
        'insert',
        %5$L,
        NULL
    $$,
    transliteration_id,
    entry_no,
    key_col,
    target,
    vals);

SET CONSTRAINTS ALL DEFERRED;

PERFORM @extschema@.shift_key_col(transliteration_id, entry_no, target, key_col, 1, schema);

EXECUTE format(
    $$
    INSERT INTO %1$I.%2$I
    SELECT (%L::%1$I.%2$I).*
    $$,
    schema,
    target,
    vals);

RETURN;

END;
$BODY$;


CREATE OR REPLACE FUNCTION delete_entry (
    transliteration_id integer,
    entry_no integer,
    target text,
    key_col text,
    schema text
    )
    RETURNS SETOF log_data
    VOLATILE
    ROWS 1
    LANGUAGE PLPGSQL
    AS 
$BODY$

BEGIN

RETURN QUERY EXECUTE format(
    $$
    SELECT
        %1$s,
        %2$s,
        %3$L,
        %4$L,
        'delete',
        NULL,
        %4$I::%5$I.%4$I::text
    FROM
        %5$I.%4$I
    WHERE
        transliteration_id = %1$s AND
        %3$I = %2$s
    $$,
    transliteration_id,
    entry_no,
    key_col,
    target,
    schema);

SET CONSTRAINTS ALL DEFERRED;

EXECUTE format(
    $$
    DELETE FROM %I.%I
    WHERE
        transliteration_id = %s AND
        %I = %s
    $$,
    schema,
    target,
    transliteration_id,
    key_col,
    entry_no);

PERFORM @extschema@.shift_key_col(transliteration_id, entry_no, target, key_col, -1, schema);

RETURN;

END;
$BODY$;


CREATE OR REPLACE FUNCTION split_entry (
    transliteration_id integer,
    entry_no integer,
    target text,
    key_col text,
    parent_target text,
    parent_key_col text,
    vals record,
    schema text
    )
    RETURNS SETOF log_data
    VOLATILE
    ROWS 2
    LANGUAGE PLPGSQL
    AS 
$BODY$
DECLARE

parent_entry_no integer;

BEGIN

SET CONSTRAINTS ALL DEFERRED;

EXECUTE format(
    $$
    SELECT %I 
    FROM %I.%I
    WHERE
        transliteration_id = %s AND
        %I = %s
    $$,
    parent_key_col,
    schema,
    target,
    transliteration_id,
    key_col,
    entry_no)
    INTO STRICT parent_entry_no;

RETURN QUERY SELECT * FROM @extschema@.insert_entry(transliteration_id, parent_entry_no, parent_target, parent_key_col, vals, schema);
RETURN QUERY SELECT * FROM @extschema@.adjust_key_col(transliteration_id, entry_no+1, target, key_col, parent_key_col, 1, schema);
RETURN;

END;
$BODY$;


CREATE OR REPLACE FUNCTION merge_entries (
    transliteration_id integer,
    entry_no integer,
    target text,
    key_col text,
    child_target text,
    child_key_col text,
    schema text
    )
    RETURNS SETOF log_data
    VOLATILE
    ROWS 2
    LANGUAGE PLPGSQL
    AS 
$BODY$
DECLARE

child_entry_no integer;

BEGIN

EXECUTE format(
    $$
    SELECT
        min(%1$I)
    FROM
        %2$I.%3$I
    WHERE
        %4$I = %5$s
        AND transliteration_id = %6$s
    $$,
    child_key_col,
    schema,
    child_target,
    key_col,
    entry_no+1,
    transliteration_id
    )
    INTO child_entry_no;

SET CONSTRAINTS ALL DEFERRED;
RETURN QUERY SELECT * FROM @extschema@.adjust_key_col(transliteration_id, child_entry_no, child_target, child_key_col, key_col, -1, schema);
RETURN QUERY SELECT * FROM @extschema@.delete_entry(transliteration_id, entry_no, target, key_col, schema);
RETURN;

END;
$BODY$;



CREATE OR REPLACE PROCEDURE delete_transliteration (
        v_transliteration_id integer, 
        v_schema text
    )
    LANGUAGE PLPGSQL
    AS 
$BODY$
DECLARE
t text;
BEGIN
FOREACH t IN ARRAY array['corpus', 'words', 'compounds', 'lines', 'blocks', 'surfaces', 'sections'] LOOP
    EXECUTE format($$DELETE FROM %I.%I WHERE transliteration_id = %s$$, v_schema, t, v_transliteration_id);
END LOOP;
END;
$BODY$;


CREATE OR REPLACE PROCEDURE copy_transliteration (
        v_transliteration_id integer, 
        v_source_schema text, 
        v_target_schema text
    )
    LANGUAGE PLPGSQL
    AS 
$BODY$
DECLARE
t text;
BEGIN
FOREACH t IN ARRAY array['sections', 'surfaces', 'blocks', 'lines', 'compounds', 'words', 'corpus'] LOOP
    EXECUTE format($$INSERT INTO %I.%I SELECT * FROM %I.%I WHERE transliteration_id = %s$$, v_target_schema, t, v_source_schema, t, v_transliteration_id);
END LOOP;
END;
$BODY$;