CREATE TABLE logged_signs (
    transliteration_id integer,
    edit_no integer,
    log_no integer,
    old boolean,
    value_id integer REFERENCES @extschema:cuneiform_signlist@.values (value_id) DEFERRABLE INITIALLY IMMEDIATE,
    sign_variant_id integer REFERENCES @extschema:cuneiform_signlist@.sign_variants (sign_variant_id) DEFERRABLE INITIALLY IMMEDIATE,
    custom_value text,
    PRIMARY KEY (transliteration_id, edit_no, log_no, old),
    FOREIGN KEY (transliteration_id, edit_no, log_no) REFERENCES @extschema@.edit_log (transliteration_id, edit_no, log_no) ON DELETE CASCADE
);

CREATE VIEW logged_signs_view AS 
SELECT
    transliteration_id,
    edit_no,
    log_no,
    FALSE AS old,
    (val::@extschema:cuneiform_corpus@.corpus).value_id,
    (val::@extschema:cuneiform_corpus@.corpus).sign_variant_id,
    (val::@extschema:cuneiform_corpus@.corpus).custom_value
FROM
    @extschema@.edit_log
WHERE
    target = 'corpus'
    AND action IN ('insert', 'update')
UNION ALL
SELECT
    transliteration_id,
    edit_no,
    log_no,
    TRUE AS old,
    (val_old::@extschema:cuneiform_corpus@.corpus).value_id,
    (val_old::@extschema:cuneiform_corpus@.corpus).sign_variant_id,
    (val_old::@extschema:cuneiform_corpus@.corpus).custom_value
FROM
    @extschema@.edit_log
WHERE
    target = 'corpus'
    AND action IN ('delete', 'update');


CREATE OR REPLACE FUNCTION logged_signs_trigger_fun () 
  RETURNS trigger 
  VOLATILE
  LANGUAGE PLPGSQL
  AS
$BODY$
BEGIN
    DELETE FROM @extschema@.logged_signs 
    USING 
      new_table 
    WHERE 
      logged_signs.transliteration_id = new_table.transliteration_id 
      AND logged_signs.edit_no = new_table.edit_no
      AND logged_signs.log_no = new_table.log_no;
  INSERT INTO @extschema@.logged_signs 
    SELECT 
      logged_signs_view.* 
    FROM 
      @extschema@.logged_signs_view
      JOIN new_table USING (transliteration_id, edit_no, log_no);
  RETURN NULL;
END;
$BODY$;


CREATE OR REPLACE FUNCTION update_logged_signs_trigger_fun () 
  RETURNS trigger 
  VOLATILE
  LANGUAGE PLPGSQL
  AS
$BODY$
DECLARE

a @extschema:cuneiform_corpus@.corpus;

BEGIN
    IF NEW.old THEN
        SELECT 
            (val_old::@extschema:cuneiform_corpus@.corpus).*
        INTO a 
        FROM 
            @extschema@.edit_log
        WHERE
            transliteration_id = NEW.transliteration_id
            AND edit_no = NEW.edit_no
            AND log_no = NEW.log_no;

        UPDATE @extschema@.edit_log 
        SET val_old = ROW(a.transliteration_id, a.sign_no, a.line_no, a.word_no, NEW.value_id, NEW.sign_variant_id, NEW.custom_value, a.type, a.indicator_type, a.phonographic, a.stem, a.condition, a.crits, a.comment, a.newline, a.inverted, a.ligature)::text
        WHERE
            transliteration_id = NEW.transliteration_id
            AND edit_no = NEW.edit_no
            AND log_no = NEW.log_no;
    ELSE
        SELECT 
            (val::@extschema:cuneiform_corpus@.corpus ).*
        INTO a 
        FROM 
            @extschema@.edit_log
        WHERE
            transliteration_id = NEW.transliteration_id
            AND edit_no = NEW.edit_no
            AND log_no = NEW.log_no;

        UPDATE @extschema@.edit_log 
        SET val = ROW(a.transliteration_id, a.sign_no, a.line_no, a.word_no, NEW.value_id, NEW.sign_variant_id, NEW.custom_value, a.type, a.indicator_type, a.phonographic, a.stem, a.condition, a.crits, a.comment, a.newline, a.inverted, a.ligature)::text
        WHERE
            transliteration_id = NEW.transliteration_id
            AND edit_no = NEW.edit_no
            AND log_no = NEW.log_no;
    END IF;
    RETURN NULL;
END;
$BODY$;


CREATE TRIGGER logged_signs_insert_trigger
    AFTER INSERT ON @extschema@.edit_log 
    REFERENCING NEW TABLE AS new_table
    FOR EACH STATEMENT
    EXECUTE FUNCTION logged_signs_trigger_fun();
CREATE TRIGGER logged_signs_update_trigger
    AFTER UPDATE ON @extschema@.edit_log 
    REFERENCING NEW TABLE AS new_table
    FOR EACH STATEMENT
    EXECUTE FUNCTION logged_signs_trigger_fun();

CREATE TRIGGER update_logged_signs_trigger
    AFTER UPDATE ON logged_signs
    FOR EACH ROW
    EXECUTE FUNCTION update_logged_signs_trigger_fun();


INSERT INTO logged_signs SELECT * FROM logged_signs_view;