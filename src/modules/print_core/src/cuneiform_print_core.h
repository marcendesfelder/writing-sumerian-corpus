#ifndef CUNEIFORM_PRINT_CORE_H
#define CUNEIFORM_PRINT_CORE_H

#include <postgres.h>
#include <fmgr.h>

typedef struct CunEnumType {
    Oid sign;
    Oid number;
    Oid punctuation;
    Oid description;
    Oid damage;
} cunEnumType;

typedef struct CunEnumIndicatorType {
    Oid none;
    Oid left;
    Oid right;
    Oid center;
} cunEnumIndicatorType;


typedef struct CunEnumLanguage {
    Oid sumerian;
    Oid akkadian;
    Oid hittite;
    Oid eblaite;
    Oid other;
} cunEnumLanguage;

typedef struct CunEnumCondition {
    Oid intact;
    Oid damaged;
    Oid lost;
    Oid inserted;
    Oid deleted;
    Oid erased;
} cunEnumCondition;

typedef struct CunEnumVariantType {
    Oid default_variant;
    Oid nondefault;
    Oid reduced;
    Oid augmented;
    Oid nonstandard;
} cunEnumVariantType;

typedef struct CunEnumPN {
    Oid person;
    Oid god;
    Oid place;
    Oid water;
    Oid field;
    Oid temple;
    Oid month;
    Oid object;
    Oid ethnicity;
} cunEnumPN;

typedef void (*set_enums_t) (
    cunEnumType *type,
    cunEnumIndicatorType *indicator_type,
    cunEnumLanguage *language,
    cunEnumCondition *condition,
    cunEnumVariantType *variant_type,
    cunEnumPN *pn,
    bool *enums_set
);


#define  LANGUAGE          128
#define  PN_TYPE            64
#define  STEM               32
#define  HIGHLIGHT          16
#define  PHONOGRAPHIC        8
#define  TYPE                4
#define  INDICATOR           2
#define  CONDITION           1


typedef struct State
{
    char** lines;
    int* line_lens;
    int line_count;
    size_t line_capacity;
    size_t string_capacity;

    char* compound_comment;
    size_t compound_comment_capacity;
    int compound_comment_len;

    int sign_no;
    int word_no;
    int compound_no;
    int line_no;
    int section_no;
    bool section_null;
    Oid type;
    bool phonographic;
    bool phonographic_null;
    Oid indicator_type;
    bool stem;
    bool stem_null;
    Oid condition;
    Oid language;
    bool language_null;
    bool unknown_reading;
    Oid pn_type;
    bool pn_type_null;
    bool highlight;

    bool capitalize;
} State;


#define SEP_DASH            0
#define SEP_DOT             1
#define SEP_NUMBER          2
#define SEP_INDICATOR_P     3
#define SEP_INDICATOR_L     4
#define SEP_INDICATOR_M     5
#define SEP_INDICATOR_0     6
#define SEP_WORD            7
#define SEP_COMPOUND        8

#define SEP_EXT_NEWLINE     1
#define SEP_EXT_LINEBREAK   2
#define SEP_EXT_LIGATURE    3
#define SEP_EXT_INVERSION   4

typedef struct Connector
{
    int connector;
    int modifier;
    bool ellipsis;
} Connector;

typedef void (*cun_set_enums_t)(void);
typedef cunEnumType *(*cun_enum_type_t)(void);
typedef cunEnumIndicatorType *(*cun_enum_indicator_type_t)(void);
typedef cunEnumLanguage *(*cun_enum_language_t)(void);
typedef cunEnumCondition *(*cun_enum_condition_t)(void);
typedef cunEnumVariantType *(*cun_enum_variant_type_t)(void);
typedef cunEnumPN *(*cun_enum_pn_t)(void);
extern PGDLLEXPORT void cun_set_enums(void);
extern PGDLLEXPORT cunEnumType *cun_enum_type(void);
extern PGDLLEXPORT cunEnumIndicatorType *cun_enum_indicator_type(void);
extern PGDLLEXPORT cunEnumLanguage *cun_enum_language(void);
extern PGDLLEXPORT cunEnumCondition *cun_enum_condition(void);
extern PGDLLEXPORT cunEnumVariantType *cun_enum_variant_type(void);
extern PGDLLEXPORT cunEnumPN *cun_enum_pn(void);


typedef char *(*cun_copy_n_t)(char *s1, const char *s2, size_t n);
typedef char *(*cun_copy_t)(char *s1, const char *s2);
typedef int (*cun_compare_next_t)(const char *s1, const char *s2);
typedef void (*cun_capitalize_t)(char *s);
typedef bool (*cun_is_unknown_reading_t)(char *s, size_t n);
extern PGDLLEXPORT char *cun_copy_n(char *s1, const char *s2, size_t n);
extern PGDLLEXPORT char *cun_copy(char *s1, const char *s2);
extern PGDLLEXPORT int cun_compare_next(const char *s1, const char *s2);
extern PGDLLEXPORT void cun_capitalize(char *s);
extern PGDLLEXPORT bool cun_is_unknown_reading(char *s, size_t n);

typedef State *(*cun_init_state_t)(int line_capacity, MemoryContext memcontext);
typedef char *(*cun_add_line_t)(int capacity, State *state, MemoryContext memcontext);
typedef char *(*cun_get_cursor_t)(int len, State *state);
typedef int (*cun_get_changes_t)(const State *s1, const State *s2);
typedef Datum *(*cun_copy_print_result_t)(const State *state);
typedef Connector (*cun_determine_connector_t)(const State *s1, const State *s2, bool inverted, bool newline, bool ligature);
typedef Oid (*cun_opened_condition_start_t)(const char *s, size_t n, bool *no_condition);
typedef Oid (*cun_opened_condition_end_t)(const char *s, size_t n);
typedef void (*cun_copy_compound_comment_t)(const text *compound_comment, State *state);
extern PGDLLEXPORT State *cun_init_state(int line_capacity, MemoryContext memcontext);
extern PGDLLEXPORT char *cun_add_line(int capacity, State *state, MemoryContext memcontext);
extern PGDLLEXPORT char *cun_get_cursor(int len, State *state);
extern PGDLLEXPORT int cun_get_changes(const State *s1, const State *s2);
extern PGDLLEXPORT Datum* cun_copy_print_result(const State *state);
extern PGDLLEXPORT Connector cun_determine_connector(const State *s1, const State *s2, bool inverted, bool newline, bool ligature);
extern PGDLLEXPORT Oid cun_opened_condition_start(const char *s, size_t n, bool *no_condition);
extern PGDLLEXPORT Oid cun_opened_condition_end(const char *s, size_t n);
extern PGDLLEXPORT void cun_copy_compound_comment(const text *compound_comment, State *state);

#endif // CUNEIFORM_PRINT_CORE_H