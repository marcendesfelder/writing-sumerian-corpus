# Search syntax

This document describes the query language implemented by the `cuneiform_search`
extension. A query describes a sequence of signs and graphemes together with 
constraints on how those units are grouped into words, compounds and lines. 
The extension can run a query against any table that has the layout of `corpus_search`, 
for example the corpus (`search_corpus.search`) and the personal name tables (`cuneiform_pns`).

Queries are processed in two stages:

1. `preparse_search(search_term)` parses the query that the user typed, resolves
   every sign reference against the sign list, and returns an intermediate *code*
   string together with the list of *wildcards* (see [section 9](#9-wildcards-and-capture-groups)).
2. `parse_search(code, table, key, schema)` turns the code into an SQL query.

Sections 1–9 describe the user-facing syntax (the input to `preparse_search`).
Section 10 describes the intermediate code.

---

## 1. Overview

```
{d}en-lil2           the god name Enlil: determinative d, then en and lil2 in one word
lugal … e2           lugal, followed later in the same text by e2
(a|e)-ĝu10           a or e, then ĝu10 in the same word
|KA×A|               any variant of the sign KA×A
/du/                 any reading du, du2, du3, …, dux
;lugal;              lugal as a complete word
```

A query is a sequence of **segments** (units plus indicators, groups, line groups and alternatives)
joined by **separators**. Every separator states how the two units it connects
relate to each other: directly adjacent, later in the text, in the same word, in
a different line, and so on.

---

## 2. Units

### 2.1 Readings (values)

A reading in lower case, such as `du`, `ĝen`, `lugal`, `e2` or `ša3`, matches
every occurrence of that reading.

- The alphabet is `a b d e g ĝ h ḫ i j k l m n p q r ř s š ṣ t ṭ u w y z ’`.
- The reading may end in an index: digits (`du3`, `ĝen6`) or `x` (`dux`).
  `du` and `du3` are different readings. An index is never added implicitly.
- Single letters are only accepted for the vowels `a e i u` and for `d`.
  (`n` on its own is the number wildcard; see 2.5.)
- Readings must be all lower case. `Du` is a syntax error.
- An unknown reading is an error. The search does not return an empty result
  for it.

### 2.2 Regular-expression patterns: `/…/`

A regular expression (PostgreSQL syntax) between slashes is matched against all
readings. The query adds `^` at the start and an optional index plus `$` at the
end:

```
/du/        becomes  ^(du)([0-9]+|x)?$     →  du, du2, du3, …, dux
/[bp]a/     →  ba, pa and all of their indices
/.*ĝ.*/     any reading that contains ĝ
```

The pattern cannot contain `/`. Each pattern creates a wildcard (see section 9),
so the result shows which reading actually matched.

### 2.3 Signs

Upper case between vertical bars matches a sign, whatever reading it was
given in the text. All variants of that sign match. A sign can be identified
by any one of its values or specific forms:

```
|ENSI2|        the sign ENSI2, identified by a reading
|PA.TE.SI|     the sign ENSI2, identified by a specific form
```

Inside the bars `.` separates the parts of a glyph sequence (`PA.TE.SI`).

### 2.4 Graphemes and glyphs

Upper case without bars, such as `KA` matches a grapheme or glyph. It does not depend
on what sign it is understood to belong to, and allographs of each grapheme also match.

Graphemes and glyphs are identified by any reading for which they are a specific spelling.

Complex glyphs can be derived from simple ones using:
- Glyph operators: `×` (also typed as `x` between two names), `+`, `%`, `&`, `@`.
- Modifiers, which follow a name or a parenthesised group: `@t @g @š @n @k @z @i
  @c @d @f @v @a @b @x @180 @90 @45`. More than one is allowed.
- Parentheses: `(PA.TE)@g`, `KA×(A.IGI)`.

A `.` outside bars is a separator (see 3.2), so `PA.TE.SI` is the same query as
`PA-TE-SI`: three graphemes in one word. Write `|PA.TE.SI|` or `|ENSI2|` for the single sign.

Glyphs can also be identified by signlist references, e.g. `LAK123`.

Complex glyph descriptions and signlist references only match glyphs, not graphemes.

### 2.5 Wildcards for single units

| syntax | matches |
|--------|---------|
| `x` | any (possibly damaged) sign that is not a number |
| `X` | any (possibly damaged) glyph that is not part of a number |
| `n` or `N` | any (possibly damaged) number |

### 2.6 Form specification: `(…)` after a unit

A form specification in parentheses restricts the form of a unit:

```
du(GIN)        the reading du, written with the glyph GIN
/ša.*/(NI)     a reading matching ša…, written with the glyph NI
|ENSI2|(PA.TE) the sign ENSI2, written with the glyph sequence PA.TE
SU(ZU)         the grapheme SU, written with the glyph ZU
x(KA×A)        any sign written with the glyph KA×A
```

No space is allowed between the sign and `(`. With a space, `(…)` is 
parsed as a capture group.

`n` and `N` do not accept a specification.

### 2.7 ASCII substitutes

Before parsing, the following letters are replaced everywhere (including inside 
regular expressions) except directly after `@` or before three digits:

| typed | becomes |
|-------|---------|
| `c` / `C` | `š` / `Š` |
| `j` / `J` | `ĝ` / `Ĝ` |
| `v` / `V` | `ř` / `Ř` |

This means `jen` is the same query as `ĝen`, and `cu` is the same query as `šu`.
Modifiers keep their letters, so `@v` stays `@v`, as do signlist references (`RECXXX`).

---

## 3. Separators

Two adjacent units must always be separated by at least one separator. Several
separator symbols can be combined into one separator, and all of their
conditions then apply.

### 3.1 Plain adjacency

| syntax | meaning |
|--------|---------|
| space (or tab) | the second unit follows the first **immediately**. Word, compound and line boundaries between them are irrelevant. |

`du ĝen` finds `du-ĝen`, `du ĝen` and `du` at the end of one line with `ĝen` at
the start of the next.

### 3.2 Connectors

| syntax | meaning |
|--------|---------|
| `--` | immediately adjacent **and in the same compound** |
| `-` or `.` | immediately adjacent **and in the same word** |

Connectors do not allow surrounding spaces: `du-ĝen` is valid, `du - ĝen` is not.

### 3.3 Breaks

| syntax | meaning |
|--------|---------|
| `;;` | immediately adjacent, **but in different compounds** |
| `;` | immediately adjacent, **but in different words** |
| `//` | immediately adjacent, **but in different lines** |

Breaks can be combined with each other and with spaces: `du ;ĝen`, `du; ĝen`
and `du ;;;// ĝen` (all three boundaries) are valid.

### 3.4 Distance operators

| syntax | meaning |
|--------|---------|
| `…` or `...` | the second unit comes **anywhere after** the first in the same text, at any distance, across any boundaries |
| `:` | the units joined by `:` form a contiguous block **in any order** |

`lugal … e2` finds `e2` anywhere after `lugal`.

`du : ĝen : e2` finds the three signs as one contiguous run in any order.
Contiguity is checked on sign components, so the block cannot contain any other
sign. The block ends at the first separator that is not `:`. The next separator
then applies to the end of the whole block: in `du:ĝen lugal`, `lugal` must
follow the block immediately.

`:` and `…` cannot appear in the same separator (`du :… ĝen` is a syntax error).
They can appear in neighbouring separators (`du : ĝen … e2`).

### 3.5 Combining separators

| combination | allowed | meaning |
|---|---|---|
| `-`/`.` with `//`, `…`, `:` | yes | e.g. `du-//ĝen`: same word, split across a line; `du…-ĝen`: later in the same word |
| `--` with `//`, `…`, `:` | yes | same compound, plus that condition |
| `--` with `;` | yes | same compound, different word |
| `-` with `;;` or `;` | no | syntax error (contradictory) |
| `--` with `;;` | no | syntax error |
| `-` with `--` | no | syntax error (`-` already implies the same compound) |

### 3.6 Boundary anchors at the start or end of a query

A break (`;` `;;` `//`) can be placed at the very beginning or end of the query,
with no space between it and the unit. It then anchors the match to a boundary:

```
;lugal       lugal at the start of a word
lugal;       lugal at the end of a word
;lugal;      lugal as a whole word
;;dumu       dumu at the start of a compound
//a          a at the start of a line
```

Internally a pseudo-unit is inserted that matches either the preceding or
following sign or the virtual beginning or end of the text. This means an anchor
also matches at the start or end of a transliteration. Pseudo-units are not part
of the highlighted match.

Spaces, `…` and `:` cannot be used as anchors (`du //`, `…du` and `du…` are
syntax errors).

---

## 4. Determinatives and phonetic complements

### 4.1 Determinatives: `{…}`

```
{d}en-lil2      d as a determinative before en
lugal{d}        d as a determinative following lugal
{d}             d as a determinative in any position
{d-lugal}       several units inside one indicator, with separators as usual
{|DINGIR|}x     any kind of unit is allowed inside braces
```

- `{…}` placed directly before a unit, without a separator, matches a
  determinative that precedes and refers to that unit (indicator type *right*).
- `{…}` placed directly after a unit matches a determinative that follows that
  unit (indicator type *left*).
- `{…}` that stands alone (separated by a space or other separator) matches the
  unit as a determinative in either direction.

Several indicators can be stacked: `{d}{d}du`, `du{d}{d}`.

### 4.2 Phonetic complements: `<…>`

`<…>` works like `{…}`, but matches phonographic indicators (phonetic
complements) instead of semantic ones:

```
<a>du         phonetic complement a before du
du<a>         phonetic complement a after du
```

### 4.3 Separators between indicator and unit

An indicator is attached to a unit only when nothing separates the two. Any
separator, such as `{d} lugal`, `{d};lugal` or `{d}…lugal`, detaches it. The
indicator then matches in either direction (as in a standalone `{d}`), and the
separator has its usual meaning. An indicator cannot be attached in both directions.
Standalone indicators cannot be attached to each other.

---

## 5. Capture groups: `( … )`

Parentheses group units and create a capture group:

```
(du ĝen) … e2
lugal (x x) e2
```

The content of a group is a full sub-query. A group behaves like a single unit
with respect to the separators around it. Each group creates an *explicit*
wildcard (see section 9), which the replace functions reference as `"1"`,
`"2"`, … in the replacement string:

```
replace('(NI) (NI)', '"2" "1"', …)     swap two NI
replace('sa12-(rig7)', 'sag-"1"', …)
```

Groups can be nested: `(ĝen (DU))`. A group is distinguished from a form
specification by a separator in front of it: `ĝen (DU)` is a value followed by a
group, while `ĝen(DU)` is a value with a form specification.

---

## 6. Alternatives: `|`

`|` between units means "either side":

```
a|e              a or e
(a|e)-ĝu10       a or e, followed by ĝu10 in the same word
(du ĝen)|e2      the sequence du ĝen, or e2
```

**Precedence.** `|` has the lowest precedence within its enclosing group or the 
whole query. It separates everything to its left from everything to its right:

```
du|ĝen e2        =  (du)|(ĝen e2)
du e2|ĝen        =  (du e2)|(ĝen)
```

Always use parentheses to make the scope explicit: `(du|ĝen) e2`. Leaving out the
parentheses is technically valid, but can have surprising results: `;du|ĝen` resolves 
to `;du` or `ĝen`, `[du|ĝen]` to `[du` or `ĝen]` (which is a syntax error).

Parenthesised groups inside an alternative are not capture groups, and the 
alternative removes the wildcards of its members (see section 9). A group
that *contains* an alternative, such as `(du|ĝen) e2`, is a capture group.
Alternatives may contain line groups (`[…]|[…]`), except inside a line group.

A sign name in bars can directly follow `|`: `a||LUGAL|` is valid, but
`a|(|LUGAL|)` is easier to read.

---

## 7. Line groups: `[ … ]`

Square brackets require all units inside them to be on **the same line**:

```
[lugal … e2]       lugal and later e2, both on one line
[(du ĝen)] e2      a capture group inside a line group
```

Line groups cannot be nested. Inside a line group, alternatives cannot contain
other line groups. A `//` separator inside a line group can never match.

---

## 8. Excluding units from the match: `*`

A `*` placed directly before a unit or group means: the unit must be present for 
the query to match, but it is **not** part of the reported match. It is excluded
from `sign_nos`, `word_nos` and `line_nos`, so it is not highlighted or
replaced. This is useful for context:

```
lugal *e2           lugal, but only where e2 follows it; only lugal is reported
{*d}en-lil2         match the determinative, but do not report it
*(gu3-de2-a) ensi2  match ensi2, but only after gu3-de2-a
```

---

## 9. Wildcards and capture groups

Besides the matching rows, the search returns a `wildcards` array of
`(wildcard_id, sign_nos)` pairs. These record which signs matched each
non-literal part of the query. `preparse_search` returns the matching labels.

A wildcard is created for:

| query part | label |
|---|---|
| each capture group `( … )` | the group's content, e.g. `du ĝen` (*explicit*) |
| each ambiguous reading (more than one sign-list entry) | the reading, e.g. `ax` |
| each sign `\|…\|` | the identifier, e.g. `LUGAL` |
| each grapheme/glyph | the identifier, e.g. `KA×A` |
| each pattern | the pattern, e.g. `/du/` |
| each `x`, `X`, `n` | `x`, `X`, `n`; `x(KA×A)` with a specification |

Rules:

- Identical labels are numbered from left to right: `A A` gives `A[1]`, `A[2]`.
- A capture group that contains only a single wildcard and has the same label
  produces one wildcard, not two (`(ax)` gives a single `ax`).
- Wildcards inside an alternative are dropped.
- Every wildcard that `preparse_search` returns is present in the search
  result. Its `sign_nos` are empty if it contains no reported signs, e.g. for
  a unit or group marked with `*` (see section 8).
- `wildcards_explicit` lists the indices of the wildcards that come from capture
  groups. `replace` uses these indices for its `"1"`, `"2"`, … references.

---

## 10. Intermediate code (developer reference)

`preparse_search` outputs a compact string that `parse_search` consumes
(`grammar.lark`). It is not meant to be typed by users, but it can be passed to
`parse_search` directly.

### 10.1 Sign specs

| code | condition |
|---|---|
| `v<id>` | `value_id = id` |
| `s<id>` | `sign and form_id = id` |
| `S<id>` | `sign and meaning_id = id` |
| `g<id>` | `NOT sign and meaning_id = id` |
| `c<id>` | `NOT sign and form_id = id` |
| `x` | `sign AND NOT type = 'number'` |
| `X` | `NOT sign` |
| `n` | `sign AND type = 'number'` |
| `p` | pseudo-sign, `sign IS DISTINCT FROM FALSE` (start/end of text or a sign's value row) |

Several specs in a row are joined with AND: `v12s34` means value 12 written with
sign variant 34.

An indicator is `[<|>](D|P)spec+`. `D` is a determinative (`phonographic =
false`) and `P` a phonetic complement (`phonographic = true`). `>` means it
precedes its base (`indicator_type = 'right'`), `<` that it follows its base
(`'left'`), and no prefix means any (`!= 'none'`).

`*` before a char excludes it from the reported match. `@<n>` after a char or a
group assigns wildcard `n`.

### 10.2 Separators

| code | user syntax | condition between neighbours |
|---|---|---|
| ` ` | space | `next(a) = b` |
| `--` | `--` | + same `compound_no` |
| `-` | `-` `.` | + same `word_no` |
| `;;` | `;;` | + different `compound_no` |
| `;` | `;` | + different `word_no` |
| `//` | `//` | + different `line_no` |
| `…` | `…` `...` | `next(a) <= b` instead of `next(a) = b` |
| `:` | `:` | the members are tested together with `consecutive(…)` |
| `\|` | `\|` | alternative |

### 10.3 Rows

Each corpus sign is indexed as one sign row (component 0, `sign = TRUE`, holding
`value_id` / `sign_id` as `meaning_id` / `sign_variant_id` as `form_id`) plus one row 
per grapheme/glyph (components 0…n−1, `sign = FALSE`, holding `grapheme_id` as `meaning_id` 
/ `glyph_id` as `form_id`). Additionally, each document gets a pseudo first and last 
row with `sign_no = NULL` and `position`, `word_no`, `compound_no` and `line_no` 
lower/higher than any other in the document and a dummy row with `position = NULL`.
`cun_position` packs `(sign_no, component_no, final)`.
`next()` advances to the next component, or to component 0 of the next sign
after a final component. As a result, readings, signs and forms can be mixed
freely in one sequence, and a form can span a sign boundary.
