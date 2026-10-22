-- The triggers on the corpus tables only mark the affected texts as dirty;
-- the statistics are brought up to date once per transaction, at commit.

CREATE OR REPLACE FUNCTION statistics_corpus_trigger_fun ()
    RETURNS trigger
    VOLATILE
    LANGUAGE PLPGSQL
    AS
$BODY$
DECLARE
    v_text_ids  integer[];
BEGIN
    -- rows whose transliteration does not exist (yet or anymore) are covered by statistics_transliterations_trigger_fun
    IF TG_OP = 'INSERT' THEN
        SELECT array_agg(DISTINCT text_id) INTO v_text_ids
        FROM new_table JOIN @extschema:cuneiform_corpus@.transliterations USING (transliteration_id);
    ELSIF TG_OP = 'DELETE' THEN
        SELECT array_agg(DISTINCT text_id) INTO v_text_ids
        FROM old_table JOIN @extschema:cuneiform_corpus@.transliterations USING (transliteration_id);
    ELSE
        -- only rows in which columns relevant for the statistics have changed
        SELECT array_agg(DISTINCT text_id) INTO v_text_ids
        FROM (
            (
                SELECT transliteration_id, value_id, sign_variant_id FROM old_table
                EXCEPT ALL
                SELECT transliteration_id, value_id, sign_variant_id FROM new_table
            )
            UNION ALL
            (
                SELECT transliteration_id, value_id, sign_variant_id FROM new_table
                EXCEPT ALL
                SELECT transliteration_id, value_id, sign_variant_id FROM old_table
            )
        ) _
        JOIN @extschema:cuneiform_corpus@.transliterations USING (transliteration_id);
    END IF;

    PERFORM @extschema@.statistics_mark_dirty(v_text_ids);
    RETURN NULL;
END;
$BODY$;


CREATE OR REPLACE FUNCTION statistics_transliterations_trigger_fun ()
    RETURNS trigger
    VOLATILE
    LANGUAGE PLPGSQL
    AS
$BODY$
DECLARE
    v_text_ids  integer[];
BEGIN
    IF TG_OP = 'INSERT' THEN
        SELECT array_agg(text_id) INTO v_text_ids FROM new_table;
    ELSIF TG_OP = 'DELETE' THEN
        SELECT array_agg(text_id) INTO v_text_ids FROM old_table;
    ELSE
        SELECT array_agg(text_id) INTO v_text_ids
        FROM (
            (
                SELECT transliteration_id, text_id FROM old_table
                EXCEPT
                SELECT transliteration_id, text_id FROM new_table
            )
            UNION ALL
            (
                SELECT transliteration_id, text_id FROM new_table
                EXCEPT
                SELECT transliteration_id, text_id FROM old_table
            )
        ) _;
    END IF;

    PERFORM @extschema@.statistics_mark_dirty(v_text_ids);
    RETURN NULL;
END;
$BODY$;


CREATE OR REPLACE FUNCTION statistics_texts_trigger_fun ()
    RETURNS trigger
    VOLATILE
    LANGUAGE PLPGSQL
    AS
$BODY$
DECLARE
    v_text_ids  integer[];
BEGIN
    IF TG_OP = 'INSERT' THEN
        SELECT array_agg(text_id) INTO v_text_ids FROM new_table;
    ELSIF TG_OP = 'DELETE' THEN
        SELECT array_agg(text_id) INTO v_text_ids FROM old_table;
    ELSE
        SELECT array_agg(text_id) INTO v_text_ids
        FROM (
            (
                SELECT text_id, period_id, provenience_id, genre_id, object_id FROM old_table
                EXCEPT
                SELECT text_id, period_id, provenience_id, genre_id, object_id FROM new_table
            )
            UNION ALL
            (
                SELECT text_id, period_id, provenience_id, genre_id, object_id FROM new_table
                EXCEPT
                SELECT text_id, period_id, provenience_id, genre_id, object_id FROM old_table
            )
        ) _;
    END IF;

    PERFORM @extschema@.statistics_mark_dirty(v_text_ids);
    RETURN NULL;
END;
$BODY$;


CREATE OR REPLACE FUNCTION statistics_truncate_trigger_fun ()
    RETURNS trigger
    VOLATILE
    LANGUAGE PLPGSQL
    AS
$BODY$
BEGIN
    PERFORM @extschema@.statistics_rebuild();
    RETURN NULL;
END;
$BODY$;


CREATE OR REPLACE FUNCTION statistics_flush_queue_trigger_fun ()
    RETURNS trigger
    VOLATILE
    LANGUAGE PLPGSQL
    AS
$BODY$
BEGIN
    PERFORM @extschema@.statistics_flush();
    RETURN NULL;
END;
$BODY$;


CREATE TRIGGER statistics_corpus_insert_trigger
    AFTER INSERT ON @extschema:cuneiform_corpus@.corpus
    REFERENCING NEW TABLE AS new_table
    FOR EACH STATEMENT
    EXECUTE FUNCTION statistics_corpus_trigger_fun();

CREATE TRIGGER statistics_corpus_update_trigger
    AFTER UPDATE ON @extschema:cuneiform_corpus@.corpus
    REFERENCING OLD TABLE AS old_table NEW TABLE AS new_table
    FOR EACH STATEMENT
    EXECUTE FUNCTION statistics_corpus_trigger_fun();

CREATE TRIGGER statistics_corpus_delete_trigger
    AFTER DELETE ON @extschema:cuneiform_corpus@.corpus
    REFERENCING OLD TABLE AS old_table
    FOR EACH STATEMENT
    EXECUTE FUNCTION statistics_corpus_trigger_fun();

CREATE TRIGGER statistics_corpus_truncate_trigger
    AFTER TRUNCATE ON @extschema:cuneiform_corpus@.corpus
    FOR EACH STATEMENT
    EXECUTE FUNCTION statistics_truncate_trigger_fun();

CREATE TRIGGER statistics_transliterations_insert_trigger
    AFTER INSERT ON @extschema:cuneiform_corpus@.transliterations
    REFERENCING NEW TABLE AS new_table
    FOR EACH STATEMENT
    EXECUTE FUNCTION statistics_transliterations_trigger_fun();

CREATE TRIGGER statistics_transliterations_update_trigger
    AFTER UPDATE ON @extschema:cuneiform_corpus@.transliterations
    REFERENCING OLD TABLE AS old_table NEW TABLE AS new_table
    FOR EACH STATEMENT
    EXECUTE FUNCTION statistics_transliterations_trigger_fun();

CREATE TRIGGER statistics_transliterations_delete_trigger
    AFTER DELETE ON @extschema:cuneiform_corpus@.transliterations
    REFERENCING OLD TABLE AS old_table
    FOR EACH STATEMENT
    EXECUTE FUNCTION statistics_transliterations_trigger_fun();

CREATE TRIGGER statistics_transliterations_truncate_trigger
    AFTER TRUNCATE ON @extschema:cuneiform_corpus@.transliterations
    FOR EACH STATEMENT
    EXECUTE FUNCTION statistics_truncate_trigger_fun();

CREATE TRIGGER statistics_texts_insert_trigger
    AFTER INSERT ON @extschema:cuneiform_corpus@.texts
    REFERENCING NEW TABLE AS new_table
    FOR EACH STATEMENT
    EXECUTE FUNCTION statistics_texts_trigger_fun();

CREATE TRIGGER statistics_texts_update_trigger
    AFTER UPDATE ON @extschema:cuneiform_corpus@.texts
    REFERENCING OLD TABLE AS old_table NEW TABLE AS new_table
    FOR EACH STATEMENT
    EXECUTE FUNCTION statistics_texts_trigger_fun();

CREATE TRIGGER statistics_texts_delete_trigger
    AFTER DELETE ON @extschema:cuneiform_corpus@.texts
    REFERENCING OLD TABLE AS old_table
    FOR EACH STATEMENT
    EXECUTE FUNCTION statistics_texts_trigger_fun();

CREATE TRIGGER statistics_texts_truncate_trigger
    AFTER TRUNCATE ON @extschema:cuneiform_corpus@.texts
    FOR EACH STATEMENT
    EXECUTE FUNCTION statistics_truncate_trigger_fun();

CREATE CONSTRAINT TRIGGER statistics_flush_queue_trigger
    AFTER INSERT ON statistics_flush_queue
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION statistics_flush_queue_trigger_fun();


SELECT statistics_rebuild();
