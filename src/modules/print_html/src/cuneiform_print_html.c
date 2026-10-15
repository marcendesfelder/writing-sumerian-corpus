#include "cuneiform_print_html.h"

#include "../../print_core/src/cuneiform_print_core.h"

#include <math.h>

#include <fmgr.h>
#include <utils/builtins.h>
#include <access/htup_details.h>
#include <catalog/pg_type.h>
#include <utils/array.h>
#include <utils/arrayaccess.h>
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


#define EXP_LINE_LEN          1000
#define MAX_EXTRA_LINE_LEN     200

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
#define ARG_HIGHLIGHT           22
#define ARG_EXTRA               23


typedef struct HTMLState {
    State *state;
    int *extra;
    bool *extra_null;
    int *extra_old;
    bool *extra_null_old;
    int len_extra;
} htmlState;


static htmlState *init_htmlstate(const int len_extra, MemoryContext memcontext)
{
    htmlState *htmlstate = (htmlState *) MemoryContextAlloc(memcontext, sizeof(htmlState));
    htmlstate->state = init_state(EXP_LINE_LEN, memcontext);
    htmlstate->extra = (int *) MemoryContextAlloc(memcontext, len_extra * sizeof(int));
    htmlstate->extra_null = (bool *) MemoryContextAlloc(memcontext, len_extra * sizeof(bool));
    htmlstate->extra_old = (int *) MemoryContextAlloc(memcontext, len_extra * sizeof(int));
    htmlstate->extra_null_old = (bool *) MemoryContextAlloc(memcontext, len_extra * sizeof(bool));
    htmlstate->len_extra = len_extra;
    return htmlstate;
}

static void load_extra(const AnyArrayType *extra, htmlState *state)
{
    array_iter it;
    int *const extra_swap = state->extra;
    bool *const extra_null_swap = state->extra_null;
    state->extra = state->extra_old;
    state->extra_null = state->extra_null_old;
    state->extra_old = extra_swap;
    state->extra_null_old = extra_null_swap;
    array_iter_setup(&it, (AnyArrayType *) extra);
    for(int i = 0; i < state->len_extra; ++i)
    {
        const Datum d = array_iter_next(&it, &(state->extra_null[i]), i, 4, true, TYPALIGN_INT);
        state->extra[i] = DatumGetInt32(d);
    }
}

static int get_extra_changes(const htmlState *state, const bool newline)
{
    int changes = 0;
    for(int i = 0; i < state->len_extra; ++i)
        if(newline || state->extra_null[i] != state->extra_null_old[i] || (!state->extra_null[i] && state->extra[i] != state->extra_old[i]))
            changes += 1 << i;
    return changes;
}


static char* open_html(char* s, int changes, const State* state, const int *extra, const bool *extra_null, const int len_extra)
{
    for(int i = 0; i < len_extra; ++i)
        if(changes >= LANGUAGE * (2 << i) && !extra_null[i])
            s += sprintf(s, "<span class='extra%d-%d'>", i, extra[i]);

    if(changes >= LANGUAGE && !state->language_null)
    {
        if(state->language == enum_language()->akkadian)
            s = copy(s, "<span class='akkadian'>");
        else if(state->language == enum_language()->hittite)
            s = copy(s, "<span class='hittite'>");
        else if(state->language == enum_language()->eblaite)
            s = copy(s, "<span class='eblaite'>");
        else
            s = copy(s, "<span class='otherlanguage'>");
    }
    if(changes >= STEM && state->stem && !state->stem_null)
        s = copy(s, "<span class='stem'>");
    if(changes >= HIGHLIGHT && state->highlight)
        s = copy(s, "<span class='highlight'>");
    if(changes >= PHONOGRAPHIC && !state->phonographic_null)
    {
        if(state->phonographic)
            s = copy(s, "<span class='phonographic'>");
        else
            s = copy(s, "<span class='logographic'>");
    }
    if(changes >= TYPE && (state->type != enum_type()->sign || state->unknown_reading)  && state->type != enum_type()->punctuation)
    {
        if(state->type == enum_type()->number)
            s = copy(s, "<span class='number'>");
        else if(state->type == enum_type()->description)
            s = copy(s, "<span class='description'>");
        else if(state->type == enum_type()->damage)
            s = copy(s, "<span class='damage'>");
        else if(state->unknown_reading)
            s = copy(s, "<span class='unknown_reading'>");
    }
    if(changes >= INDICATOR && state->indicator_type != enum_indicator_type()->none)
        s = copy(s, "<span class='indicator'>");
    if(changes >= CONDITION && state->condition != enum_condition()->intact)
    {
        if(state->condition == enum_condition()->lost)
            s = copy(s, "<span class='lost'>");
        else if(state->condition == enum_condition()->damaged)
            s = copy(s, "<span class='damaged'>");
        else if(state->condition == enum_condition()->inserted)
            s = copy(s, "<span class='inserted'>");
        else if(state->condition == enum_condition()->deleted)
            s = copy(s, "<span class='deleted'>");
        else if(state->condition == enum_condition()->erased)
            s = copy(s, "<span class='erased'>");
    }
    return s;
}


static char* close_html(char* s, int changes, const State* state, const int *extra, const bool *extra_null, const int len_extra)
{
    if(changes >= CONDITION && state->condition != enum_condition()->intact)
        s = copy(s, "</span>");
    if(changes >= INDICATOR && state->indicator_type != enum_indicator_type()->none)
        s = copy(s, "</span>");
    if(changes >= TYPE && (state->type != enum_type()->sign || state->unknown_reading) && state->type != enum_type()->punctuation)
        s = copy(s, "</span>");
    if(changes >= PHONOGRAPHIC && !state->phonographic_null)
        s = copy(s, "</span>");
    if(changes >= HIGHLIGHT && state->highlight)
        s = copy(s, "</span>");
    if(changes >= STEM && state->stem && !state->stem_null)
        s = copy(s, "</span>");
    if(changes >= LANGUAGE && !state->language_null)
        s = copy(s, "</span>");
    for(int i = 0; i < len_extra; ++i)
        if(changes >= LANGUAGE * (2 << i) && !extra_null[i])
            s = copy(s, "</span>");
    return s;
}


static char* open_condition_html(char* s, Oid condition)
{
    if(condition == enum_condition()->lost)
        s = copy(s, "<span class='open-lost'></span>");
    else if(condition == enum_condition()->damaged)
        s = copy(s, "<span class='open-damaged'></span>");
    else if(condition == enum_condition()->inserted)
        s = copy(s, "<span class='open-inserted'></span>");
    else if(condition == enum_condition()->deleted)
        s = copy(s, "<span class='open-deleted'></span>");
    else if(condition == enum_condition()->erased)
        s = copy(s, "<span class='open-erased'></span>");
    return s;
}


static char* close_condition_html(char* s, Oid condition)
{
    if(condition == enum_condition()->lost)
        s = copy(s, "<span class='close-lost'></span>");
    else if(condition == enum_condition()->damaged)
        s = copy(s, "<span class='close-damaged'></span>");
    else if(condition == enum_condition()->inserted)
        s = copy(s, "<span class='close-inserted'></span>");
    else if(condition == enum_condition()->deleted)
        s = copy(s, "<span class='close-deleted'></span>");
    else if(condition == enum_condition()->erased)
        s = copy(s, "<span class='close-erased'></span>");
    return s;
}


static char* write_simple_connector_html(char* s, int connector)
{
    if(connector == SEP_INDICATOR_L || connector == SEP_DOT || connector == SEP_NUMBER)
        *s++ = '.';
    else if(connector == SEP_INDICATOR_M)
        s = copy(s, "<span class='indicator'>.</span>");
    else if(connector == SEP_INDICATOR_P || connector == SEP_DASH)
        *s++ = '-';
    else if(connector == SEP_WORD)
        s = copy(s, "–");
    else if(connector == SEP_COMPOUND)
        *s++ = ' ';
    return s;
}


static char* write_modified_connector_html(char* s, const Connector c)
{   
    if(c.ellipsis)
    {
        s = write_simple_connector_html(s, c.connector);
        s = copy(s, "…");
        s = write_simple_connector_html(s, c.connector);
    }
    else if(c.modifier == SEP_EXT_LIGATURE)
    {
        if(c.modifier == SEP_INDICATOR_M)
            s = copy(s, "<span class='indicator'>+</span>");
        else
            *s++ = '+';
    }
    else if(c.modifier == SEP_EXT_LINEBREAK || c.modifier == SEP_EXT_NEWLINE)
    {
        if(c.connector != SEP_COMPOUND && c.connector != SEP_INDICATOR_L && c.connector != SEP_INDICATOR_P && c.connector != SEP_INDICATOR_M && c.connector != SEP_INDICATOR_0)
            s = write_simple_connector_html(s, c.connector);
    }
    else if(c.modifier == SEP_EXT_INVERSION)
    {
        if(c.connector == SEP_WORD)
            s = copy(s, "—:");
        else if(c.connector == SEP_COMPOUND)
            s = copy(s, " : ");
        else if(c.modifier == SEP_INDICATOR_M)
            s = copy(s, "<span class='indicator'>:</span>");
        else
            *s++ = ':';
    }
    else
        s = write_simple_connector_html(s, c.connector);

    return s;
}


static size_t calculate_value_size_replacing_conditions_html(const char* s, size_t n)
{
    size_t size = 0;
    while(n-- != 0)
    {
        if(*s == ']')
            size += strlen("</span><span class='close-lost'></span>");
        else if(n+1 >= strlen("⸣") && !compare_next(s, "⸣"))
            size += strlen("</span><span class='close-damaged'></span>");
        else if(n+1 >= strlen("›") && !compare_next(s, "›"))
            size += strlen("</span><span class='close-inserted'></span>");
        else if(n+1 >= strlen("»") && !compare_next(s, "»"))
            size += strlen("</span><span class='close-deleted'></span>");
        else if(*s == '[') 
            size += strlen("<span class='open-lost'></span><span class='lost'>");
        else if(n+1 >= strlen("⸢") && !compare_next(s, "⸢"))
            size += strlen("<span class='close-damaged'><span class='damaged'>");
        else if(n+1 >= strlen("‹") && !compare_next(s, "‹"))
            size += strlen("<span class='close-inserted'><span class='inserted'>");
        else if(n+1 >= strlen("«") && !compare_next(s, "«"))
            size += strlen("<span class='close-deleted'><span class='deleted'>");
        else
            ++size;
    }
    return size;
}


static char* write_value_replacing_conditions_html(char* s, const char* v, size_t n)
{
    while(n-- != 0)
    {
        if(*s == ']')
            s = copy(s, "</span><span class='close-lost'></span>");
        else if(n+1 >= strlen("⸣") && !compare_next(s, "⸣"))
            s = copy(s, "</span><span class='close-damaged'></span>");
        else if(n+1 >= strlen("›") && !compare_next(s, "›"))
            s = copy(s, "</span><span class='close-inserted'></span>");
        else if(n+1 >= strlen("»") && !compare_next(s, "»"))
            s = copy(s, "</span><span class='close-deleted'></span>");
        else if(*s == '[') 
            s = copy(s, "<span class='open-lost'></span><span class='lost'>");
        else if(n+1 >= strlen("⸢") && !compare_next(s, "⸢"))
            s = copy(s, "<span class='close-damaged'><span class='damaged'>");
        else if(n+1 >= strlen("‹") && !compare_next(s, "‹"))
            s = copy(s, "<span class='close-inserted'><span class='inserted'>");
        else if(n+1 >= strlen("«") && !compare_next(s, "«"))
            s = copy(s, "<span class='close-deleted'><span class='deleted'>");
        else
            *s++ = *v;
        ++v;
    }
    return s;
}


Datum cuneiform_cun_agg_html_sfunc(PG_FUNCTION_ARGS)
{
    MemoryContext aggcontext;
    htmlState* htmlstate;
    State* state;
    State state_old;

    char *s;
    bool no_condition;
    Oid inner_condition;
    int changes = 0;

    const bool first_call = PG_ARGISNULL(0);

    const text* value = PG_ARGISNULL(ARG_VALUE) ? NULL : PG_GETARG_TEXT_PP(ARG_VALUE);

    const bool inverted = PG_GETARG_BOOL(ARG_INVERTED);
    const bool newline = PG_GETARG_BOOL(ARG_NEWLINE);
    const bool ligature = PG_GETARG_BOOL(ARG_LIGATURE);

    const text* critics = PG_ARGISNULL(ARG_CRITICS) ? NULL : PG_GETARG_TEXT_PP(ARG_CRITICS);
    const text* comment = PG_ARGISNULL(ARG_COMMENT) ? NULL : PG_GETARG_TEXT_PP(ARG_COMMENT);
    const text* compound_comment = PG_ARGISNULL(ARG_COMPOUND_COMMENT) ? NULL : PG_GETARG_TEXT_PP(ARG_COMPOUND_COMMENT);

    const text* section = PG_ARGISNULL(ARG_SECTION) ? NULL : PG_GETARG_TEXT_PP(ARG_SECTION);

    const AnyArrayType* extra = PG_GETARG_ANY_ARRAY_P(ARG_EXTRA);

    const int32 value_size = value ? VARSIZE_ANY_EXHDR(value) : 0;
    const int32 value_size_final = calculate_value_size_replacing_conditions_html(value ? VARDATA_ANY(value) : NULL, value_size);
    const int32 critics_size = critics ? VARSIZE_ANY_EXHDR(critics) : 0;
    const int32 comment_size = comment ? VARSIZE_ANY_EXHDR(comment) : 0;
    const int32 section_size = section ? VARSIZE_ANY_EXHDR(section) : 0;
    const int32 size = value_size_final + critics_size + comment_size + section_size;

    if (!AggCheckCallContext(fcinfo, &aggcontext))
    {
        /* cannot be called directly because of internal-type argument */
        elog(ERROR, "array_agg_transfn called in non-aggregate context");
    }

    set_enums();

    if(PG_ARGISNULL(0))
        htmlstate = init_htmlstate(ArrayGetNItems(AARR_NDIM(extra), AARR_DIMS(extra)), aggcontext);
    else
        htmlstate = (htmlState*) PG_GETARG_POINTER(0);

    state = htmlstate->state;
    state_old = *state;

    state->sign_no = PG_GETARG_INT32(ARG_SIGN_NO);
    state->word_no = PG_GETARG_INT32(ARG_WORD_NO);
    state->compound_no = PG_GETARG_INT32(ARG_COMPOUND_NO);
    state->line_no = PG_GETARG_INT32(ARG_LINE_NO);
    state->section_no = PG_GETARG_INT32(ARG_SECTION_NO);
    state->section_null = PG_ARGISNULL(ARG_SECTION_NO);
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
    state->highlight = PG_ARGISNULL(ARG_HIGHLIGHT) ? false : PG_GETARG_BOOL(ARG_HIGHLIGHT);
    state->capitalize = state_old.capitalize || (PG_GETARG_BOOL(ARG_CAPITALIZED) && state_old.word_no != state->word_no);
    state->unknown_reading = state->type == enum_type()->sign && is_unknown_reading(value ? (char*)VARDATA_ANY(value) : NULL, value_size);

    load_extra(extra, htmlstate);

    s = get_cursor(size + state_old.compound_comment_len + MAX_EXTRA_LINE_LEN, state);

    inner_condition = opened_condition_start(value ? (char*)VARDATA_ANY(value) : NULL, value_size, &no_condition);
    if(!no_condition)
        state->condition = inner_condition;

    if(!first_call)
    { 
        changes = get_changes(&state_old, state) + 2*LANGUAGE*get_extra_changes(htmlstate, state_old.line_no != state->line_no);

        if(state_old.compound_no != state->compound_no && state_old.compound_comment_len)  // Word comments
        {
            *s++ = ' ';
            s = copy(s, "<span class='word-comment'>");
            s = copy_n(s, state_old.compound_comment, state_old.compound_comment_len);
            s = copy(s, "</span>");
        }

        s = close_html(s, changes, &state_old, htmlstate->extra_old, htmlstate->extra_null_old, htmlstate->len_extra);
        if(state->condition != state_old.condition || state_old.line_no != state->line_no)
            s = close_condition_html(s,state_old.condition);
        s = write_modified_connector_html(s, determine_connector(&state_old, state, inverted, newline, ligature));
        
        if (state_old.line_no != state->line_no)    // Newline
        {
            state->line_lens[state->line_count-1] = s - state->lines[state->line_count-1];
            s = add_line(size + EXP_LINE_LEN, state, aggcontext);
        }
    }
    else
        changes = INT_MAX;   

    if(newline)   
        s = copy(s, "<br class='internal-linebreak'>");   

    if(first_call || state->condition != state_old.condition || state_old.line_no != state->line_no)
        s = open_condition_html(s, state->condition);
    s = open_html(s, changes, state, htmlstate->extra, htmlstate->extra_null, htmlstate->len_extra);

    if(value)
    {
        if(!compare_next(VARDATA_ANY(value), "||"))
            s = copy(s, "<span class='hspace'></span>");
        else if(!compare_next(VARDATA_ANY(value), "="))
            s = copy(s, "<span class='vspace'></span>");
        else if(!compare_next(VARDATA_ANY(value), "|"))
            s = copy(s, "<span class='hline'></span>");
        else if(!compare_next(VARDATA_ANY(value), "–"))
            s = copy(s, "<span class='vline'></span>");
        else
        {
            char* s_ = s;
            s = write_value_replacing_conditions_html(s, VARDATA_ANY(value), value_size);
            if(state->capitalize && state->indicator_type == enum_indicator_type()->none)
            {
                capitalize(s_);
                state->capitalize = false;
            }
        } 
    }

    if(critics_size)
    {
        s = copy(s, "<span class='critics'>");
        s = copy_n(s, VARDATA_ANY(critics), critics_size);
        s = copy(s, "</span>");
    }
    
    if(comment_size)
    {
        s = copy(s, "<span class='comment'>");
        s = copy_n(s, VARDATA_ANY(comment), comment_size);
        s = copy(s, "</span>");
    }

    copy_compound_comment(compound_comment, state);

    if(!no_condition)
        state->condition = opened_condition_end(value ? (char*)VARDATA_ANY(value) : NULL, value_size);

    state->line_lens[state->line_count-1] = s - state->lines[state->line_count-1];

    PG_RETURN_POINTER(htmlstate);
}

Datum cuneiform_cun_agg_html_finalfunc(PG_FUNCTION_ARGS)
{
    const htmlState* htmlstate;
    const State* state;
    Datum* lines;
    text* string;
    char* s;

    Assert(AggCheckCallContext(fcinfo, NULL));

    if(PG_ARGISNULL(0))
        PG_RETURN_NULL();

    htmlstate = (htmlState*) PG_GETARG_POINTER(0);
    state = htmlstate->state;
    
    lines = copy_print_result(state);

    string = DatumGetTextPP(lines[state->line_count-1]);
    s = VARDATA(string) + state->line_lens[state->line_count-1];

    if(state->compound_comment_len)  // Compound comments
    {
        *s++ = ' ';
        s = copy(s, "<span class='word-comment'>");
        s = copy_n(s, state->compound_comment, state->compound_comment_len);
        s = copy(s, "</span>");
    }

    s = close_html(s, INT_MAX, state, htmlstate->extra, htmlstate->extra_null, htmlstate->len_extra);
    s = close_condition_html(s, state->condition);
       
    SET_VARSIZE(string, s-VARDATA(string)+VARHDRSZ);
    PG_RETURN_ARRAYTYPE_P(construct_array(lines, state->line_count, TEXTOID, -1, false, 'i'));
}