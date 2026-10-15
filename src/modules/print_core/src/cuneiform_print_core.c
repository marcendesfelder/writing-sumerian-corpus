#include "cuneiform_print_core.h"

#include <fmgr.h>
#include <executor/spi.h>

PG_MODULE_MAGIC;


static cunEnumType ENUM_TYPE;
static cunEnumIndicatorType ENUM_INDICATOR_TYPE;
static cunEnumLanguage ENUM_LANGUAGE;
static cunEnumCondition ENUM_CONDITION;
static cunEnumVariantType ENUM_VARIANT_TYPE;
static cunEnumPN ENUM_PN;

static bool enums_set = false;

void cun_set_enums()
{
    bool isnull;
    
    if(enums_set)
        return;

    SPI_connect();

    SPI_execute("SELECT extnamespace::regnamespace::text FROM pg_extension WHERE extname = 'cuneiform_sign_properties'", true, 1);
    if(SPI_tuptable != NULL && SPI_processed == 1)
    {
        const HeapTuple tuple = SPI_tuptable->vals[0];
        const TupleDesc tupdesc = SPI_tuptable->tupdesc;

        text *schema;
        char *query;
        char *s;

        schema = DatumGetTextPP(SPI_getbinval(tuple, tupdesc, 1, &isnull));
        query = palloc(25 + VARSIZE_ANY_EXHDR(schema));
        s = query;
        s = cun_copy(s, "SET search_path TO ");
        s = cun_copy_n(s, VARDATA_ANY(schema), VARSIZE_ANY_EXHDR(schema));
        *s = '\0';
        SPI_execute(query, false, 0);
    }    

    SPI_execute("SELECT 'sumerian'::language, 'akkadian'::language, 'hittite'::language, 'eblaite'::language, 'other'::language", true, 1);
    if(SPI_tuptable != NULL && SPI_processed == 1)
    {
        const HeapTuple tuple = SPI_tuptable->vals[0];
        const TupleDesc tupdesc = SPI_tuptable->tupdesc;
        ENUM_LANGUAGE.sumerian = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 1, &isnull));
        ENUM_LANGUAGE.akkadian = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 2, &isnull));
        ENUM_LANGUAGE.hittite = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 3, &isnull));
        ENUM_LANGUAGE.eblaite = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 4, &isnull));
        ENUM_LANGUAGE.other = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 5, &isnull));
    }
    SPI_execute("SELECT 'none'::indicator_type, 'left'::indicator_type, 'right'::indicator_type, 'center'::indicator_type", true, 1);
    if(SPI_tuptable != NULL && SPI_processed == 1)
    {
        const HeapTuple tuple = SPI_tuptable->vals[0];
        const TupleDesc tupdesc = SPI_tuptable->tupdesc;
        ENUM_INDICATOR_TYPE.none = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 1, &isnull));
        ENUM_INDICATOR_TYPE.left = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 2, &isnull));
        ENUM_INDICATOR_TYPE.right = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 3, &isnull));
        ENUM_INDICATOR_TYPE.center = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 4, &isnull));
    }
    SPI_execute("SELECT 'sign'::sign_type, 'number'::sign_type, 'punctuation'::sign_type,"
                "       'description'::sign_type, 'damage'::sign_type", true, 1);
    if(SPI_tuptable != NULL && SPI_processed == 1)
    {
        const HeapTuple tuple = SPI_tuptable->vals[0];
        const TupleDesc tupdesc = SPI_tuptable->tupdesc;
        ENUM_TYPE.sign = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 1, &isnull));
        ENUM_TYPE.number = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 2, &isnull));
        ENUM_TYPE.punctuation = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 3, &isnull));
        ENUM_TYPE.description = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 4, &isnull));
        ENUM_TYPE.damage = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 5, &isnull));
    }
    SPI_execute("SELECT 'intact'::sign_condition, 'damaged'::sign_condition, 'lost'::sign_condition,"
                "       'inserted'::sign_condition, 'deleted'::sign_condition, 'erased'::sign_condition", true, 1);
    if(SPI_tuptable != NULL && SPI_processed == 1)
    {
        const HeapTuple tuple = SPI_tuptable->vals[0];
        const TupleDesc tupdesc = SPI_tuptable->tupdesc;
        ENUM_CONDITION.intact = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 1, &isnull));
        ENUM_CONDITION.damaged = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 2, &isnull));
        ENUM_CONDITION.lost = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 3, &isnull));
        ENUM_CONDITION.inserted = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 4, &isnull));
        ENUM_CONDITION.deleted = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 5, &isnull));
        ENUM_CONDITION.erased = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 6, &isnull));
    }
    SPI_execute("SELECT 'person'::pn_type, 'god'::pn_type, 'place'::pn_type, 'water'::pn_type, 'field'::pn_type,"
                "       'temple'::pn_type, 'month'::pn_type, 'object'::pn_type, 'ethnicity'::pn_type", true, 1);
    if(SPI_tuptable != NULL && SPI_processed == 1)
    {
        const HeapTuple tuple = SPI_tuptable->vals[0];
        const TupleDesc tupdesc = SPI_tuptable->tupdesc;
        ENUM_PN.person = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 1, &isnull));
        ENUM_PN.god = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 2, &isnull));
        ENUM_PN.place = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 3, &isnull));
        ENUM_PN.water = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 4, &isnull));
        ENUM_PN.field = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 5, &isnull));
        ENUM_PN.temple = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 6, &isnull));
        ENUM_PN.month = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 7, &isnull));
        ENUM_PN.object = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 8, &isnull));
        ENUM_PN.ethnicity = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 9, &isnull));
    }


    SPI_execute("SELECT extnamespace::regnamespace::text FROM pg_extension WHERE extname = 'cuneiform_signlist'", true, 1);
    if(SPI_tuptable != NULL && SPI_processed == 1)
    {
        const HeapTuple tuple = SPI_tuptable->vals[0];
        const TupleDesc tupdesc = SPI_tuptable->tupdesc;

        text *schema;
        char *query;
        char *s;

        schema = DatumGetTextPP(SPI_getbinval(tuple, tupdesc, 1, &isnull));
        query = palloc(25 + VARSIZE_ANY_EXHDR(schema));
        s = query;
        s = cun_copy(s, "SET search_path TO ");
        s = cun_copy_n(s, VARDATA_ANY(schema), VARSIZE_ANY_EXHDR(schema));
        *s = '\0';
        SPI_execute(query, false, 0);
    }

    SPI_execute("SELECT 'default'::sign_variant_type, 'nondefault'::sign_variant_type, 'reduced'::sign_variant_type,"
                "       'augmented'::sign_variant_type, 'nonstandard'::sign_variant_type", true, 1);
    if(SPI_tuptable != NULL && SPI_processed == 1)
    {
        const HeapTuple tuple = SPI_tuptable->vals[0];
        const TupleDesc tupdesc = SPI_tuptable->tupdesc;
        ENUM_VARIANT_TYPE.default_variant = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 1, &isnull));
        ENUM_VARIANT_TYPE.nondefault = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 2, &isnull));
        ENUM_VARIANT_TYPE.reduced = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 3, &isnull));
        ENUM_VARIANT_TYPE.augmented = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 4, &isnull));
        ENUM_VARIANT_TYPE.nonstandard = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 5, &isnull));
    }

    SPI_execute("SET search_path TO public", false, 0);
    
    SPI_finish();

    enums_set = true;
}

cunEnumType *cun_enum_type()
{
    return &ENUM_TYPE;
}
cunEnumIndicatorType *cun_enum_indicator_type()
{
    return &ENUM_INDICATOR_TYPE;
}
cunEnumLanguage *cun_enum_language()
{
    return &ENUM_LANGUAGE;
}
cunEnumCondition *cun_enum_condition()
{
    return &ENUM_CONDITION;
}
cunEnumVariantType *cun_enum_variant_type()
{
    return &ENUM_VARIANT_TYPE;
}
cunEnumPN *cun_enum_pn()
{
    return &ENUM_PN;
}


char* cun_copy_n(char* s1, const char* s2, size_t n)
{
    while(n-- != 0)
        *s1++ = *s2++;
    return s1;
}

char* cun_copy(char* s1, const char* s2)
{
    while(*s2 != '\0')
        *s1++ = *s2++;
    return s1;
}

int cun_compare_next(const char* s1, const char* s2)
{
    while(*s2 != '\0')
    {
        if(*s1 < *s2)
            return -1;
        if(*s1++ > *s2++)
            return 1;
    }
    return 0;
}

void cun_capitalize(char* s)
{
    if(*s & (1 << 8))
    {
        if(!cun_compare_next(s, "’"))
            cun_capitalize(s+strlen("’"));
        else if(!cun_compare_next(s, "ḫ"))
            cun_copy(s,"Ḫ");
        else if(!cun_compare_next(s, "š"))
            cun_copy(s,"Š");
        else if(!cun_compare_next(s, "ĝ"))
            cun_copy(s,"Ĝ");
        else if(!cun_compare_next(s, "ř"))
            cun_copy(s,"Ř");
        else if(!cun_compare_next(s, "ṣ"))
            cun_copy(s,"Ṣ");
        else if(!cun_compare_next(s, "ṭ"))
            cun_copy(s,"Ṭ");
    }
    else
        *s = toupper(*s);
}

bool cun_is_unknown_reading(char* s, size_t n)
{
    if(!n)
        return false;
    if(islower((unsigned char)*s))
        return false;
    if(n >= strlen("’") && !cun_compare_next(s, "’"))
        return cun_is_unknown_reading(s+strlen("’"), n-strlen("’"));
    if(n >= strlen("ḫ") && !cun_compare_next(s, "ḫ"))
        return false;
    if(n >= strlen("š") && !cun_compare_next(s, "š"))
        return false;
    if(n >= strlen("ĝ") && !cun_compare_next(s, "ĝ"))
        return false;
    if(n >= strlen("ř") && !cun_compare_next(s, "ř"))
        return false;
    if(n >= strlen("ṣ") && !cun_compare_next(s, "ṣ"))
        return false;
    if(n >= strlen("ṭ") && !cun_compare_next(s, "ṭ"))
        return false;
    if(n == strlen("II") && !cun_compare_next(s, "II"))
        return false;
    return true;
}



State* cun_init_state(const int line_capacity, MemoryContext memcontext)
{
    State* state;
    state = (State*) MemoryContextAllocZero(memcontext, sizeof(State));

    state->lines = (char **) MemoryContextAllocZero(memcontext, 10*sizeof(char *));
    state->line_lens = (int *) MemoryContextAllocZero(memcontext, 10*sizeof(int));
    state->line_count = 1;
    state->line_capacity = 10;
    state->lines[0] = (char *) MemoryContextAllocZero(memcontext, line_capacity);
    state->line_lens[0] = 0;
    state->string_capacity = line_capacity;

    state->compound_comment = (char *) MemoryContextAllocZero(memcontext, 100);
    state->compound_comment_len = 0;
    state->compound_comment_capacity = 100;
    state->word_no = -1;
    state->capitalize = false;
    return state;
}

char *cun_add_line(const int capacity, State *state, MemoryContext memcontext)
{
    if(state->line_count == state->line_capacity)
    {
        state->line_capacity *= 2;
        state->lines = (char **) repalloc(state->lines, state->line_capacity * sizeof(char *));
        state->line_lens = (int *) repalloc(state->line_lens, state->line_capacity * sizeof(int));   
    }
    state->lines[state->line_count] = (char *) MemoryContextAllocZero(memcontext, capacity);
    state->line_lens[state->line_count] = 0;
    state->line_count += 1;
    state->string_capacity = capacity;
    return state->lines[state->line_count-1];
}

char *cun_get_cursor(const int len, State *state)
{
    const int i = state->line_count-1;
    while(state->string_capacity < state->line_lens[i] + len)
    {
        state->string_capacity = 2*state->string_capacity;
        state->lines[i] = (char *)repalloc(state->lines[i], state->string_capacity);
    }
    return state->lines[i] + state->line_lens[i];
}


int cun_get_changes(const State* s1, const State* s2)
{
    int changes = 0;
    if(s1->condition != s2->condition)
        changes += CONDITION;
    if(s1->indicator_type != s2->indicator_type)
        changes += INDICATOR;
    if(s1->type != s2->type || s1->unknown_reading != s2->unknown_reading)
        changes += TYPE;
    if(s1->phonographic != s2->phonographic || s1->phonographic_null != s2->phonographic_null)
        changes += PHONOGRAPHIC;
    if(s1->highlight != s2->highlight)
        changes += HIGHLIGHT;
    if(s1->stem != s2->stem || s1->stem_null != s2->stem_null || (!s1->stem_null && s1->stem && s1->word_no != s2->word_no))
        changes += STEM;
    if(s1->pn_type != s2->pn_type || s1->pn_type_null != s2->pn_type_null || s1->word_no != s2->word_no)
        changes += PN_TYPE;
    if(s1->language != s2->language || s1->language_null != s2->language_null)
        changes += LANGUAGE;
    return changes;
}


Datum* cun_copy_print_result(const State *state, int extra_size)
{
    char *p;
    Datum* lines = (Datum*) palloc0(state->line_count * sizeof(Datum));
    int texts_size = extra_size;
    for(int i = 0; i < state->line_count; ++i)
        texts_size += state->line_lens[i] + VARHDRSZ;
    p = palloc0(texts_size);
    for(int i = 0; i < state->line_count; ++i)
    {
        text *t = (text *) p;
        SET_VARSIZE(t, state->line_lens[i] + VARHDRSZ);
        memcpy(VARDATA(t), state->lines[i], state->line_lens[i]);
        lines[i] = PointerGetDatum(t);
        p += state->line_lens[i] + VARHDRSZ;
    }
    return lines;
}


Connector cun_determine_connector(const State* s1, const State* s2, bool inverted, bool newline, bool ligature)
{
    Connector res = {SEP_DASH, 0, s1->sign_no + 1 != s2->sign_no};

    if(inverted)
        res.modifier = SEP_EXT_INVERSION;
    else if(newline)
        res.modifier = SEP_EXT_NEWLINE;
    else if(ligature)
        res.modifier = SEP_EXT_LIGATURE;
    else if(s1->line_no != s2->line_no)
        res.modifier = SEP_EXT_LINEBREAK;

    if(s1->indicator_type != ENUM_INDICATOR_TYPE.none && s2->indicator_type == s1->indicator_type)
        res.connector = s1->phonographic == s2->phonographic ? (s1->phonographic ? SEP_INDICATOR_P : SEP_INDICATOR_L) : SEP_INDICATOR_M;
    else if((s1->indicator_type == ENUM_INDICATOR_TYPE.right || s1->indicator_type == ENUM_INDICATOR_TYPE.center) || (s2->indicator_type == ENUM_INDICATOR_TYPE.left || s2->indicator_type == ENUM_INDICATOR_TYPE.center))
        res.connector = SEP_INDICATOR_0;
    else if(s1->compound_no != s2->compound_no)
        res.connector = SEP_COMPOUND;
    else if(s1->word_no != s2->word_no)
        res.connector = SEP_WORD;
    else if(s1->type == ENUM_TYPE.number && s2->type == ENUM_TYPE.number)
        res.connector = SEP_NUMBER;
    else if(s1->unknown_reading && s2->unknown_reading && s1->stem == s2->stem && s1->stem_null == s2->stem_null)
        res.connector = SEP_DOT;

    return res;
}


Oid cun_opened_condition_start(const char* s, size_t n, bool* no_condition)
{
    *no_condition = false;
    while(n-- != 0)
    {
        if(*s == ']')
            return ENUM_CONDITION.lost;
        if(n+1 >= strlen("⸣") && !cun_compare_next(s, "⸣"))
            return ENUM_CONDITION.damaged;
        if(n+1 >= strlen("›") && !cun_compare_next(s, "›"))
            return ENUM_CONDITION.inserted;
        if(n+1 >= strlen("»") && !cun_compare_next(s, "»"))
            return ENUM_CONDITION.deleted;
        if(*s == '[') 
            return ENUM_CONDITION.intact;
        if(n+1 >= strlen("⸢") && !cun_compare_next(s, "⸢"))
            return ENUM_CONDITION.intact;
        if(n+1 >= strlen("‹") && !cun_compare_next(s, "‹"))
            return ENUM_CONDITION.intact;
        if(n+1 >= strlen("«") && !cun_compare_next(s, "«"))
            return ENUM_CONDITION.intact;
        ++s;
    }
    *no_condition = true;
    return ENUM_CONDITION.intact;
}

Oid cun_opened_condition_end(const char* s, size_t n)
{
    size_t i = 0;
    s += n-1;
    while(i++ != n)
    {
        if(*s == ']')
            return ENUM_CONDITION.intact;
        if(i+1 >= strlen("⸣") && !cun_compare_next(s, "⸣"))
            return ENUM_CONDITION.intact;
        if(i+1 >= strlen("›") && !cun_compare_next(s, "›"))
            return ENUM_CONDITION.intact;
        if(i+1 >= strlen("»") && !cun_compare_next(s, "»"))
            return ENUM_CONDITION.intact;
        if(*s == '[') 
            return ENUM_CONDITION.lost;
        if(i+1 >= strlen("⸢") && !cun_compare_next(s, "⸢"))
            return ENUM_CONDITION.damaged;
        if(i+1 >= strlen("‹") && !cun_compare_next(s, "‹"))
            return ENUM_CONDITION.inserted;
        if(i+1 >= strlen("«") && !cun_compare_next(s, "«"))
            return ENUM_CONDITION.deleted;
        --s;
    }
    return ENUM_CONDITION.intact;
}


void cun_copy_compound_comment(const text* compound_comment, State* state)
{
    if(compound_comment != NULL)
    {
        const int len = VARSIZE_ANY_EXHDR(compound_comment);
        if(state->compound_comment_capacity < len)
        {
            state->compound_comment = (char *) repalloc(state->compound_comment, len);
            state->compound_comment_capacity = len;
        }
        cun_copy_n(state->compound_comment, VARDATA_ANY(compound_comment), len);
        state->compound_comment_len = len;
    }
    else
        state->compound_comment_len = 0;
}