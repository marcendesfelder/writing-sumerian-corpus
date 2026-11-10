CREATE TYPE sign_meaning AS (
    word_no integer,
    value_id integer,
    sign_id integer,
    indicator_type @extschema:cuneiform_sign_properties@.indicator_type,
    phonographic boolean,
    stem boolean,
    capitalized boolean
);


CREATE FUNCTION value_ids (v_sign_meanings sign_meaning[])
    RETURNS integer[]
    IMMUTABLE
    LANGUAGE SQL
BEGIN  ATOMIC

SELECT
    array_agg(value_id ORDER BY ord)
FROM
    UNNEST(v_sign_meanings) WITH ORDINALITY AS _(word_no, value_id, sign_id, indicator_type, phonographic, stem, capitalized, ord);
END;


CREATE FUNCTION sign_ids (v_sign_meanings sign_meaning[])
    RETURNS integer[]
    IMMUTABLE
    LANGUAGE SQL
BEGIN  ATOMIC

SELECT
    array_agg(sign_id ORDER BY ord)
FROM
    UNNEST(v_sign_meanings) WITH ORDINALITY AS _(word_no, value_id, sign_id, indicator_type, phonographic, stem, capitalized, ord);
END;


CREATE FUNCTION uncapitalized (v_sign_meanings sign_meaning[])
    RETURNS sign_meaning[]
    IMMUTABLE
    LANGUAGE SQL
BEGIN  ATOMIC

SELECT
    array_agg(ROW(word_no, value_id, sign_id, indicator_type, phonographic, stem, FALSE)::sign_meaning ORDER BY ord)
FROM
    UNNEST(v_sign_meanings) WITH ORDINALITY AS _(word_no, value_id, sign_id, indicator_type, phonographic, stem, capitalized, ord);
END;

CREATE FUNCTION is_stemmed (v_sign_meanings sign_meaning[])
    RETURNS boolean
    IMMUTABLE
    LANGUAGE SQL
BEGIN ATOMIC
SELECT
    bool_and(stem IS NOT NULL)
FROM
    UNNEST(v_sign_meanings) WITH ORDINALITY AS _(word_no, value_id, sign_id, indicator_type, phonographic, stem, capitalized, ord);
END;


CREATE FUNCTION is_half_stemmed (v_sign_meanings sign_meaning[])
    RETURNS boolean
    IMMUTABLE
    LANGUAGE SQL
BEGIN ATOMIC
SELECT
    bool_and(stem IS NOT NULL) OR bool_and(stem IS NULL)
FROM
    UNNEST(v_sign_meanings) WITH ORDINALITY AS _(word_no, value_id, sign_id, indicator_type, phonographic, stem, capitalized, ord);
END;


CREATE FUNCTION has_affix (v_sign_meanings sign_meaning[])
    RETURNS boolean
    IMMUTABLE
    LANGUAGE SQL
BEGIN ATOMIC
SELECT
    bool_or(NOT stem ORDER BY ord)
FROM
    UNNEST(v_sign_meanings) WITH ORDINALITY AS _(word_no, value_id, sign_id, indicator_type, phonographic, stem, capitalized, ord);
END;


CREATE FUNCTION sign_variant_ids (
    v_sign_meanings sign_meaning[],
    v_variant_types @extschema:cuneiform_signlist@.sign_variant_type[] = '{default}'
  )
  RETURNS TABLE (
    sign_variant_ids integer[]
  )
  LANGUAGE SQL
  STABLE
BEGIN ATOMIC

WITH RECURSIVE
a AS (
  SELECT
    v_sign_meanings AS sign_meanings,
    ARRAY[]::integer[] AS sign_variant_ids
  UNION ALL
  SELECT
    sign_meanings[2:],
    sign_variant_ids || sign_variant_id
  FROM
    a
    CROSS JOIN LATERAL (       -- forces an index lookup per row, the planner would otherwise scan sign_variants in every iteration
      SELECT
        sign_variant_id
      FROM
        @extschema:cuneiform_signlist@.sign_variants
      WHERE
        sign_variants.sign_id = (a.sign_meanings[1]).sign_id
        AND variant_type = ANY (v_variant_types)
    ) _
)
SELECT
  sign_variant_ids
FROM
  a
WHERE
  cardinality(sign_meanings) = 0;
END;