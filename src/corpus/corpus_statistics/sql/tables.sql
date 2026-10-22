-- Per-text snapshots: what each text currently contributes to values_present and sign_variants_present,
-- including the dimensions and the normalizer it was added under. statistics_flush() subtracts a text's
-- snapshot, recomputes it from the corpus and adds it again.

CREATE TABLE texts_snapshot (
    text_id integer PRIMARY KEY,
    period_id integer,
    provenience_id integer,
    genre_id integer,
    object_id integer,
    transliteration_count integer NOT NULL
);

CREATE TABLE texts_snapshot_values (
    text_id integer,
    value_id integer,
    count integer NOT NULL,
    PRIMARY KEY (text_id, value_id)
);

CREATE TABLE texts_snapshot_sign_variants (
    text_id integer,
    sign_variant_id integer,
    count integer NOT NULL,
    PRIMARY KEY (text_id, sign_variant_id)
);


-- Aggregated statistics

CREATE TABLE values_present (
    value_id integer NOT NULL,
    period_id integer,
    provenience_id integer,
    genre_id integer,
    object_id integer,
    count integer NOT NULL,
    count_norm double precision NOT NULL,
    UNIQUE NULLS NOT DISTINCT (value_id, period_id, provenience_id, genre_id, object_id)
);

CREATE TABLE sign_variants_present (
    sign_variant_id integer NOT NULL,
    period_id integer,
    provenience_id integer,
    genre_id integer,
    object_id integer,
    count integer NOT NULL,
    count_norm double precision NOT NULL,
    UNIQUE NULLS NOT DISTINCT (sign_variant_id, period_id, provenience_id, genre_id, object_id)
);

CREATE INDEX ON values_present (value_id) WHERE count = 0;
CREATE INDEX ON sign_variants_present (sign_variant_id) WHERE count = 0;


-- Texts whose snapshots are outdated, and one entry per transaction that has to flush them at commit

CREATE TABLE statistics_dirty_texts (
    text_id integer PRIMARY KEY
);

CREATE TABLE statistics_flush_queue (
    xact_id xid8 PRIMARY KEY
);


-- Snapshots computed from scratch

CREATE OR REPLACE VIEW texts_snapshot_view AS
SELECT
    texts.text_id,
    texts.period_id,
    texts.provenience_id,
    texts.genre_id,
    texts.object_id,
    count(transliterations.transliteration_id)::integer AS transliteration_count
FROM
    @extschema:cuneiform_corpus@.texts
    LEFT JOIN @extschema:cuneiform_corpus@.transliterations ON transliterations.text_id = texts.text_id
GROUP BY
    texts.text_id;

CREATE OR REPLACE VIEW texts_snapshot_values_view AS
SELECT
    text_id,
    value_id,
    count(*)::integer AS count
FROM
    @extschema:cuneiform_corpus@.corpus
    JOIN @extschema:cuneiform_corpus@.transliterations USING (transliteration_id)
WHERE
    value_id IS NOT NULL
GROUP BY
    text_id,
    value_id;

CREATE OR REPLACE VIEW texts_snapshot_sign_variants_view AS
SELECT
    text_id,
    sign_variant_id,
    count(*)::integer AS count
FROM
    @extschema:cuneiform_corpus@.corpus
    JOIN @extschema:cuneiform_corpus@.transliterations USING (transliteration_id)
WHERE
    sign_variant_id IS NOT NULL
GROUP BY
    text_id,
    sign_variant_id;


-- Aggregated statistics computed from the snapshots

CREATE OR REPLACE VIEW values_present_view AS
SELECT
    value_id,
    period_id,
    provenience_id,
    genre_id,
    object_id,
    sum(count)::integer AS count,
    sum(count::double precision / transliteration_count) AS count_norm
FROM
    texts_snapshot_values
    JOIN texts_snapshot USING (text_id)
GROUP BY
    value_id,
    period_id,
    provenience_id,
    genre_id,
    object_id;

CREATE OR REPLACE VIEW sign_variants_present_view AS
SELECT
    sign_variant_id,
    period_id,
    provenience_id,
    genre_id,
    object_id,
    sum(count)::integer AS count,
    sum(count::double precision / transliteration_count) AS count_norm
FROM
    texts_snapshot_sign_variants
    JOIN texts_snapshot USING (text_id)
GROUP BY
    sign_variant_id,
    period_id,
    provenience_id,
    genre_id,
    object_id;
