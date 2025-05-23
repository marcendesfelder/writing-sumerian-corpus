CREATE OR REPLACE FUNCTION edit_log_redo_query (
        v_transliteration_id integer,
        v_schema text,
        v_entry_no integer,
        v_key_col text,
        v_target text,
        v_action text,
        v_val text
    )
    RETURNS text
    IMMUTABLE
    LANGUAGE PLPGSQL
AS $BODY$
DECLARE

v_ops text[];

BEGIN

SELECT string_to_array(v_action, ' ') INTO v_ops;

CASE v_ops[1]
    WHEN 'update' THEN
        RETURN format(
            'SELECT @extschema:cuneiform_actions@.update_entry(%s, %s, %L, %L, %L, %L)', 
            v_transliteration_id, v_entry_no, v_target, v_key_col, v_val, v_schema);
    WHEN 'adjust' THEN
        RETURN format(
            'SELECT @extschema:cuneiform_actions@.adjust_key_col(%s, %s, %L, %L, %L, %L, %L)',
            v_transliteration_id, v_entry_no, v_target, v_key_col, v_ops[2], v_val, v_schema);
    WHEN 'shift' THEN
        RETURN format(
            'SELECT @extschema:cuneiform_actions@.shift_key_col(%s, %s, %L, %L, %L, %L)',
            v_transliteration_id, v_entry_no, v_target, v_key_col, v_val, v_schema);
    WHEN 'insert' THEN
        RETURN format(
            'SELECT @extschema:cuneiform_actions@.insert_entry(%1$s, %2$s, %3$L, %4$L, %5$L::%6$I.%3$I, %6$L)',
            v_transliteration_id, v_entry_no, v_target, v_key_col, v_val, v_schema);
    WHEN 'delete' THEN
        RETURN format(
            'SELECT @extschema:cuneiform_actions@.delete_entry(%s, %s, %L, %L, %L)',
            v_transliteration_id, v_entry_no, v_target, v_key_col, v_schema);
END CASE;
END;
$BODY$;



CREATE OR REPLACE FUNCTION edit_log_undo_query (
        v_transliteration_id integer,
        v_schema text,
        v_entry_no integer,
        v_key_col text,
        v_target text,
        v_action text,
        v_val_old text
    )
    RETURNS text
    IMMUTABLE
    LANGUAGE PLPGSQL
AS $BODY$
DECLARE

v_ops text[];

BEGIN

SELECT string_to_array(v_action, ' ') INTO v_ops;

CASE v_ops[1]
    WHEN 'update' THEN
        RETURN format(
            'SELECT @extschema:cuneiform_actions@.update_entry(%s, %s, %L, %L, %L, %L)', 
            v_transliteration_id, v_entry_no, v_target, v_key_col, v_val_old, v_schema);
    WHEN 'adjust' THEN
        RETURN format(
            'SELECT @extschema:cuneiform_actions@.adjust_key_col(%s, %s, %L, %L, %L, %L, %L)',
            v_transliteration_id, v_entry_no, v_target, v_key_col, v_ops[2], v_val_old, v_schema);
    WHEN 'shift' THEN
        RETURN format(
            'SELECT @extschema:cuneiform_actions@.shift_key_col(%s, %s, %L, %L, %L, %L)',
            v_transliteration_id, v_entry_no-v_val_old::integer, v_target, v_key_col, v_val_old, v_schema);
    WHEN 'insert' THEN
        RETURN format(
            'SELECT @extschema:cuneiform_actions@.delete_entry(%s, %s, %L, %L, %L)',
            v_transliteration_id, v_entry_no, v_target, v_key_col, v_schema);
    WHEN 'delete' THEN
        RETURN format(
            'SELECT @extschema:cuneiform_actions@.insert_entry(%1$s, %2$s, %3$L, %4$L, %5$L::%6$I.%3$I, %6$L)',
            v_transliteration_id, v_entry_no, v_target, v_key_col, v_val_old, v_schema);
END CASE;
END;
$BODY$;


CREATE OR REPLACE FUNCTION log_trace_entry (
        v_entry_no integer,
        v_action text,
        v_id integer
    )
    RETURNS integer
    LANGUAGE SQL
    COST 100
    IMMUTABLE 
BEGIN ATOMIC
SELECT
    CASE
        WHEN v_action = 'insert' AND v_entry_no >= v_id THEN v_entry_no+1
        WHEN v_action = 'delete' AND v_entry_no = v_id THEN NULL
        WHEN v_action = 'delete' AND v_entry_no > v_id THEN v_entry_no-1
        WHEN v_action IS NULL THEN v_id     -- init
        ELSE v_entry_no
    END;
END;

CREATE OR REPLACE AGGREGATE log_trace_entry_agg (v_action text, v_id integer) (
    stype = integer,
    sfunc = log_trace_entry
);


CREATE OR REPLACE FUNCTION log_trace_entry_backwards (
        v_entry_no integer,
        v_action text,
        v_id integer
    )
    RETURNS integer
    LANGUAGE SQL
    COST 100
    IMMUTABLE 
BEGIN ATOMIC
SELECT
    CASE
        WHEN v_action = 'insert' AND v_entry_no >= v_id THEN v_entry_no-1
        WHEN v_action = 'insert' AND v_entry_no = v_id THEN NULL
        WHEN v_action = 'delete' AND v_entry_no > v_id THEN v_entry_no+1
        ELSE v_entry_no
    END;
END;

CREATE OR REPLACE AGGREGATE log_trace_entry_backwards_agg (v_action text, v_id integer) (
    stype = integer,
    sfunc = log_trace_entry_backwards
);


CREATE OR REPLACE FUNCTION log_affected_entries_sfunc (
        v_entry_nos integer[],
        v_action text,
        v_id integer)
    RETURNS integer[]
    LANGUAGE SQL
    COST 100
    IMMUTABLE 
BEGIN ATOMIC
SELECT
    array_agg(log_trace_entry(entry_no, v_action, v_id)) 
    || 
    CASE 
        WHEN v_action ~ '^update' OR v_action = 'insert' OR v_action = 'shift' THEN ARRAY[v_id]::integer[]
        ELSE ARRAY[]::integer[]
    END
FROM
    unnest(v_entry_nos) AS _(entry_no);
END;


CREATE OR REPLACE FUNCTION log_affected_entries_finalfunc (
        v_entry_nos integer[]
    )
    RETURNS integer[]
    LANGUAGE SQL
    COST 100
    IMMUTABLE 
BEGIN ATOMIC
SELECT 
    array_agg(DISTINCT entry_no ORDER BY entry_no)
FROM
    unnest(v_entry_nos) AS _(entry_no)
WHERE
    entry_no IS NOT NULL;
END;


CREATE OR REPLACE AGGREGATE log_affected_entries_agg (v_action text, v_id integer) (
    stype = integer[],
    sfunc = log_affected_entries_sfunc,
    finalfunc = log_affected_entries_finalfunc
);



CREATE TYPE log_agg_state_type AS (
    id integer,
    edit_nos integer[]
);


CREATE OR REPLACE FUNCTION log_agg_sfunc (
        v_state log_agg_state_type,
        v_edit_no integer,
        v_action text,
        v_id integer,
        v_value text)
    RETURNS log_agg_state_type
    LANGUAGE SQL
    COST 100
    IMMUTABLE 
BEGIN ATOMIC
SELECT
    CASE
        WHEN v_action = 'insert' AND (v_state).id > v_id THEN ROW((v_state).id-1, (v_state).edit_nos)::log_agg_state_type
        WHEN v_action = 'insert' AND (v_state).id = v_id THEN ROW(null, (v_state).edit_nos || v_edit_no)::log_agg_state_type
        WHEN v_action = 'delete' AND (v_state).id >= v_id THEN ROW((v_state).id+1, (v_state).edit_nos)::log_agg_state_type
        WHEN v_action ~ '^update' AND (v_state).id = v_id THEN ROW((v_state).id, (v_state).edit_nos || v_edit_no)::log_agg_state_type
        WHEN v_action IS NULL THEN ROW(v_id, ARRAY[]::integer[])::log_agg_state_type -- init
        ELSE v_state
    END;
END;

CREATE OR REPLACE FUNCTION log_agg_finalfunc (
        v_state log_agg_state_type
    )
    RETURNS integer[]
    LANGUAGE SQL
    COST 100
    IMMUTABLE 
BEGIN ATOMIC
SELECT (v_state).edit_nos;
END;


CREATE OR REPLACE AGGREGATE log_agg (v_edit_no integer, v_action text, v_id integer, v_value text) (
    stype = log_agg_state_type,
    sfunc = log_agg_sfunc,
    finalfunc = log_agg_finalfunc
);