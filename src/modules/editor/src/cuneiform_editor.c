#include "cuneiform_editor.h"

#include <fmgr.h>
#include <miscadmin.h>
#include <access/htup_details.h>
#include <utils/array.h>
#include <utils/builtins.h>
#include <utils/lsyscache.h>
#include <utils/typcache.h>

typedef enum LevenshteinOp
{
    OP_NONE = 0,
    OP_INSERT,
    OP_DELETE,
    OP_UPDATE
} LevenshteinOp;

static const char* const op_labels[] = {"NONE", "INSERT", "DELETE", "UPDATE"};

typedef struct WagnerFischerOp
{
    LevenshteinOp op;
    int32 pos;
} WagnerFischerOp;


static ArrayType* build_ops_array(const WagnerFischerOp* ops, int count, Oid op_array_type)
{
    const Oid op_type = get_element_type(op_array_type);
    TupleDesc op_tupdesc;
    Oid enum_type;
    Datum enum_values[lengthof(op_labels)];
    Datum* elems;
    int16 typlen;
    bool typbyval;
    char typalign;
    ArrayType* result;

    if(!OidIsValid(op_type))
        elog(ERROR, "levenshtein: v_ops is not an array type");

    if(count == 0)
        return construct_empty_array(op_type);

    op_tupdesc = lookup_rowtype_tupdesc(op_type, -1);
    enum_type = TupleDescAttr(op_tupdesc, 0)->atttypid;

    for(int i = 0; i < lengthof(op_labels); ++i)
        enum_values[i] = DirectFunctionCall2(enum_in, CStringGetDatum(op_labels[i]), ObjectIdGetDatum(enum_type));

    elems = (Datum*) palloc(count * sizeof(Datum));
    for(int i = 0; i < count; ++i)
    {
        Datum values[2];
        bool nulls[2] = {false, false};

        values[0] = enum_values[ops[i].op];
        values[1] = Int32GetDatum(ops[i].pos);
        elems[i] = HeapTupleGetDatum(heap_form_tuple(op_tupdesc, values, nulls));
    }
    ReleaseTupleDesc(op_tupdesc);

    get_typlenbyvalalign(op_type, &typlen, &typbyval, &typalign);
    result = construct_array(elems, count, op_type, typlen, typbyval, typalign);
    pfree(elems);
    return result;
}

Datum cuneiform_levenshtein(PG_FUNCTION_ARGS)
{
    ArrayType* s_array = PG_GETARG_ARRAYTYPE_P(0);
    ArrayType* t_array = PG_GETARG_ARRAYTYPE_P(1);
    const Oid elemtype = ARR_ELEMTYPE(s_array);
    const Oid collation = PG_GET_COLLATION();

    TupleDesc tupdesc;
    TypeCacheEntry* typentry;
    int16 typlen;
    bool typbyval;
    char typalign;

    Datum* s;
    Datum* t;
    bool* s_nulls;
    bool* t_nulls;
    int n;
    int m;

    int32* prev;
    int32* cur;
    uint8* o;
    Size width;

    WagnerFischerOp* ops;
    int count = 0;
    int i;
    int j;

    Datum values[2];
    bool nulls[2] = {false, false};

    if(ARR_ELEMTYPE(t_array) != elemtype)
        ereport(ERROR,
                (errcode(ERRCODE_DATATYPE_MISMATCH),
                 errmsg("levenshtein: arrays must have the same element type")));

    if(get_call_result_type(fcinfo, NULL, &tupdesc) != TYPEFUNC_COMPOSITE)
        elog(ERROR, "levenshtein: return type must be a row type");
    tupdesc = BlessTupleDesc(tupdesc);

    typentry = lookup_type_cache(elemtype, TYPECACHE_EQ_OPR_FINFO);
    if(!OidIsValid(typentry->eq_opr_finfo.fn_oid))
        ereport(ERROR,
                (errcode(ERRCODE_UNDEFINED_FUNCTION),
                 errmsg("levenshtein: could not identify an equality operator for type %s",
                        format_type_be(elemtype))));

    get_typlenbyvalalign(elemtype, &typlen, &typbyval, &typalign);
    deconstruct_array(s_array, elemtype, typlen, typbyval, typalign, &s, &s_nulls, &n);
    deconstruct_array(t_array, elemtype, typlen, typbyval, typalign, &t, &t_nulls, &m);

    width = (Size) m + 1;
    if((Size) n + 1 > MaxAllocHugeSize / width)
        ereport(ERROR,
                (errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
                 errmsg("levenshtein: arrays too large (%d x %d)", n, m)));

    prev = (int32*) palloc(width * sizeof(int32));
    cur = (int32*) palloc(width * sizeof(int32));
    o = (uint8*) palloc_extended(((Size) n + 1) * width, MCXT_ALLOC_HUGE);

    for(j = 0; j <= m; ++j)
        prev[j] = j;

    for(i = 1; i <= n; ++i)
    {
        int32* tmp;

        CHECK_FOR_INTERRUPTS();

        cur[0] = i;
        for(j = 1; j <= m; ++j)
        {
            int32 cost = prev[j-1];
            uint8 op = OP_NONE;

            if(s_nulls[i-1] || t_nulls[j-1] ?
               s_nulls[i-1] != t_nulls[j-1] :
               !DatumGetBool(FunctionCall2Coll(&typentry->eq_opr_finfo, collation, s[i-1], t[j-1])))
            {
                cost += 1;
                op = OP_UPDATE;
            }

            if(cost > prev[j] + 1)
            {
                cost = prev[j] + 1;
                op = OP_DELETE;
            }
            else if(cost > cur[j-1] + 1)
            {
                cost = cur[j-1] + 1;
                op = OP_INSERT;
            }

            cur[j] = cost;
            o[i * width + j] = op;
        }

        tmp = prev;
        prev = cur;
        cur = tmp;
    }

    values[0] = Int32GetDatum(prev[m]);

    /* Backtrace; ops are collected in reverse order. Positions follow the
       1-based column index l = j+1 of the former PL/pgSQL implementation. */
    ops = (WagnerFischerOp*) palloc(((Size) n + m + 1) * sizeof(WagnerFischerOp));
    i = n;
    j = m;
    while(i != 0 && j != 0)
    {
        switch(o[i * width + j])
        {
            case OP_DELETE:
                ops[count++] = (WagnerFischerOp){OP_DELETE, j+1};
                --i;
                break;
            case OP_INSERT:
                ops[count++] = (WagnerFischerOp){OP_INSERT, j};
                --j;
                break;
            case OP_UPDATE:
                ops[count++] = (WagnerFischerOp){OP_UPDATE, j};
                --i;
                --j;
                break;
            default:
                --i;
                --j;
                break;
        }
    }
    for(; i > 0; --i)
        ops[count++] = (WagnerFischerOp){OP_DELETE, 1};
    for(; j > 0; --j)
        ops[count++] = (WagnerFischerOp){OP_INSERT, 1};

    for(int a = 0, b = count-1; a < b; ++a, --b)
    {
        WagnerFischerOp tmp = ops[a];
        ops[a] = ops[b];
        ops[b] = tmp;
    }

    values[1] = PointerGetDatum(build_ops_array(ops, count, TupleDescAttr(tupdesc, 1)->atttypid));

    PG_RETURN_DATUM(HeapTupleGetDatum(heap_form_tuple(tupdesc, values, nulls)));
}
