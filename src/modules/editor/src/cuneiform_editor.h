#include <postgres.h>

#include <funcapi.h>

#ifdef PG_MODULE_MAGIC
PG_MODULE_MAGIC;
#endif

Datum cuneiform_levenshtein(PG_FUNCTION_ARGS);
PG_FUNCTION_INFO_V1(cuneiform_levenshtein);
