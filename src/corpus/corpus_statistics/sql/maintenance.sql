-- Marks texts as dirty and makes sure the current transaction flushes them at commit

CREATE OR REPLACE FUNCTION statistics_mark_dirty (
    v_text_ids integer[]
  )
    RETURNS void
    VOLATILE
    LANGUAGE PLPGSQL
    AS
$BODY$
BEGIN
    IF v_text_ids IS NULL THEN
        RETURN;
    END IF;

    INSERT INTO @extschema@.statistics_dirty_texts
    SELECT DISTINCT unnest(v_text_ids)
    ON CONFLICT DO NOTHING;

    INSERT INTO @extschema@.statistics_flush_queue VALUES (pg_current_xact_id())
    ON CONFLICT DO NOTHING;
END;
$BODY$;


-- Adds or subtracts the snapshots of the given texts to/from the aggregated statistics

CREATE OR REPLACE FUNCTION statistics_apply (
    v_text_ids integer[],
    v_subtract boolean
  )
    RETURNS void
    VOLATILE
    LANGUAGE SQL
    AS
$BODY$
    INSERT INTO @extschema@.values_present
    SELECT
        value_id,
        period_id,
        provenience_id,
        genre_id,
        object_id,
        -1 ^ v_subtract::integer * sum(count),
        -1 ^ v_subtract::integer * sum(count::double precision / transliteration_count)
    FROM
        @extschema@.texts_snapshot_values
        JOIN @extschema@.texts_snapshot USING (text_id)
    WHERE
        text_id = ANY(v_text_ids)
    GROUP BY
        value_id,
        period_id,
        provenience_id,
        genre_id,
        object_id
    ORDER BY
        value_id,
        period_id,
        provenience_id,
        genre_id,
        object_id
    ON CONFLICT (value_id, period_id, provenience_id, genre_id, object_id) DO UPDATE SET
        count = values_present.count + excluded.count,
        count_norm = values_present.count_norm + excluded.count_norm;

    INSERT INTO @extschema@.sign_variants_present
    SELECT
        sign_variant_id,
        period_id,
        provenience_id,
        genre_id,
        object_id,
        -1 ^ v_subtract::integer * sum(count),
        -1 ^ v_subtract::integer * sum(count::double precision / transliteration_count)
    FROM
        @extschema@.texts_snapshot_sign_variants
        JOIN @extschema@.texts_snapshot USING (text_id)
    WHERE
        text_id = ANY(v_text_ids)
    GROUP BY
        sign_variant_id,
        period_id,
        provenience_id,
        genre_id,
        object_id
    ORDER BY
        sign_variant_id,
        period_id,
        provenience_id,
        genre_id,
        object_id
    ON CONFLICT (sign_variant_id, period_id, provenience_id, genre_id, object_id) DO UPDATE SET
        count = sign_variants_present.count + excluded.count,
        count_norm = sign_variants_present.count_norm + excluded.count_norm;
$BODY$;


-- Recomputes all statistics from scratch

CREATE OR REPLACE FUNCTION statistics_rebuild ()
    RETURNS void
    VOLATILE
    LANGUAGE SQL
    AS
$BODY$
    -- no TRUNCATE: the table may have pending trigger events
    DELETE FROM @extschema@.statistics_dirty_texts;

    TRUNCATE
        @extschema@.texts_snapshot,
        @extschema@.texts_snapshot_values,
        @extschema@.texts_snapshot_sign_variants,
        @extschema@.values_present,
        @extschema@.sign_variants_present;

    INSERT INTO @extschema@.texts_snapshot SELECT * FROM @extschema@.texts_snapshot_view;
    INSERT INTO @extschema@.texts_snapshot_values SELECT * FROM @extschema@.texts_snapshot_values_view;
    INSERT INTO @extschema@.texts_snapshot_sign_variants SELECT * FROM @extschema@.texts_snapshot_sign_variants_view;
    INSERT INTO @extschema@.values_present SELECT * FROM @extschema@.values_present_view;
    INSERT INTO @extschema@.sign_variants_present SELECT * FROM @extschema@.sign_variants_present_view;
$BODY$;


-- Brings the snapshots of all dirty texts up to date

CREATE OR REPLACE FUNCTION statistics_flush ()
    RETURNS void
    VOLATILE
    LANGUAGE PLPGSQL
    AS
$BODY$
DECLARE
    v_text_ids  integer[];
BEGIN
    DELETE FROM @extschema@.statistics_flush_queue WHERE xact_id = pg_current_xact_id();

    WITH dirty AS (
        DELETE FROM @extschema@.statistics_dirty_texts RETURNING text_id
    )
    SELECT array_agg(text_id) INTO v_text_ids FROM dirty;

    IF v_text_ids IS NULL THEN
        RETURN;
    END IF;

    -- for bulk changes a full rebuild is cheaper than updating text by text
    IF cardinality(v_text_ids) > 1000 AND cardinality(v_text_ids) > (SELECT count(*) FROM @extschema:cuneiform_corpus@.texts) / 2 THEN
        PERFORM @extschema@.statistics_rebuild();
        RETURN;
    END IF;

    PERFORM @extschema@.statistics_apply(v_text_ids, true);

    DELETE FROM @extschema@.texts_snapshot WHERE text_id = ANY(v_text_ids);
    DELETE FROM @extschema@.texts_snapshot_values WHERE text_id = ANY(v_text_ids);
    DELETE FROM @extschema@.texts_snapshot_sign_variants WHERE text_id = ANY(v_text_ids);

    INSERT INTO @extschema@.texts_snapshot SELECT * FROM @extschema@.texts_snapshot_view WHERE text_id = ANY(v_text_ids);
    INSERT INTO @extschema@.texts_snapshot_values SELECT * FROM @extschema@.texts_snapshot_values_view WHERE text_id = ANY(v_text_ids);
    INSERT INTO @extschema@.texts_snapshot_sign_variants SELECT * FROM @extschema@.texts_snapshot_sign_variants_view WHERE text_id = ANY(v_text_ids);

    PERFORM @extschema@.statistics_apply(v_text_ids, false);

    DELETE FROM @extschema@.values_present WHERE count = 0;
    DELETE FROM @extschema@.sign_variants_present WHERE count = 0;
END;
$BODY$;


-- Lists all differences between the stored statistics and the statistics computed from scratch (empty if consistent)

CREATE OR REPLACE FUNCTION statistics_check ()
    RETURNS TABLE (
        relation text,
        difference text,
        entry jsonb
    )
    STABLE
    LANGUAGE SQL
    AS
$BODY$
    SELECT 'texts_snapshot', 'extra', to_jsonb(a) FROM (
        TABLE @extschema@.texts_snapshot EXCEPT TABLE @extschema@.texts_snapshot_view) a
    UNION ALL
    SELECT 'texts_snapshot', 'missing', to_jsonb(a) FROM (
        TABLE @extschema@.texts_snapshot_view EXCEPT TABLE @extschema@.texts_snapshot) a
    UNION ALL
    SELECT 'texts_snapshot_values', 'extra', to_jsonb(a) FROM (
        TABLE @extschema@.texts_snapshot_values EXCEPT TABLE @extschema@.texts_snapshot_values_view) a
    UNION ALL
    SELECT 'texts_snapshot_values', 'missing', to_jsonb(a) FROM (
        TABLE @extschema@.texts_snapshot_values_view EXCEPT TABLE @extschema@.texts_snapshot_values) a
    UNION ALL
    SELECT 'texts_snapshot_sign_variants', 'extra', to_jsonb(a) FROM (
        TABLE @extschema@.texts_snapshot_sign_variants EXCEPT TABLE @extschema@.texts_snapshot_sign_variants_view) a
    UNION ALL
    SELECT 'texts_snapshot_sign_variants', 'missing', to_jsonb(a) FROM (
        TABLE @extschema@.texts_snapshot_sign_variants_view EXCEPT TABLE @extschema@.texts_snapshot_sign_variants) a
    UNION ALL
    -- count_norm is maintained incrementally in floating point and may deviate slightly from the value
    -- computed from scratch, so it is compared with a tolerance.
    SELECT 'values_present', difference, entry
    FROM
        (SELECT ROW(value_id, period_id, provenience_id, genre_id, object_id) AS key, a AS stored FROM @extschema@.values_present a) s
        FULL JOIN (SELECT ROW(value_id, period_id, provenience_id, genre_id, object_id) AS key, a AS fresh FROM @extschema@.values_present_view a) f USING (key)
        CROSS JOIN LATERAL (VALUES ('extra', to_jsonb(stored)), ('missing', to_jsonb(fresh))) v (difference, entry)
    WHERE
        entry IS NOT NULL
        AND ((stored).count IS DISTINCT FROM (fresh).count OR NOT abs((stored).count_norm - (fresh).count_norm) < 1e-9)
    UNION ALL
    SELECT 'sign_variants_present', difference, entry
    FROM
        (SELECT ROW(sign_variant_id, period_id, provenience_id, genre_id, object_id) AS key, a AS stored FROM @extschema@.sign_variants_present a) s
        FULL JOIN (SELECT ROW(sign_variant_id, period_id, provenience_id, genre_id, object_id) AS key, a AS fresh FROM @extschema@.sign_variants_present_view a) f USING (key)
        CROSS JOIN LATERAL (VALUES ('extra', to_jsonb(stored)), ('missing', to_jsonb(fresh))) v (difference, entry)
    WHERE
        entry IS NOT NULL
        AND ((stored).count IS DISTINCT FROM (fresh).count OR NOT abs((stored).count_norm - (fresh).count_norm) < 1e-9);
$BODY$;
