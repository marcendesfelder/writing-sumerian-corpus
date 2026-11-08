#include "cuneiform_serialize.h"
#include "../../print_core/src/cuneiform_print_core.h"

#include <fmgr.h>
#include <utils/builtins.h>
#include <access/htup_details.h>
#include <catalog/pg_type.h>
#include <utils/array.h>
#include <tcop/pquery.h>

PG_MODULE_MAGIC;

static cun_set_enums_t set_enums;
static cun_copy_n_t copy_n;
static cun_copy_t copy;
static cun_compare_next_t compare_next;
static cun_capitalize_t capitalize;
static cun_is_unknown_reading_t is_unknown_reading;

static cun_enum_type_t enum_type;
static cun_enum_condition_t enum_condition;
static cun_enum_indicator_type_t enum_indicator_type;
static cun_enum_pn_t enum_pn;
static cun_enum_language_t enum_language;

static cun_init_state_t init_state;
static cun_add_line_t add_line;
static cun_get_cursor_t get_cursor;
static cun_get_changes_t get_changes;
static cun_copy_print_result_t copy_print_result;

static cun_determine_connector_t determine_connector;
static cun_opened_condition_start_t opened_condition_start;
static cun_opened_condition_end_t opened_condition_end;
static cun_copy_compound_comment_t copy_compound_comment;

void _PG_init(void)
{
    set_enums = (cun_set_enums_t)load_external_function("cuneiform_print_core", "cun_set_enums", true, NULL);
    copy_n = (cun_copy_n_t)load_external_function("cuneiform_print_core", "cun_copy_n", true, NULL);
    copy = (cun_copy_t)load_external_function("cuneiform_print_core", "cun_copy", true, NULL);
    compare_next = (cun_compare_next_t)load_external_function("cuneiform_print_core", "cun_compare_next", true, NULL);
    capitalize = (cun_capitalize_t)load_external_function("cuneiform_print_core", "cun_capitalize", true, NULL);
    is_unknown_reading = (cun_is_unknown_reading_t)load_external_function("cuneiform_print_core", "cun_is_unknown_reading", true, NULL);

    enum_type = (cun_enum_type_t)load_external_function("cuneiform_print_core", "cun_enum_type", true, NULL);
    enum_condition = (cun_enum_condition_t)load_external_function("cuneiform_print_core", "cun_enum_condition", true, NULL);
    enum_indicator_type = (cun_enum_indicator_type_t)load_external_function("cuneiform_print_core", "cun_enum_indicator_type", true, NULL);
    enum_pn = (cun_enum_pn_t)load_external_function("cuneiform_print_core", "cun_enum_pn", true, NULL);
    enum_language = (cun_enum_language_t)load_external_function("cuneiform_print_core", "cun_enum_language", true, NULL);

    init_state = (cun_init_state_t)load_external_function("cuneiform_print_core", "cun_init_state", true, NULL);
    add_line = (cun_add_line_t)load_external_function("cuneiform_print_core", "cun_add_line", true, NULL);
    get_cursor = (cun_get_cursor_t)load_external_function("cuneiform_print_core", "cun_get_cursor", true, NULL);
    get_changes = (cun_get_changes_t)load_external_function("cuneiform_print_core", "cun_get_changes", true, NULL);
    copy_print_result = (cun_copy_print_result_t)load_external_function("cuneiform_print_core", "cun_copy_print_result", true, NULL);
    determine_connector = (cun_determine_connector_t)load_external_function("cuneiform_print_core", "cun_determine_connector", true, NULL);
    opened_condition_start = (cun_opened_condition_start_t)load_external_function("cuneiform_print_core", "cun_opened_condition_start", true, NULL);
    opened_condition_end = (cun_opened_condition_end_t)load_external_function("cuneiform_print_core", "cun_opened_condition_end", true, NULL);
    copy_compound_comment = (cun_copy_compound_comment_t)load_external_function("cuneiform_print_core", "cun_copy_compound_comment", true, NULL);
};


#define EXP_LINE_LEN           256
#define MAX_EXTRA_LINE_LEN     128     // upper bound for the code written around one sign

#define ARG_VALUE                1
#define ARG_SIGN_NO              2
#define ARG_WORD_NO              3
#define ARG_COMPOUND_NO          4
#define ARG_SECTION_NO           5
#define ARG_LINE_NO              6
#define ARG_TYPE                 7
#define ARG_INDICATOR_TYPE       8
#define ARG_PHONOGRAPHIC         9      
#define ARG_STEM                10
#define ARG_CONDITION           11
#define ARG_LANGUAGE            12
#define ARG_INVERTED            13
#define ARG_NEWLINE             14
#define ARG_LIGATURE            15
#define ARG_CRITICS             16
#define ARG_COMMENT             17
#define ARG_CAPITALIZED         18
#define ARG_PN_TYPE             19
#define ARG_SECTION             20
#define ARG_COMPOUND_COMMENT    21



static char* open_code(char* s, const State* s1, State* s2)
{
    if(s1 == NULL || s1->language != s2->language || s1->language_null != s2->language_null)
    {
        if(s2->language_null)
        {
            if(s1)
                s = copy(s, "%u ");
        }
        else if(s2->language == enum_language()->akkadian)
            s = copy(s, "%a ");
        else if(s2->language == enum_language()->eblaite)
            s = copy(s, "%e ");
        else if(s2->language == enum_language()->hittite)
            s = copy(s, "%h ");
        else if(s2->language == enum_language()->hurrian)
            s = copy(s, "%hu ");
        else if(s2->language == enum_language()->emesal)
            s = copy(s, "%es ");
        else if(s2->language == enum_language()->amorite)
            s = copy(s, "%am ");
        else if(s2->language == enum_language()->sumerian)
            s = copy(s, "%s ");
        else if(s2->language == enum_language()->other)
            s = copy(s, "%o ");
    }
    if(!s2->pn_type_null && (s1 == NULL || s1->pn_type != s2->pn_type || s1->pn_type_null || s1->compound_no != s2->compound_no))
    {
        if(s2->pn_type == enum_pn()->person)
            s = copy(s, "%person ");
        else if(s2->pn_type == enum_pn()->god)
            s = copy(s, "%god ");
        else if(s2->pn_type == enum_pn()->place)
            s = copy(s, "%place ");
        else if(s2->pn_type == enum_pn()->water)
            s = copy(s, "%water ");
        else if(s2->pn_type == enum_pn()->field)
            s = copy(s, "%field ");
        else if(s2->pn_type == enum_pn()->temple)
            s = copy(s, "%temple ");
        else if(s2->pn_type == enum_pn()->month)
            s = copy(s, "%month ");
        else if(s2->pn_type == enum_pn()->object)
            s = copy(s, "%object ");
        else if(s2->pn_type == enum_pn()->ethnicity)
            s = copy(s, "%ethnicity ");
        else if(s2->pn_type == enum_pn()->festival)
            s = copy(s, "%festival ");
    }

    if(!s2->stem_null && (s1 == NULL || (s1->stem_null && s1->compound_no != s2->compound_no)))
        s = copy(s, "%st+ ");
    else if(s2->stem_null && s1 != NULL && !s1->stem_null && s1->compound_no != s2->compound_no)
        s = copy(s, "%st- ");

    if(s1 != NULL && s1->word_no == s2->word_no && !s1->stem && s2->stem && !s1->stem_null && !s2->stem_null)
        *s++ = ';';

    if(!s2->phonographic_null && !s2->phonographic && s2->indicator_type == enum_indicator_type()->none && (s1 == NULL || s1->phonographic_null || s1->phonographic || s1->indicator_type != enum_indicator_type()->none || s1->line_no != s2->line_no))
        *s++ = '_';

    if(s1 == NULL || s1->condition != s2->condition || s1->line_no != s2->line_no)
    {
        if(s2->condition == enum_condition()->lost)
            s = copy(s, "[");
        else if(s2->condition == enum_condition()->damaged)
            s = copy(s, "⸢");
        else if(s2->condition == enum_condition()->inserted)
            s = copy(s, "‹");
        else if(s2->condition == enum_condition()->deleted)
            s = copy(s, "«");
    }

    if(s2->capitalize) {
        *s++ = '&';
        s2->capitalize = false;
    }

    if(s2->indicator_type != enum_indicator_type()->none && (s1 == NULL || s1->indicator_type != s2->indicator_type || s1->phonographic != s2->phonographic || s1->phonographic_null || s1->line_no != s2->line_no))
    {
        if(s2->phonographic)
            *s++ = '<';
        else 
            *s++ = '{';
    }

    return s;
}


static char* close_code(char* s, const State* s1, const State* s2)
{
    if(s1->indicator_type != enum_indicator_type()->none && (s2 == NULL || s1->indicator_type != s2->indicator_type || s1->phonographic != s2->phonographic || s2->phonographic_null || s1->line_no != s2->line_no))
    {
        if(s1->phonographic)
            *s++ = '>';
        else 
            *s++ = '}';
    }

    if((s2 == NULL || s1->compound_no != s2->compound_no) && s1->compound_comment_len)
    {
        *s++ = ' ';
        *s++ = '(';
        s = copy_n(s, s1->compound_comment, s1->compound_comment_len);
        *s++ = ')';
    }

    if(s2 == NULL || s1->condition != s2->condition || s1->line_no != s2->line_no)
    {
        if(s1->condition == enum_condition()->lost)
            s = copy(s, "]");
        else if(s1->condition == enum_condition()->damaged)
            s = copy(s, "⸣");
        else if(s1->condition == enum_condition()->inserted)
            s = copy(s, "›");
        else if(s1->condition == enum_condition()->deleted)
            s = copy(s, "»");
    }

    if(!s1->phonographic_null && !s1->phonographic && s1->indicator_type == enum_indicator_type()->none && (s2 == NULL || s2->phonographic_null || s2->phonographic || s2->indicator_type != enum_indicator_type()->none || s1->line_no != s2->line_no))
        *s++ = '_';

    if(s2 != NULL && s1->stem && !s2->stem && !s1->stem_null && !s2->stem_null && s1->word_no == s2->word_no)
        *s++ = ';';
        
    return s;
}


static char* write_simple_connector_code(char* s, int connector)
{
    if(connector == SEP_INDICATOR_L || connector == SEP_DOT || connector == SEP_NUMBER)
        *s++ = '.';
    else if(connector == SEP_INDICATOR_P || connector == SEP_DASH)
        *s++ = '-';
    else if(connector == SEP_WORD)
        s = copy(s, "--");
    else if(connector == SEP_COMPOUND)
        *s++ = ' ';
    return s;
}


static char* write_modified_connector_code(char* s, const Connector c)
{   
    if(c.ellipsis)
    {
        s = write_simple_connector_code(s, c.connector);
        s = copy(s, "…");
        s = write_simple_connector_code(s, c.connector);
    }
    else if(c.modifier == SEP_EXT_LIGATURE)
    {
        if(c.connector == SEP_WORD)
            s = write_simple_connector_code(s, c.connector);
        *s++ = '+';
    }
    else if(c.modifier == SEP_EXT_LINEBREAK)
    {
        if(c.connector == SEP_INDICATOR_L || c.connector == SEP_INDICATOR_P || c.connector == SEP_INDICATOR_M || c.connector == SEP_INDICATOR_0)
            *s++ = '~';
        else if(c.connector != SEP_COMPOUND)
            s = write_simple_connector_code(s, c.connector);
    }
    else if(c.modifier == SEP_EXT_INVERSION)
    {
        if(c.connector == SEP_WORD)
            s = copy(s, "--:");
        else if(c.connector == SEP_COMPOUND)
            s = copy(s, " : ");
        else
            *s++ = ':';
    }
    else if(c.modifier == SEP_EXT_NEWLINE)
    {
        s = write_simple_connector_code(s, c.connector);
        *s++ = '/';
        if(c.connector == SEP_COMPOUND)
            *s++ = ' ';
    }
    else
        s = write_simple_connector_code(s, c.connector);

    return s;
}


Datum cuneiform_cun_agg_sfunc(PG_FUNCTION_ARGS)
{
    MemoryContext aggcontext;
    State* state;
    State state_old;

    char *s;
    bool no_condition;
    Oid inner_condition;

    const bool first_call = PG_ARGISNULL(0);

    const text* value = PG_ARGISNULL(ARG_VALUE) ? NULL : PG_GETARG_TEXT_PP(ARG_VALUE);

    const bool inverted = PG_GETARG_BOOL(ARG_INVERTED);
    const bool newline = PG_GETARG_BOOL(ARG_NEWLINE);
    const bool ligature = PG_GETARG_BOOL(ARG_LIGATURE);

    const text* critics = PG_ARGISNULL(ARG_CRITICS) ? NULL : PG_GETARG_TEXT_PP(ARG_CRITICS);
    const text* comment = PG_ARGISNULL(ARG_COMMENT) ? NULL : PG_GETARG_TEXT_PP(ARG_COMMENT);
    const text* compound_comment = PG_ARGISNULL(ARG_COMPOUND_COMMENT) ? NULL : PG_GETARG_TEXT_PP(ARG_COMPOUND_COMMENT);

    const text* section = PG_ARGISNULL(ARG_SECTION) ? NULL : PG_GETARG_TEXT_PP(ARG_SECTION);

    const int32 value_size = value ? VARSIZE_ANY_EXHDR(value) : 0;
    const int32 critics_size = critics ? VARSIZE_ANY_EXHDR(critics) : 0;
    const int32 comment_size = comment ? VARSIZE_ANY_EXHDR(comment) : 0;
    const int32 section_size = section ? VARSIZE_ANY_EXHDR(section) : 0;
    const int32 size = value_size + critics_size + comment_size + section_size;

    if (!AggCheckCallContext(fcinfo, &aggcontext))
    {
        /* cannot be called directly because of internal-type argument */
        elog(ERROR, "cuneiform_cun_agg_sfunc called in non-aggregate context");
    }

    set_enums();

    if(first_call)
        state = init_state(EXP_LINE_LEN, aggcontext);
    else
        state = (State*) PG_GETARG_POINTER(0);

    state_old = *state;

    state->sign_no = PG_GETARG_INT32(ARG_SIGN_NO);
    state->word_no = PG_GETARG_INT32(ARG_WORD_NO);
    state->compound_no = PG_GETARG_INT32(ARG_COMPOUND_NO);
    state->line_no = PG_GETARG_INT32(ARG_LINE_NO);
    state->section_no = PG_GETARG_INT32(ARG_SECTION_NO);
    state->section_null = PG_ARGISNULL(ARG_SECTION_NO);
    if(!section && !state->section_null)
        elog(ERROR, "section name is NULL for section no %d", state->section_no);
    state->type = PG_GETARG_OID(ARG_TYPE);
    state->phonographic = PG_GETARG_BOOL(ARG_PHONOGRAPHIC);
    state->phonographic_null = PG_ARGISNULL(ARG_PHONOGRAPHIC);
    state->indicator_type = PG_GETARG_OID(ARG_INDICATOR_TYPE);
    state->stem = PG_GETARG_BOOL(ARG_STEM);
    state->stem_null = PG_ARGISNULL(ARG_STEM);
    state->condition = PG_GETARG_OID(ARG_CONDITION);
    state->language = PG_GETARG_OID(ARG_LANGUAGE);
    state->language_null = PG_ARGISNULL(ARG_LANGUAGE);
    state->pn_type = PG_GETARG_OID(ARG_PN_TYPE);
    state->pn_type_null = PG_ARGISNULL(ARG_PN_TYPE);
    state->capitalize = state_old.capitalize || (PG_GETARG_BOOL(ARG_CAPITALIZED) && state_old.word_no != state->word_no);
    state->unknown_reading = state->type == enum_type()->sign && is_unknown_reading(value ? (char*)VARDATA_ANY(value) : NULL, value_size);

    s = get_cursor(size + state_old.compound_comment_len + MAX_EXTRA_LINE_LEN, state);

    inner_condition = opened_condition_start(value ? (char*)VARDATA_ANY(value) : NULL, value_size, &no_condition);
    if(!no_condition)
        state->condition = inner_condition;

    if(!first_call)
    { 
        s = close_code(s, &state_old, state);
        s = write_modified_connector_code(s, determine_connector(&state_old, state, inverted, newline, ligature));        

        if(state_old.line_no != state->line_no)    // Newline
        {
            state->line_lens[state->line_count-1] = s - state->lines[state->line_count-1];
            s = add_line(size + EXP_LINE_LEN, state, aggcontext);
        }
    }    

    if(!state->section_null && (first_call || state_old.section_null || state_old.section_no != state->section_no))
    {
        s = copy(s, "%sec=");
        s = copy_n(s, VARDATA_ANY(section), section_size);
        *s++ = ' ';
    }
    else if(state->section_null && !first_call && !state_old.section_null)
    {
        s = copy(s, "%sec ");
    }
    
    s = open_code(s, first_call ? NULL : &state_old, state);

    if(value)
    {
        if(state->type == enum_type()->description)
            *s++ = '"';
        s = copy_n(s, VARDATA_ANY(value), value_size);
        if(state->type == enum_type()->description)
            *s++ = '"';
    }

    if(critics_size)
        s = copy_n(s, VARDATA_ANY(critics), critics_size);

    if(comment_size)
    {
        *s++ = '(';
        s = copy_n(s, VARDATA_ANY(comment), comment_size);
        *s++ = ')';
    }

    copy_compound_comment(compound_comment, state);

    if(!no_condition)
        state->condition = opened_condition_end(value ? (char*)VARDATA_ANY(value) : NULL, value_size);

    state->line_lens[state->line_count-1] = s - state->lines[state->line_count-1];

    PG_RETURN_POINTER(state);
}


Datum cuneiform_cun_agg_finalfunc(PG_FUNCTION_ARGS)
{
    const State* state;
    Datum* lines;
    text* string;
    char* s;

    Assert(AggCheckCallContext(fcinfo, NULL));

    state = (State*) PG_GETARG_POINTER(0);
    
    lines = copy_print_result(state, state->compound_comment_len + MAX_EXTRA_LINE_LEN);

    string = DatumGetTextPP(lines[state->line_count-1]);
    s = VARDATA(string) + state->line_lens[state->line_count-1];

    s = close_code(s, state, NULL);

    SET_VARSIZE(string, s-VARDATA(string)+VARHDRSZ);
    PG_RETURN_ARRAYTYPE_P(construct_array(lines, state->line_count, TEXTOID, -1, false, 'i'));
}