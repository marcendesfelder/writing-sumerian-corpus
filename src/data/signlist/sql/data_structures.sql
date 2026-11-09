CREATE TYPE sign_variant_type AS ENUM (
    'default',
    'nondefault',
    'reduced',
    'augmented',
    'nonstandard'
);


CREATE TABLE glyphs (
    glyph_id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    glyph text NOT NULL UNIQUE,
    unicode text
);

CREATE TABLE glyph_synonyms (
    synonym text PRIMARY KEY,
    glyph_id integer NOT NULL REFERENCES glyphs (glyph_id) ON UPDATE CASCADE DEFERRABLE INITIALLY IMMEDIATE
);

CREATE TABLE graphemes (
    grapheme_id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    grapheme text NOT NULL UNIQUE,
    mzl_no integer
);

CREATE TABLE allographs (
    allograph_id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    grapheme_id integer NOT NULL REFERENCES graphemes (grapheme_id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
    glyph_id integer NOT NULL REFERENCES glyphs (glyph_id) ON UPDATE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
    variant_type sign_variant_type NOT NULL,
    specific boolean NOT NULL,
    UNIQUE (grapheme_id, glyph_id),
    CHECK (specific OR variant_type != 'default')
);

CREATE TABLE signs (
    sign_id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY
);

CREATE TABLE allomorphs (
    allomorph_id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    sign_id integer NOT NULL REFERENCES signs (sign_id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
    variant_type sign_variant_type NOT NULL,
    specific boolean NOT NULL,
    CHECK (specific OR variant_type != 'default')
);

CREATE TABLE allomorph_components (
    allomorph_id integer REFERENCES allomorphs (allomorph_id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
    pos integer,
    grapheme_id integer NOT NULL REFERENCES graphemes (grapheme_id) ON UPDATE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
    PRIMARY KEY (allomorph_id, pos)
);

CREATE TABLE sign_variants (
    sign_variant_id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    sign_id integer NOT NULL REFERENCES signs (sign_id) DEFERRABLE INITIALLY DEFERRED,
    allomorph_id integer NOT NULL REFERENCES allomorphs (allomorph_id) DEFERRABLE INITIALLY DEFERRED,
    allograph_ids integer[] NOT NULL,
    variant_type sign_variant_type NOT NULL,
    specific boolean NOT NULL,
    UNIQUE (allomorph_id, allograph_ids)
);

CREATE TABLE values (
    value_id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    sign_id integer NOT NULL REFERENCES signs (sign_id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
    main_variant_id integer NOT NULL,
    phonographic boolean
);

CREATE TABLE value_variants (
    value_variant_id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    value_id integer NOT NULL REFERENCES values (value_id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
    value text NOT NULL,
    UNIQUE (value_variant_id, value_id),  -- pointless, but required for foreign key on values
    UNIQUE (value_variant_id, value)
);

CREATE TABLE glyph_values (
    value text PRIMARY KEY,
    value_id integer NOT NULL REFERENCES values (value_id) ON UPDATE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
    glyph_ids integer[] NOT NULL
);

ALTER TABLE values ADD FOREIGN KEY (value_id, main_variant_id) REFERENCES value_variants (value_id, value_variant_id) DEFERRABLE INITIALLY DEFERRED;

CREATE UNIQUE INDEX ON allomorphs (sign_id) 
WHERE 
    variant_type = 'default';

CREATE UNIQUE INDEX ON allographs (grapheme_id) 
WHERE 
    variant_type = 'default';

CREATE UNIQUE INDEX ON allographs (glyph_id)
WHERE
    specific;

CREATE UNIQUE INDEX ON sign_variants(allograph_ids) 
WHERE 
    specific;

CREATE UNIQUE INDEX ON sign_variants(allograph_ids)
WHERE
    variant_type = 'default';

CREATE UNIQUE INDEX ON sign_variants (sign_id)
WHERE
    variant_type = 'default';

CREATE UNIQUE INDEX ON value_variants (value)
WHERE
    value NOT LIKE '%x';

CREATE INDEX value_index ON value_variants (value);
CREATE INDEX sign_variants_sign_id_ix ON sign_variants (sign_id);

CREATE FUNCTION check_sign_default_variant ()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $BODY$
DECLARE
  v_sign_id integer := CASE WHEN TG_TABLE_NAME = 'signs' THEN NEW.sign_id ELSE OLD.sign_id END;
BEGIN
  IF EXISTS (SELECT FROM @extschema@.signs WHERE sign_id = v_sign_id)
    AND NOT EXISTS (SELECT FROM @extschema@.sign_variants WHERE sign_id = v_sign_id AND variant_type = 'default') THEN
    RAISE EXCEPTION 'sign % has no default variant', v_sign_id;
  END IF;
  RETURN NULL;
END;
$BODY$;

CREATE CONSTRAINT TRIGGER signs_default_variant_check
  AFTER INSERT ON signs
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION check_sign_default_variant ();

CREATE CONSTRAINT TRIGGER sign_variants_default_variant_check
  AFTER UPDATE OF sign_id, variant_type OR DELETE ON sign_variants
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION check_sign_default_variant ();

SELECT pg_catalog.pg_extension_config_dump('@extschema@.signs', '');
SELECT pg_catalog.pg_extension_config_dump('@extschema@.allomorphs', '');
SELECT pg_catalog.pg_extension_config_dump('@extschema@.allomorph_components', '');
SELECT pg_catalog.pg_extension_config_dump('@extschema@.glyphs', '');
SELECT pg_catalog.pg_extension_config_dump('@extschema@.glyph_synonyms', '');
SELECT pg_catalog.pg_extension_config_dump('@extschema@.glyph_values', '');
SELECT pg_catalog.pg_extension_config_dump('@extschema@.graphemes', '');
SELECT pg_catalog.pg_extension_config_dump('@extschema@.allographs', '');
SELECT pg_catalog.pg_extension_config_dump('@extschema@.values', '');
SELECT pg_catalog.pg_extension_config_dump('@extschema@.value_variants', '');
SELECT pg_catalog.pg_extension_config_dump('@extschema@.sign_variants', '');
SELECT pg_catalog.pg_extension_config_dump(pg_get_serial_sequence('@extschema@.signs', 'sign_id'), '');
SELECT pg_catalog.pg_extension_config_dump(pg_get_serial_sequence('@extschema@.allomorphs', 'allomorph_id'), '');
SELECT pg_catalog.pg_extension_config_dump(pg_get_serial_sequence('@extschema@.glyphs', 'glyph_id'), '');
SELECT pg_catalog.pg_extension_config_dump(pg_get_serial_sequence('@extschema@.graphemes', 'grapheme_id'), '');
SELECT pg_catalog.pg_extension_config_dump(pg_get_serial_sequence('@extschema@.allographs', 'allograph_id'), '');
SELECT pg_catalog.pg_extension_config_dump(pg_get_serial_sequence('@extschema@.values', 'value_id'), '');
SELECT pg_catalog.pg_extension_config_dump(pg_get_serial_sequence('@extschema@.value_variants', 'value_variant_id'), '');
SELECT pg_catalog.pg_extension_config_dump(pg_get_serial_sequence('@extschema@.sign_variants', 'sign_variant_id'), '');