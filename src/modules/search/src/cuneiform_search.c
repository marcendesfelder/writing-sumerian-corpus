#include "cuneiform_search.h"

#include <stdlib.h>

#include <libpq/pqformat.h>
#include <common/hashfn.h>
#include <utils/array.h>
#include <utils/lsyscache.h>
#include <catalog/pg_type.h>

static uint32 sign_no(const uint32 val)
{
    return val >> 8;
}

static uint32 component_no(const uint32 val)
{
    return val >> 1 & ((1 << 7) - 1);
}

static bool final(const uint32 val)
{
    return val%2;
}

Datum position_in(PG_FUNCTION_ARGS)
{
    char* str = PG_GETARG_CSTRING(0);

    uint32 sign_no;
    uint32 component_no;
    bool final;
        
    char* s1;
    char* s2;

    s1 = str;
    while(*s1 != '.' && *s1 != '\0')
        if(*s1 < '0' || *(s1++) > '9')
            goto error;
    if(*s1 != '.' || s1-str > 7 || s1 == str)
        goto error;

    sign_no = (uint32)atoi(str);

    s2 = ++s1;
    while(*s2 != '.' && *s2 != '\0')
        if(*s2 < '0' || *(s2++) > '9')
            goto error;
    if(*s2 != '.' || s2-s1 > 2 || s2 == s1)
        goto error;
    component_no = (uint32)atoi(s1);

    ++s2;
    if(*s2 == '1')
        final = true;
    else if(*s2 == '0')
        final = false;
    else
        goto error;
    if(*(s2+1) != '\0')
        goto error;
    
    PG_RETURN_UINT32(sign_no << 8 | component_no << 1 | (uint32)final);

error:
    ereport(ERROR,
        (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
            errmsg("invalid input syntax for type %s: \"%s\"",
                "cun_position", str)));
    PG_RETURN_NULL();
}

Datum position_out(PG_FUNCTION_ARGS)
{
    uint32 val = PG_GETARG_UINT32(0);
    char* result;

    result = psprintf("%u.%u.%c", sign_no(val), component_no(val), final(val) ? '1' : '0');
    PG_RETURN_CSTRING(result);
}

Datum position_recv(PG_FUNCTION_ARGS)
{
    StringInfo buf = (StringInfo)PG_GETARG_POINTER(0);
    PG_RETURN_UINT32(pq_getmsgint(buf, 4));
}

Datum position_send(PG_FUNCTION_ARGS)
{
    uint32 val = PG_GETARG_UINT32(0);
    StringInfoData buf;

    pq_begintypsend(&buf);
    pq_sendint(&buf, val, 4);
    PG_RETURN_BYTEA_P(pq_endtypsend(&buf));
}


static int32 order(uint32 a, uint32 b) 
{
    a >>= 1;
    b >>= 1;
    if(a == b)
        return 0;
    return  a < b ? -1 : 1;
}

Datum position_next(PG_FUNCTION_ARGS)
{
    uint32 val = PG_GETARG_UINT32(0);
    if(val%2)
    {
        val += 1 << 8;
        val &= ~((1 << 8) - 1);
    }
    else
        val += 2;
    PG_RETURN_UINT32(val);
}

Datum position_less(PG_FUNCTION_ARGS)
{
    uint32 a = PG_GETARG_UINT32(0) >> 1;
    uint32 b = PG_GETARG_UINT32(1) >> 1;
    PG_RETURN_BOOL(a < b);
}

Datum position_greater(PG_FUNCTION_ARGS)
{
    uint32 a = PG_GETARG_UINT32(0) >> 1;
    uint32 b = PG_GETARG_UINT32(1) >> 1;
    PG_RETURN_BOOL(a > b);
}

Datum position_leq(PG_FUNCTION_ARGS)
{
    uint32 a = PG_GETARG_UINT32(0) >> 1;
    uint32 b = PG_GETARG_UINT32(1) >> 1;
    PG_RETURN_BOOL(a <= b);
}

Datum position_geq(PG_FUNCTION_ARGS)
{
    uint32 a = PG_GETARG_UINT32(0) >> 1;
    uint32 b = PG_GETARG_UINT32(1) >> 1;
    PG_RETURN_BOOL(a >= b);
}

Datum position_equal(PG_FUNCTION_ARGS)
{
    uint32 a = PG_GETARG_UINT32(0) >> 1;
    uint32 b = PG_GETARG_UINT32(1) >> 1;
    PG_RETURN_BOOL(a == b);
}

Datum position_neq(PG_FUNCTION_ARGS)
{
    uint32 a = PG_GETARG_UINT32(0) >> 1;
    uint32 b = PG_GETARG_UINT32(1) >> 1;
    PG_RETURN_BOOL(a != b);
}


Datum position_order(PG_FUNCTION_ARGS)
{
    uint32 a = PG_GETARG_UINT32(0);
    uint32 b = PG_GETARG_UINT32(1);
    PG_RETURN_INT32(order(a,b));
}

Datum position_sign_no(PG_FUNCTION_ARGS)
{
    uint32 val = PG_GETARG_UINT32(0);
    PG_RETURN_INT32(sign_no(val));
}

Datum position_component_no(PG_FUNCTION_ARGS)
{
    uint32 val = PG_GETARG_UINT32(0);
    PG_RETURN_INT32(component_no(val));
}

Datum position_equalimage(PG_FUNCTION_ARGS)
{
    PG_RETURN_BOOL(false);
}

Datum position_hash(PG_FUNCTION_ARGS)
{
    uint32 val = PG_GETARG_UINT32(0);
    return hash_uint32(val >> 1);
}

Datum position_hash_extended(PG_FUNCTION_ARGS)
{
    uint32 val = PG_GETARG_UINT32(0);
    uint64 seed = PG_GETARG_INT64(1);
    return hash_uint32_extended(val >> 1, seed);
}


Datum position_construct(PG_FUNCTION_ARGS)
{
    int32 sign_no = PG_GETARG_INT32(0);
    int32 component_no = PG_GETARG_INT32(1);
    bool final = PG_GETARG_BOOL(2);

    if(sign_no > 9999999 || sign_no < 0)
        ereport(ERROR,
            (errcode(ERRCODE_NUMERIC_VALUE_OUT_OF_RANGE),
             errmsg("invalid value for sign no: %d", sign_no)));
    if(component_no > 99 || component_no < 0)
        ereport(ERROR,
            (errcode(ERRCODE_NUMERIC_VALUE_OUT_OF_RANGE),
             errmsg("invalid value for component no: %d", component_no)));
    
    PG_RETURN_UINT32((uint32)sign_no << 8 | (uint32)component_no << 1 | (uint32)final);
}

static int cmp_position(const void* a, const void* b)
{
    return order(DatumGetUInt32(*(const Datum*)a), DatumGetUInt32(*(const Datum*)b));
}

static int cmp_int32(const void* a, const void* b)
{
    int32 x = DatumGetInt32(*(const Datum*)a);
    int32 y = DatumGetInt32(*(const Datum*)b);
    return (x > y) - (x < y);
}

Datum unique(PG_FUNCTION_ARGS)
{
    ArrayType* array;
    Oid element_type;
    bool typbyval;
    char typalign;
    int16 typlen;

    Datum* vals;
    bool* nulls;
    int nargs;
    int n;

    array = PG_GETARG_ARRAYTYPE_P(0);
    element_type = ARR_ELEMTYPE(array);

    get_typlenbyvalalign(element_type, &typlen, &typbyval, &typalign);
    deconstruct_array(array, element_type, typlen, typbyval,
                      typalign, &vals, &nulls, &nargs);
           
    if(!nargs)
        PG_RETURN_NULL();
    n = nargs-1;
    while(nulls[n] && n--);
    if(n < 0)
        PG_RETURN_NULL();

    for(int i = 0; i < n; i++)
    {
        if(nulls[i])
        {
            vals[i] = vals[n];
            nulls[i] = false;
            while(n && nulls[--n]);
        }
    }
    ++n;

    qsort(vals, n, sizeof(Datum), cmp_position);
    for(int i = 1; i < n; i++)
    {
        uint32 a = DatumGetUInt32(vals[i-1]);
        uint32 b = DatumGetUInt32(vals[i]);
        if(sign_no(a) == sign_no(b) && (final(a) || component_no(a) == component_no(b)))
            PG_RETURN_BOOL(false);
    }
        
    PG_RETURN_BOOL(true);
}

Datum consecutive(PG_FUNCTION_ARGS)
{
    ArrayType* array;
    Oid element_type;
    bool typbyval;
    char typalign;
    int16 typlen;

    Datum* vals;
    bool* nulls;
    int nargs;
    int n;

    array = PG_GETARG_ARRAYTYPE_P(0);
    element_type = ARR_ELEMTYPE(array);

    get_typlenbyvalalign(element_type, &typlen, &typbyval, &typalign);
    deconstruct_array(array, element_type, typlen, typbyval,
                      typalign, &vals, &nulls, &nargs);
           
    if(!nargs)
        PG_RETURN_NULL();
    n = nargs-1;
    while(nulls[n] && n--);
    if(n < 0)
        PG_RETURN_NULL();

    for(int i = 0; i < n; i++)
    {
        if(nulls[i])
        {
            vals[i] = vals[n];
            nulls[i] = false;
            while(n && nulls[--n]);
        }
    }
    ++n;

    qsort(vals, n, sizeof(Datum), cmp_position);
    for(int i = 1; i < n; i++)
    {
        uint32 a = DatumGetUInt32(vals[i-1]);
        uint32 b = DatumGetUInt32(vals[i]);
        switch(sign_no(b) - sign_no(a))
        {
            case 0:
                if(final(a) || component_no(a)+1 != component_no(b))
                    PG_RETURN_BOOL(false);
                break;
            case 1:
                if(!final(a) || component_no(b))
                    PG_RETURN_BOOL(false);
                break;
            default:
                PG_RETURN_BOOL(false);
        }
    }
        
    PG_RETURN_BOOL(true);
}


Datum get_sign_nos(PG_FUNCTION_ARGS)
{
    ArrayType* array;
    ArrayType* result;
    Oid element_type;
    bool typbyval;
    char typalign;
    int16 typlen;

    Datum* vals;
    Datum* vals_new;
    bool* nulls;
    int nargs;
    int n;
    int n_new = 0;

    array = PG_GETARG_ARRAYTYPE_P(0);
    element_type = ARR_ELEMTYPE(array);

    get_typlenbyvalalign(element_type, &typlen, &typbyval, &typalign);
    deconstruct_array(array, element_type, typlen, typbyval,
                      typalign, &vals, &nulls, &nargs);
           
    n = nargs - 1;
    while(n >= 0 && nulls[n]) --n;
    if(n < 0)
    {
        result = construct_empty_array(INT4OID);
        PG_RETURN_ARRAYTYPE_P(result);
    }

    for(int i = 0; i < n; i++)
    {
        if(nulls[i])
        {
            vals[i] = vals[n];
            nulls[i] = false;
            while(n && nulls[--n]);
        }
    }
    ++n;

    qsort(vals, n, sizeof(Datum), cmp_position);

    vals_new = (Datum*)palloc(n*sizeof(Datum));
    for(int i = 0; i < n; i++)
    {
        const int32 v = (int32)sign_no(DatumGetUInt32(vals[i]));
        if(!n_new || DatumGetInt32(vals_new[n_new-1]) != v)
            vals_new[n_new++] = Int32GetDatum(v);
    }

    get_typlenbyvalalign(INT4OID, &typlen, &typbyval, &typalign);
    result = construct_array(vals_new, n_new, INT4OID, typlen, typbyval, typalign);

    PG_RETURN_ARRAYTYPE_P(result);
}

Datum sort_uniq_remove_null(PG_FUNCTION_ARGS)
{
    ArrayType* array;
    ArrayType* result;
    Oid element_type;
    bool typbyval;
    char typalign;
    int16 typlen;

    Datum* vals;
    Datum* vals_new;
    bool* nulls;
    int nargs;
    int n;
    int n_new = 0;

    array = PG_GETARG_ARRAYTYPE_P(0);
    element_type = ARR_ELEMTYPE(array);

    get_typlenbyvalalign(element_type, &typlen, &typbyval, &typalign);
    deconstruct_array(array, element_type, typlen, typbyval,
                      typalign, &vals, &nulls, &nargs);
           
    n = nargs - 1;
    while(n >= 0 && nulls[n]) --n;
    if(n < 0)
    {
        result = construct_empty_array(INT4OID);
        PG_RETURN_ARRAYTYPE_P(result);
    }

    for(int i = 0; i < n; i++)
    {
        if(nulls[i])
        {
            vals[i] = vals[n];
            nulls[i] = false;
            while(n && nulls[--n]);
        }
    }
    ++n;

    qsort(vals, n, sizeof(Datum), cmp_int32);

    vals_new = (Datum*)palloc(n*sizeof(Datum));
    for(int i = 0; i < n; i++)
        if(!n_new || vals_new[n_new-1] != vals[i])
            vals_new[n_new++] = vals[i];

    get_typlenbyvalalign(INT4OID, &typlen, &typbyval, &typalign);
    result = construct_array(vals_new, n_new, INT4OID, typlen, typbyval, typalign);

    PG_RETURN_ARRAYTYPE_P(result);
}