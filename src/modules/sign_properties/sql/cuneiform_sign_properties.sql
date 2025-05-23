CREATE TYPE language AS ENUM (
    'sumerian',
    'akkadian',
    'hittite',
    'eblaite',
    'emesal',
    'other'
);

CREATE TYPE sign_type AS ENUM (
    'value',
    'sign',
    'number',
    'punctuation',
    'description',
    'damage'
);

CREATE TYPE indicator_type AS ENUM (
    'none',
    'left',
    'right',
    'center'
);

CREATE TYPE sign_condition AS ENUM (
    'intact',
    'damaged',
    'lost',
    'inserted',
    'deleted',
    'erased'
);

CREATE TYPE pn_type AS ENUM (
    'none',
    'person', 
    'god',
    'place',   
    'water', 
    'field', 
    'temple', 
    'month',
    'object',
    'ethnicity',
    'festival'
);

CREATE TYPE sign_meaning AS (
    word_no integer,
    value_id integer,
    sign_id integer,
    indicator_type indicator_type,
    phonographic boolean,
    stem boolean,
    capitalized boolean
);

CREATE OR REPLACE FUNCTION condition_agg_sfunc (sign_condition, sign_condition)
    RETURNS sign_condition
    STABLE 
    STRICT 
    PARALLEL SAFE
    LANGUAGE sql 
BEGIN ATOMIC
    SELECT
        CASE 
            WHEN $1 = $2 THEN $1
            WHEN $1 = 'deleted' OR $1 = 'inserted' OR $2 = 'deleted' OR $2 = 'inserted' THEN null
            ELSE 'damaged' 
        END;
END;


CREATE AGGREGATE condition_agg (sign_condition) (
    SFUNC       = condition_agg_sfunc,
    COMBINEFUNC = condition_agg_sfunc,
    STYPE       = sign_condition,
    PARALLEL    = safe
);