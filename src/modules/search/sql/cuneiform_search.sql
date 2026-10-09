CREATE TYPE cun_position;

CREATE FUNCTION cun_position_in (cstring)
    RETURNS cun_position
    AS 'cuneiform_search', 'position_in'
    LANGUAGE C
    IMMUTABLE STRICT;

CREATE FUNCTION cun_position_out (cun_position)
    RETURNS cstring
    AS 'cuneiform_search', 'position_out'
    LANGUAGE C
    IMMUTABLE STRICT;

CREATE FUNCTION cun_position_recv (internal)
    RETURNS cun_position
    AS 'cuneiform_search', 'position_recv'
    LANGUAGE C
    IMMUTABLE STRICT;

CREATE FUNCTION cun_position_send (cun_position)
    RETURNS bytea
    AS 'cuneiform_search', 'position_send'
    LANGUAGE C
    IMMUTABLE STRICT;

CREATE TYPE cun_position (
   internallength = 4,
   passedbyvalue,
   input = cun_position_in,
   output = cun_position_out,
   receive = cun_position_recv,
   send = cun_position_send,
   alignment = integer
);


CREATE FUNCTION cun_position_less (cun_position, cun_position)
    RETURNS bool
    AS 'cuneiform_search', 'position_less'
    LANGUAGE C
    IMMUTABLE STRICT;

CREATE FUNCTION cun_position_greater (cun_position, cun_position)
    RETURNS bool
    AS 'cuneiform_search', 'position_greater'
    LANGUAGE C
    IMMUTABLE STRICT;

CREATE FUNCTION cun_position_leq (cun_position, cun_position)
    RETURNS bool
    AS 'cuneiform_search', 'position_leq'
    LANGUAGE C
    IMMUTABLE STRICT;

CREATE FUNCTION cun_position_geq (cun_position, cun_position)
    RETURNS bool
    AS 'cuneiform_search', 'position_geq'
    LANGUAGE C
    IMMUTABLE STRICT;

CREATE FUNCTION cun_position_equal (cun_position, cun_position)
    RETURNS bool
    AS 'cuneiform_search', 'position_equal'
    LANGUAGE C
    IMMUTABLE STRICT;

CREATE FUNCTION cun_position_neq (cun_position, cun_position)
    RETURNS bool
    AS 'cuneiform_search', 'position_neq'
    LANGUAGE C
    IMMUTABLE STRICT;


CREATE OPERATOR < (
    leftarg = cun_position,
    rightarg = cun_position,
    procedure = cun_position_less,
    commutator = >,
    negator = >=,
    restrict = scalarltsel,
    join = scalarltjoinsel
);

CREATE OPERATOR > (
    leftarg = cun_position,
    rightarg = cun_position,
    procedure = cun_position_greater,
    commutator = <,
    negator = <=,
    restrict = scalargtsel,
    join = scalargtjoinsel
);

CREATE OPERATOR <= (
    leftarg = cun_position,
    rightarg = cun_position,
    procedure = cun_position_leq,
    commutator = >=,
    negator = >,
    restrict = scalarltsel,
    join = scalarltjoinsel
);

CREATE OPERATOR >= (
    leftarg = cun_position,
    rightarg = cun_position,
    procedure = cun_position_geq,
    commutator = <=,
    negator = <,
    restrict = scalargtsel,
    join = scalargtjoinsel
);

CREATE OPERATOR = (
    leftarg = cun_position,
    rightarg = cun_position,
    procedure = cun_position_equal,
    commutator = =,
    negator = <>,
    restrict = eqsel,
    join = eqjoinsel,
    HASHES,
    MERGES
);

CREATE OPERATOR <> (
    leftarg = cun_position,
    rightarg = cun_position,
    procedure = cun_position_neq,
    commutator = <>,
    negator = =,
    restrict = neqsel,
    join = neqjoinsel
);


CREATE FUNCTION cun_position_order (cun_position, cun_position)
    RETURNS integer
    AS 'cuneiform_search', 'position_order'
    LANGUAGE C
    IMMUTABLE STRICT;

CREATE FUNCTION cun_position_equalimage (oid)
    RETURNS bool
    AS 'cuneiform_search', 'position_equalimage'
    LANGUAGE C
    IMMUTABLE STRICT;

CREATE FUNCTION cun_position_hash (cun_position)
    RETURNS integer
    AS 'cuneiform_search', 'position_hash'
    LANGUAGE C
    IMMUTABLE STRICT;

CREATE FUNCTION cun_position_hash_extended (cun_position, bigint)
    RETURNS bigint
    AS 'cuneiform_search', 'position_hash_extended'
    LANGUAGE C
    IMMUTABLE STRICT;


CREATE OPERATOR FAMILY btree_cun_position_ops USING btree;

CREATE OPERATOR CLASS btree_cun_position_ops
    DEFAULT FOR TYPE cun_position USING btree FAMILY btree_cun_position_ops AS
        OPERATOR        1       <,
        OPERATOR        2       <=,
        OPERATOR        3       =,
        OPERATOR        4       >=,
        OPERATOR        5       >,
        FUNCTION        1       cun_position_order,
        FUNCTION        4       cun_position_equalimage;

CREATE OPERATOR FAMILY hash_cun_position_ops USING hash;

CREATE OPERATOR CLASS hash_cun_position_ops
    DEFAULT FOR TYPE cun_position USING hash FAMILY hash_cun_position_ops AS
        OPERATOR        1       =,
        FUNCTION        1       cun_position_hash,
        FUNCTION        2       cun_position_hash_extended;

CREATE OPERATOR FAMILY brin_cun_position_minmax_ops USING brin;

CREATE OPERATOR CLASS brin_cun_position_minmax_ops
    DEFAULT FOR TYPE cun_position USING brin FAMILY brin_cun_position_minmax_ops AS
        OPERATOR        1       <,
        OPERATOR        2       <=,
        OPERATOR        3       =,
        OPERATOR        4       >=,
        OPERATOR        5       >,
        FUNCTION        1       brin_minmax_opcinfo,
        FUNCTION        2       brin_minmax_add_value,
        FUNCTION        3       brin_minmax_consistent,
        FUNCTION        4       brin_minmax_union;

CREATE FUNCTION next (cun_position)
    RETURNS cun_position
    AS 'cuneiform_search', 'position_next'
    LANGUAGE C
    IMMUTABLE STRICT;


CREATE FUNCTION sign_no(cun_position)
    RETURNS int
    AS 'cuneiform_search', 'position_sign_no'
    LANGUAGE C
    IMMUTABLE STRICT;

CREATE FUNCTION component_no(cun_position)
    RETURNS int
    AS 'cuneiform_search', 'position_component_no'
    LANGUAGE C
    IMMUTABLE STRICT;

CREATE FUNCTION cun_position(integer, integer, bool)
    RETURNS cun_position
    AS 'cuneiform_search', 'position_construct'
    LANGUAGE C
    IMMUTABLE STRICT;




CREATE OR REPLACE FUNCTION uniq (VARIADIC cun_position[])
    RETURNS bool
    AS 'cuneiform_search', 'unique'
    LANGUAGE C
    IMMUTABLE STRICT
    COST 10;

CREATE OR REPLACE FUNCTION consecutive (VARIADIC cun_position[])
    RETURNS bool
    AS 'cuneiform_search', 'consecutive'
    LANGUAGE C
    IMMUTABLE STRICT
    COST 10;

CREATE OR REPLACE FUNCTION get_sign_nos (VARIADIC cun_position[] DEFAULT '{}')
    RETURNS int[]
    AS 'cuneiform_search', 'get_sign_nos'
    LANGUAGE C
    IMMUTABLE STRICT
    COST 10;

CREATE OR REPLACE FUNCTION sort_uniq_remove_null (VARIADIC integer[] DEFAULT '{}')
    RETURNS int[]
    AS 'cuneiform_search', 'sort_uniq_remove_null'
    LANGUAGE C
    IMMUTABLE STRICT
    COST 10;


CREATE TYPE search_wildcard AS (
    wildcard_id integer,
    sign_nos integer[]
);


CREATE VIEW values_search (value, sign_spec, code) AS
SELECT
    value,
    null,
    'v' || value_id::text
FROM
    @extschema:cuneiform_signlist@.value_variants
    LEFT JOIN @extschema:cuneiform_signlist@.values USING (value_id)
UNION ALL
SELECT
    value,
    glyphs,
    'v' || value_id::text || 's' || sign_variant_id::text
FROM
    @extschema:cuneiform_signlist@.value_variants
    LEFT JOIN @extschema:cuneiform_signlist@.values USING (value_id)
    JOIN @extschema:cuneiform_signlist@.sign_variants_composition USING (sign_id)
UNION ALL
SELECT
    value,
    CASE WHEN i = 1 THEN NULL ELSE glyphs END,
    'v' || value_id::text || 's' || sign_variant_id::text
FROM
    @extschema:cuneiform_signlist@.glyph_values 
    JOIN @extschema:cuneiform_signlist@.values USING (value_id)
    JOIN @extschema:cuneiform_signlist@.sign_variants_composition USING (sign_id, glyph_ids)
    LEFT JOIN LATERAL generate_series(1, 2) AS _(i) ON TRUE;


CREATE VIEW signs_search (sign, sign_spec, code) AS
SELECT
    upper(value),
    NULL,
    'S' || sign_id::text
FROM
    @extschema:cuneiform_signlist@.value_variants
    LEFT JOIN @extschema:cuneiform_signlist@.values USING (value_id)
UNION
SELECT
    upper(value),
    glyphs,
    's' || sign_variant_id::text
FROM
    @extschema:cuneiform_signlist@.value_variants
    LEFT JOIN @extschema:cuneiform_signlist@.values USING (value_id)
    JOIN @extschema:cuneiform_signlist@.sign_variants_composition USING (sign_id)
UNION
SELECT
    upper(value),
    CASE WHEN i = 1 THEN NULL ELSE glyphs END,
    's' || sign_variant_id::text
FROM
    @extschema:cuneiform_signlist@.glyph_values 
    JOIN @extschema:cuneiform_signlist@.sign_variants_composition USING (glyph_ids)
    LEFT JOIN LATERAL generate_series(1, 2) AS _(i) ON TRUE
UNION
SELECT
    glyphs,
    NULL,
    'S' || sign_id::text
FROM
    @extschema:cuneiform_signlist@.sign_variants_composition
WHERE
    specific
UNION
SELECT
    a.glyphs,
    b.glyphs,
    's' || b.sign_variant_id::text
FROM
    @extschema:cuneiform_signlist@.sign_variants_composition a
    JOIN @extschema:cuneiform_signlist@.sign_variants_composition b USING (sign_id)
WHERE
    a.specific;


CREATE OR REPLACE VIEW forms_search (form, sign_spec, code) AS
SELECT
    upper(value),
    NULL,
    'g' || grapheme_ids[1]::text
FROM
    @extschema:cuneiform_signlist@.value_variants
    LEFT JOIN @extschema:cuneiform_signlist@.values USING (value_id)
    LEFT JOIN @extschema:cuneiform_signlist@.sign_variants_composition USING (sign_id)
WHERE
    cardinality(grapheme_ids) = 1
    AND specific
UNION
SELECT
    upper(value),
    glyphs,
    'g' || grapheme_ids[1]::text || 'c' || glyph_ids[1]::text
FROM
    @extschema:cuneiform_signlist@.value_variants
    LEFT JOIN @extschema:cuneiform_signlist@.values USING (value_id)
    LEFT JOIN @extschema:cuneiform_signlist@.sign_variants_composition USING (sign_id)
WHERE
    cardinality(grapheme_ids) = 1
    AND specific
UNION
SELECT
    upper(value),
    CASE WHEN i = 1 THEN NULL ELSE glyphs END,
    'c' || glyph_ids[1]::text
FROM
    @extschema:cuneiform_signlist@.value_variants
    LEFT JOIN @extschema:cuneiform_signlist@.values USING (value_id)
    LEFT JOIN @extschema:cuneiform_signlist@.sign_variants_composition USING (sign_id)
    LEFT JOIN LATERAL generate_series(1, 2) AS _(i) ON TRUE
WHERE
    cardinality(grapheme_ids) = 1
    AND specific
UNION
SELECT
    upper(value),
    CASE WHEN i = 1 THEN NULL ELSE glyphs END,
    'g' || grapheme_ids[1]::text || 'c' || sign_variants_composition.glyph_ids[1]::text
FROM
    @extschema:cuneiform_signlist@.glyph_values
    JOIN @extschema:cuneiform_signlist@.values USING (value_id)
    JOIN @extschema:cuneiform_signlist@.sign_variants_composition USING (sign_id, glyph_ids)
    LEFT JOIN LATERAL generate_series(1, 2) AS __(i) ON TRUE
WHERE
    cardinality(grapheme_ids) = 1
    AND specific
UNION
SELECT
    glyph,
    CASE WHEN i = 1 THEN NULL ELSE glyph END,
    'c' || glyph_id::text
FROM
    @extschema:cuneiform_signlist@.glyphs
    LEFT JOIN LATERAL generate_series(1, 2) AS __(i) ON TRUE;
