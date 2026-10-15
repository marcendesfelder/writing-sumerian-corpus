#include "cuneiform_citation.h"

#include <fmgr.h>
#include <executor/executor.h>
#include <executor/spi.h>
#include <utils/builtins.h>
#include <access/htup_details.h>
#include <catalog/pg_type.h>
#include <utils/array.h>

static const int32 dash_size = strlen("–");
static const int32 dot_size = strlen("; ");

static char* cun_copy_n(char* s1, const char* s2, size_t n)
{
    while(n-- != 0)
        *s1++ = *s2++;
    return s1;
}

static char* cun_copy(char* s1, const char* s2)
{
    while(*s2 != '\0')
        *s1++ = *s2++;
    return s1;
}


static text* copy_text(const text* b, MemoryContext memcontext)
{
    text* a;

    if(!b)
        return NULL;

    a = (text*) MemoryContextAllocZero(memcontext, VARSIZE_ANY_EXHDR(b)+VARHDRSZ);
    SET_VARSIZE(a, VARSIZE_ANY_EXHDR(b)+VARHDRSZ);
    memcpy((void*)VARDATA(a), (void*)VARDATA_ANY(b), VARSIZE_ANY_EXHDR(b));
    return a;
}

typedef struct State
{
    text* string;

    text* surface;
    text* surface_start;
    int32 surface_no;
    int32 surface_no_start;
    bool print_surface;

    text* block;
    text* block_start;
    int32 block_no;
    int32 block_no_start;
    bool print_block;

    text* line;
    text* line_start;
    int32 line_no;
    int32 line_no_start;
} State;


static text* assamble_range(const State* state, text* string)
{
    const int32 string_size = VARSIZE_ANY_EXHDR(string);
    int32 size = string_size;

    const int changes 
        = 4 * (int)(state->surface_no != state->surface_no_start) 
        + 2 * (int)(state->block_no != state->block_no_start)
        + (int)(state->line_no != state->line_no_start);

    char* s;

    if(string_size)
        size += dot_size;

    if((changes > 3 || state->print_surface) && state->surface_start)
        size += VARSIZE_ANY_EXHDR(state->surface_start) + 1;
    if((changes > 1 || state->print_block) && state->block_start)
        size += VARSIZE_ANY_EXHDR(state->block_start) + 1;
    if(state->line_start)
        size += VARSIZE_ANY_EXHDR(state->line_start);
    if(changes > 1)
        size += dash_size + 2;
    else if(changes > 0)
        size += dash_size;
    if(changes > 3 && state->surface)
        size += VARSIZE_ANY_EXHDR(state->surface) + 1;
    if(changes > 1 && state->block)
        size += VARSIZE_ANY_EXHDR(state->block) + 1;
    if(changes > 0 && state->line)
        size += VARSIZE_ANY_EXHDR(state->line);

    string = (text*)repalloc(string, size + VARHDRSZ);
    s = VARDATA(string)+string_size;

    
    if(string_size)
        s = cun_copy(s, "; ");

    if((changes > 3 || state->print_surface) && state->surface_start)
    {
        s = cun_copy_n(s, VARDATA(state->surface_start), VARSIZE_ANY_EXHDR(state->surface_start));
        s = cun_copy(s, " ");
    }
    if((changes > 1 || state->print_block) && state->block_start)
    {
        s = cun_copy_n(s, VARDATA(state->block_start), VARSIZE_ANY_EXHDR(state->block_start));
        s = cun_copy(s, " ");
    }
    if(state->line_start)
        s = cun_copy_n(s, VARDATA(state->line_start), VARSIZE_ANY_EXHDR(state->line_start));
    if(changes > 1)
        s = cun_copy(s, " – ");
    else if(changes > 0)
        s = cun_copy(s, "–");
    if(changes > 3 && state->surface)
    {
        s = cun_copy_n(s, VARDATA(state->surface), VARSIZE_ANY_EXHDR(state->surface));
        s = cun_copy(s, " ");
    }
    if(changes > 1 && state->block)
    {
        s = cun_copy_n(s, VARDATA(state->block), VARSIZE_ANY_EXHDR(state->block));
        s = cun_copy(s, " ");
    }
    if(changes > 0 && state->line)
        s = cun_copy_n(s, VARDATA(state->line), VARSIZE_ANY_EXHDR(state->line));

    SET_VARSIZE(string, s-VARDATA(string)+VARHDRSZ);

    return string;
}


Datum cuneiform_citation_agg_sfunc(PG_FUNCTION_ARGS)
{
    MemoryContext aggcontext;
    State* state;

    const text* surface = PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1);
    const int32 surface_no = PG_GETARG_INT32(2);
    const text* block = PG_ARGISNULL(3) ? NULL : PG_GETARG_TEXT_PP(3);
    const int32 block_no = PG_GETARG_INT32(4);
    const text* line = PG_ARGISNULL(5) ? NULL : PG_GETARG_TEXT_PP(5);
    const int32 line_no = PG_GETARG_INT32(6);

    if (!AggCheckCallContext(fcinfo, &aggcontext))
    {
        /* cannot be called directly because of internal-type argument */
        elog(ERROR, "array_agg_transfn called in non-aggregate context");
    }

    if(PG_ARGISNULL(0)) 
    {
        state = (State*) MemoryContextAllocZero(aggcontext, sizeof(State));
        state->string = (text*) MemoryContextAllocZero(aggcontext, VARHDRSZ);
        SET_VARSIZE(state->string, VARHDRSZ);
        state->surface_no = -2;
        state->block_no = -2;
        state->line_no = -2;
        state->surface_no_start = -2;
        state->block_no_start = -2;
        state->line_no_start = -2;
        state->print_surface = true;
        state->print_block = true;
    }
    else
        state = (State*) PG_GETARG_POINTER(0);

    if(line_no != state->line_no+1)
    {
        if(!PG_ARGISNULL(0)) 
            state->string = assamble_range(state, state->string);

        state->print_surface = false;
        state->print_block = false;

        if(surface_no != state->surface_no_start)
        {
            state->surface_start = copy_text(surface, aggcontext);
            state->surface_no_start = surface_no;
            state->print_surface = true;
            state->print_block = true;
        }
        if(block_no != state->block_no_start)
        {
            state->block_start = copy_text(block, aggcontext);
            state->block_no_start = block_no;
            state->print_block = true;
        }
        state->line_start = copy_text(line, aggcontext);
        state->line_no_start = line_no;
    }

    if(surface_no != state->surface_no)
    {
        state->surface = copy_text(surface, aggcontext);
        state->surface_no = surface_no;
        state->print_surface = true;
        state->print_block = true;
    }
    if(block_no != state->block_no)
    {
        state->block = copy_text(block, aggcontext);
        state->block_no = block_no;
        state->print_block = true;
    }
    state->line = copy_text(line, aggcontext);
    state->line_no = line_no;

    PG_RETURN_POINTER(state);
}

Datum cuneiform_citation_agg_finalfunc(PG_FUNCTION_ARGS)
{
    MemoryContext aggcontext;
    text* string;
    const State* state;

    if (!AggCheckCallContext(fcinfo, &aggcontext))
    {
        /* cannot be called directly because of internal-type argument */
        elog(ERROR, "array_agg_transfn called in non-aggregate context");
    }

    state = PG_ARGISNULL(0) ? NULL : (State*) PG_GETARG_POINTER(0);
    if(state == NULL)
        PG_RETURN_NULL();

    // the finalfunc may not alter state, therefore we need to copy everything

    string = copy_text(state->string, aggcontext);
    string = assamble_range(state, string);

    PG_RETURN_TEXT_P(string);
}