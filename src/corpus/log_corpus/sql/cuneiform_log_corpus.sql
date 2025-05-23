CREATE OR REPLACE VIEW corpus_modified AS
WITH corpus_edits AS (
    SELECT
        row_number() OVER (PARTITION BY transliteration_id ORDER BY edit_no DESC, log_no DESC) AS ord,
        transliteration_id,
        sign_no,
        edit_no,
        entry_no,
        split_part(action, ' ', 1) AS action,
        val
    FROM 
        @extschema:cuneiform_log_tables@.edit_log 
        JOIN @extschema:cuneiform_log_tables@.edits USING (transliteration_id, edit_no)
        JOIN @extschema:cuneiform_corpus@.corpus USING (transliteration_id)
    WHERE
        target = 'corpus'
    UNION ALL
    SELECT
        0,
        transliteration_id,
        sign_no,
        NULL,
        sign_no,
        NULL,
        NULL
    FROM @extschema:cuneiform_corpus@.corpus
)
SELECT
    transliteration_id,
    sign_no,
    log_agg(edit_no, action, entry_no, val ORDER BY ord) AS edit_nos
FROM
    corpus_edits
GROUP BY
    transliteration_id,
    sign_no;


CREATE OR REPLACE PROCEDURE undo (
    v_transliteration_id integer,
    v_edit_no integer, 
    v_schema text
    )
    LANGUAGE PLPGSQL
    AS 
$BODY$
DECLARE

v_query text;

BEGIN
FOR v_query IN 
    SELECT 
        @extschema:cuneiform_log@.edit_log_undo_query(transliteration_id, v_schema, entry_no, key_col, target, action, val_old)
    FROM 
        @extschema:cuneiform_log_tables@.edit_log 
    WHERE 
        transliteration_id = v_transliteration_id
        AND edit_no = v_edit_no
    ORDER BY log_no DESC 
    LOOP
    RAISE INFO USING MESSAGE = v_query;
    DISCARD PLANS;
    EXECUTE v_query;
END LOOP;
END;
$BODY$;


CREATE OR REPLACE PROCEDURE revert_to (
    v_transliteration_id integer, 
    v_timestamp timestamp with time zone, 
    v_schema text
    )
    LANGUAGE PLPGSQL
    AS 
$BODY$

DECLARE

v_query text;

BEGIN
FOR v_query IN 
    SELECT 
        @extschema:cuneiform_log@.edit_log_undo_query(transliteration_id, v_schema, entry_no, key_col, target, action, val_old) 
    FROM 
        @extschema:cuneiform_log_tables@.edit_log 
        JOIN @extschema:cuneiform_log_tables@.edits USING (transliteration_id, edit_no)
    WHERE 
        transliteration_id = v_transliteration_id 
        AND timestamp > v_timestamp
    ORDER BY edit_no DESC, log_no DESC 
    LOOP
    RAISE INFO USING MESSAGE = v_query;
    DISCARD PLANS;
    EXECUTE v_query;
END LOOP;
END;
$BODY$;


CREATE OR REPLACE PROCEDURE redo (
    v_transliteration_id integer,
    v_edit_no integer, 
    v_schema text
    )
    LANGUAGE PLPGSQL
    AS 
$BODY$
DECLARE

v_query text;

BEGIN
FOR v_query IN 
    SELECT 
        @extschema:cuneiform_log@.edit_log_redo_query(transliteration_id, v_schema, entry_no, key_col, target, action, val) 
    FROM 
        @extschema:cuneiform_log_tables@.edit_log 
    WHERE 
        transliteration_id = v_transliteration_id
        AND edit_no = v_edit_no
    ORDER BY log_no
    LOOP
    RAISE INFO USING MESSAGE = v_query;
    DISCARD PLANS;
    EXECUTE v_query;
END LOOP;
END;
$BODY$;


CREATE OR REPLACE PROCEDURE revert_corpus_to (
    v_transliteration_id integer, 
    v_timestamp timestamp with time zone
    )
    LANGUAGE PLPGSQL
    AS 
$BODY$
BEGIN
    CALL @extschema@.revert_to(v_transliteration_id, v_timestamp, '@extschema:cuneiform_corpus@');
    DELETE FROM @extschema:cuneiform_log_tables@.edits WHERE transliteration_id = v_transliteration_id AND timestamp > v_timestamp;
END;
$BODY$;


CREATE OR REPLACE FUNCTION generate_diff_lines (
        v_transliteration_id integer,
        v_timestamp_since timestamp with time zone,
        OUT line_no_start integer,
        OUT line_no_end integer,
        OUT old text,
        OUT new text
    )
    RETURNS SETOF RECORD
    LANGUAGE PLPGSQL
    AS
$BODY$
DECLARE

v_edit_nos integer[];
v_edit_no integer;
v_internal boolean;

v_lines_new text[];

BEGIN

CALL @extschema:cuneiform_create_corpus@.create_corpus('pg_temp', TRUE);
CALL @extschema:cuneiform_actions@.copy_transliteration(v_transliteration_id, '@extschema:cuneiform_corpus@', 'pg_temp');

FOR v_edit_nos, v_internal IN
    WITH
        a AS (
            SELECT
                edit_no,
                internal,
                internal IS DISTINCT FROM lag(internal) OVER (ORDER BY edit_no DESC) AS internal_change
            FROM
                @extschema:cuneiform_log_tables@.edits
            WHERE
                transliteration_id = v_transliteration_id
        ),
        b AS (
            SELECT
                edit_no,
                internal,
                sum(internal_change::integer) OVER (ORDER BY edit_no DESC) AS group_no
            FROM
                a
        )
    SELECT
        array_agg(edit_no ORDER BY edit_no DESC),
        internal
    FROM
        b
    GROUP BY
        group_no,
        internal
    ORDER BY
        group_no
LOOP

    IF NOT v_internal THEN

        SELECT
            @extschema:cuneiform_serialize@.cun_agg (
                COALESCE(character_print, custom_value),
                sign_no, 
                word_no, 
                compound_no,
                NULL, 
                line_no, 
                type,
                indicator_type,
                NULL,
                NULL, 
                condition, 
                NULL, 
                inverted, 
                newline, 
                ligature,
                crits, 
                comment, 
                NULL,
                pn_type,
                NULL,
                compound_comment
                ORDER BY sign_no
                ) 
            INTO 
                v_lines_new
            FROM 
                pg_temp.corpus
                LEFT JOIN pg_temp.words USING (transliteration_id, word_no) 
                LEFT JOIN pg_temp.compounds USING (transliteration_id, compound_no) 
                LEFT JOIN pg_temp.sections USING (transliteration_id, section_no)
                LEFT JOIN @extschema:cuneiform_serialize@.characters_code ON (corpus.sign_variant_id = characters_code.sign_variant_id AND corpus.value_id IS NOT DISTINCT FROM characters_code.value_id);

    END IF;

    FOREACH v_edit_no IN ARRAY v_edit_nos LOOP
        CALL @extschema@.undo(v_transliteration_id, v_edit_no, 'pg_temp');
    END LOOP;

    IF NOT v_internal THEN

    RAISE NOTICE '%', v_edit_nos;

        RETURN QUERY
        WITH 
        lines_old AS (
            SELECT
                @extschema:cuneiform_serialize@.cun_agg (
                    COALESCE(character_print, custom_value),
                    sign_no, 
                    word_no, 
                    compound_no,
                    NULL, 
                    line_no, 
                    type,
                    indicator_type,
                    NULL,
                    NULL, 
                    condition, 
                    NULL, 
                    inverted, 
                    newline, 
                    ligature,
                    crits, 
                    comment, 
                    NULL,
                    pn_type,
                    NULL,
                    compound_comment
                    ORDER BY sign_no
                    ) AS lines_old
                FROM 
                    pg_temp.corpus
                    LEFT JOIN pg_temp.words USING (transliteration_id, word_no) 
                    LEFT JOIN pg_temp.compounds USING (transliteration_id, compound_no) 
                    LEFT JOIN pg_temp.sections USING (transliteration_id, section_no)
                    LEFT JOIN @extschema:cuneiform_serialize@.characters_code ON (corpus.sign_variant_id = characters_code.sign_variant_id AND corpus.value_id IS NOT DISTINCT FROM characters_code.value_id)
        ),
        ops(ord, line_no, entry_no, action) AS (
            SELECT
                0,
                line_no,
                line_no,
                NULL
            FROM
                pg_temp.lines
            UNION ALL
            SELECT
                row_number() OVER (ORDER BY edit_no, log_no),
                line_no,
                entry_no,
                action
            FROM
                unnest(v_edit_nos) AS _(edit_no)
                JOIN @extschema:cuneiform_log_tables@.edit_log USING (edit_no)
                JOIN pg_temp.lines USING (transliteration_id)
            WHERE
                target = 'lines'
        ),
        lines_cor AS (
            SELECT 
                line_no AS line_no_old,
                @extschema:cuneiform_log@.log_trace_entry_agg(action, entry_no ORDER BY ord) AS line_no_new
            FROM
                ops
            GROUP BY
                line_no
        ),
        lines_cor_ord AS (
            SELECT 
                line_no_old,
                line_no_new,
                COALESCE(line_no_new, max(line_no_new) OVER (ORDER BY line_no_old), 0) AS line_no_new_ord
            FROM
                lines_cor
        ),
        x AS (
            SELECT
                row_number() OVER w AS ord,
                line_no_old,
                ord_new-1 AS line_no_new,
                line_old,
                line_new,
                ord_old IS DISTINCT FROM (lag(ord_old) OVER w) +1 
                    AND ord_new IS DISTINCT FROM (lag(ord_new) OVER w)+1 
                    AND NOT (ord_old IS NULL AND lag(ord_new) OVER w IS NULL)
                    AND NOT (ord_new IS NULL AND lag(ord_old) OVER w IS NULL)
                    AS gap
            FROM
                lines_old
                LEFT JOIN LATERAL unnest(lines_old) WITH ORDINALITY AS _(line_old, ord_old) ON TRUE
                JOIN lines_cor_ord ON line_no_old = ord_old-1
                FULL JOIN unnest(v_lines_new) WITH ORDINALITY AS __(line_new, ord_new) ON line_no_new = ord_new-1
            WHERE
                line_old IS DISTINCT FROM line_new
            WINDOW w AS (ORDER BY COALESCE(ord_new-1, line_no_new_ord), line_no_old)
        ),
        y AS (
            SELECT
                ord,
                line_no_old,
                line_no_new,
                line_old,
                line_new,
                sum(gap::integer) OVER (ORDER BY ord) AS group_no
            FROM
                x
         )
         SELECT
            min(line_no_old),
            max(line_no_old),
            string_agg(line_old, ' / ' ORDER BY ord),
            string_agg(line_new, ' / ' ORDER BY ord)
        FROM
            y
        GROUP BY
            group_no;
        
    END IF;

END LOOP;

SET CONSTRAINTS ALL IMMEDIATE;
DISCARD TEMPORARY;

RETURN;

END;
$BODY$;