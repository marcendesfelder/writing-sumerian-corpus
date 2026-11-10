from typing import List
from py2plpy import plpy, sql_properties

@sql_properties(volatility='immutable', cost=1000)
def parse_search(search_term:str, target_table:str, target_key:List[str], target_schema:str) -> str:
     
    import itertools
    from enum import Enum
    from lark import Lark, Transformer, v_args

    grammar = r"""
{{grammar}}  
    """


    class TokenType(Enum):
        CHAR = 1
        ELLIPSIS = 2
        COLON = 3
        WORDBREAK = 4
        COMPOUNDBREAK = 5
        LINEBREAK = 6
        LPAREN = 7
        RPAREN = 8
        BAR = 9
        WORDCON = 10
        COMPOUNDCON = 11
        WC = 12
        LBRACKET = 13
        RBRACKET = 14
        PSEUDO = 15


    class Token:
        def __init__(self, type):
            self.type = type


    class Wildcard(Token):
        def __init__(self, id):
            self.type = TokenType.WC
            self.id = id


    class Char(Token):
        def __init__(self, id, condition, pseudo=False):
            self.type = TokenType.PSEUDO if pseudo else TokenType.CHAR
            self.id = id
            self.condition = condition
            self.matched = True


    class T(Transformer):

        def __init__(self):
            self.id = 0

        def __default_token__(self, token):
            return token.value

        def start(self, args):
            res = []
            for arg in args:
                res += arg
            return res 

        def line(self, args):
            return [Token(TokenType.LBRACKET)] + list(itertools.chain.from_iterable(args)) + [Token(TokenType.RBRACKET)]

        def paren_asterisk(self, args):
            res = []
            for arg in args:
                for c in arg:
                    if c.type == TokenType.CHAR:
                        c.matched = False
                    res.append(c)
            return res

        def paren(self, args):
            return [Token(TokenType.LPAREN)] + list(itertools.chain.from_iterable(args[:-1])) + [Token(TokenType.RPAREN)] + ([Wildcard(args[-1])] if args[-1] is not None else [])

        def char_asterisk(self, args):
            args[0][0].matched = False
            return args[0]

        def char(self, args):
            self.id += 1
            return [Char(self.id, ' AND '.join(args[:-1]).format(table = f'c{self.id}'))] + ([Wildcard(args[-1])] if args[-1] is not None else [])

        @v_args(inline=True)
        def pseudo(self):
            self.id += 1
            return [Char(self.id, f'c{self.id}.sign IS DISTINCT FROM FALSE', True)]

        @v_args(inline=True)
        def indicator(self, alignment, indic_type, *specs):
            spec = ' AND '.join(specs)
            if alignment == '>':
                spec += " AND {table}.indicator_type = 'right'"
            elif alignment == '<':
                spec += " AND {table}.indicator_type = 'left'"
            else:
                spec += " AND {table}.indicator_type != 'none'"

            if indic_type == 'D':
                spec += " AND {table}.phonographic = false"
            else:
                spec += " AND {table}.phonographic = true"
            return spec

        @v_args(inline=True)
        def value(self, id):
            return f'{{table}}.value_id = {id}'
        
        @v_args(inline=True)
        def sign(self, id):
            return f'{{table}}.sign AND {{table}}.meaning_id = {id}'

        @v_args(inline=True)
        def sign_variant(self, id):
            return f'{{table}}.sign AND {{table}}.form_id = {id}'

        @v_args(inline=True)
        def grapheme(self, id):
            return f'NOT {{table}}.sign AND {{table}}.meaning_id = {id}'

        @v_args(inline=True)
        def glyph(self, id):
            return f'NOT {{table}}.sign AND {{table}}.form_id = {id}'

        @v_args(inline=True)
        def graphemex(self):
            return f'NOT {{table}}.sign'

        @v_args(inline=True)
        def signx(self):
            return f"{{table}}.sign AND {{table}}.type != 'number'"

        @v_args(inline=True)
        def numberx(self):
            return f"{{table}}.sign AND {{table}}.type = 'number'"


        def wordbreak(self, args):
            return [Token(TokenType.WORDBREAK)]

        def compoundbreak(self, args):
            return [Token(TokenType.COMPOUNDBREAK)]

        def linebreak(self, args):
            return [Token(TokenType.LINEBREAK)]

        def ellipsis(self, args):
            return [Token(TokenType.ELLIPSIS)]

        def colon(self, args):
            return [Token(TokenType.COLON)]

        def wordcon(self, args):
            return [Token(TokenType.WORDCON)]

        def compoundcon(self, args):
            return [Token(TokenType.COMPOUNDCON)]
        
        def bar(self, args):
            return [Token(TokenType.BAR)]

        def wildcard(self, args):
            return int(args[0])
        

    class Table:
        def __init__(self):
            self.ids = []
            self.matchIds = []
            self.maybePseudoIds = set()
            self.ops = []
            self.wildcard = None
            self.lineAnchor = None

        def list(self, column):
            return ', '.join(f"c{id}.{column}" for id in self.ids)


    class SingleTable(Table):
        def __init__(self, char):
            super().__init__()
            self.id = char.id
            self.ids.append(char.id)
            if char.type == TokenType.CHAR and char.matched:
                self.matchIds.append(char.id)
            self.condition = char.condition

        def first(self, column):
            return f"c{self.id}.{column}"

        def last(self, column):
            return f"c{self.id}.{column}"


    class DummyTable(Table):
        def __init__(self, id):
            super().__init__()
            self.id = id
            self.ids.append(id)
            self.maybePseudoIds = {id}
            self.condition = f"c{id}.position IS NULL"

    
    class ComplexTable(Table):
        def __init__(self, tables=[], unordered=False):
            super().__init__()
            self.tables = []
            self.end = -1
            for table in tables:
                self.append(table)
            self.unordered = unordered
            self.knownStart = not unordered
            self.knownEnd = not unordered

        def append(self, table):
            self.ids += table.ids
            self.matchIds += table.matchIds
            self.maybePseudoIds |= table.maybePseudoIds
            self.tables.append(table)
            if not isinstance(table, DummyTable):
                self.end += 1

        def first(self, column):
            if self.knownStart:
                return self.tables[0].first(column)
            return f"LEAST({self.list(column)})"

        def last(self, column):
            if self.knownEnd:
                return self.tables[self.end].last(column)
            return f"GREATEST({self.list(column)})"


    class AlternativeTable(Table):
        def __init__(self, table1, table2):
            super().__init__()
            self.ops = table2.ops
            # Ids are only shared between tables of the same reported status, as there is no way
            # to tell which branch matched. Unshared ids are padded with dummies in the other branch.
            matched1, unreported1 = AlternativeTable.partition(table1)
            matched2, unreported2 = AlternativeTable.partition(table2)
            idMap = dict(zip(matched2, matched1)) | dict(zip(unreported2, unreported1))
            AlternativeTable.replaceIds(table2, idMap)
            only1 = [id for id in table1.ids if id not in table2.ids]
            only2 = [id for id in table2.ids if id not in table1.ids]
            table1 = AlternativeTable.pad(table1, only2)
            table2 = AlternativeTable.pad(table2, only1)
            self.ids = list(table1.ids)
            self.matchIds = [id for id in self.ids if id in table1.matchIds or id in table2.matchIds]
            self.maybePseudoIds |= table1.maybePseudoIds | table2.maybePseudoIds
            self.tables = [table1, table2]

        def partition(table):
            matched = [id for id in table.ids if id in table.matchIds]
            unreported = [id for id in table.ids if id not in table.matchIds]
            return matched, unreported

        def pad(table, ids):
            if not ids:
                return table
            if not isinstance(table, ComplexTable):
                table = ComplexTable([table])
            for id in ids:
                table.append(DummyTable(id))
            return table

        def replaceIds(table, idMap):
            if isinstance(table, SingleTable) or isinstance(table, DummyTable):
                table.condition = table.condition.replace(f'c{table.id}.', f'c{idMap.get(table.id, table.id)}.')
                table.id = idMap.get(table.id, table.id)
            else:
                for t in table.tables:
                    AlternativeTable.replaceIds(t, idMap)
            table.ids = [idMap.get(id, id) for id in table.ids]
            table.matchIds = [idMap.get(id, id) for id in table.matchIds]
            if table.lineAnchor is not None:
                table.lineAnchor = [idMap.get(id, id) for id in table.lineAnchor]
            table.maybePseudoIds = {idMap.get(i, i) for i in table.maybePseudoIds}

        def first(self, column):
            a = self.tables[0].first(column)
            b = self.tables[1].first(column)
            return f"LEAST({a}, {b})" if a != b else a

        def last(self, column):
            a = self.tables[0].last(column)
            b = self.tables[1].last(column)
            return f"GREATEST({a}, {b})" if a != b else a



    class Translator:
        def __init__(self, tokens):
            self.table, _ = self.process(tokens)


        def processUnordered(tables):
            t = None
            res = []
            for table in tables:
                if TokenType.COLON in table.ops:
                    if not t:
                        t = ComplexTable(unordered=True)
                    t.append(table)
                else:
                    if t:
                        t.ops = table.ops
                        table.ops = []
                        t.append(table)
                        res.append(t)
                        t = None
                    else:
                        res.append(table)
            return res

        def processAlternative(tables):
            ixs = [i+1 for i, table in enumerate(tables) if TokenType.BAR in table.ops]
            if not ixs:
                return tables

            res = ComplexTable(tables[0:ixs[0]])
            for i, j in zip(ixs, ixs[1:]+[len(tables)]):
                res = AlternativeTable(res, ComplexTable(tables[i:j]))
            return [res]                                


        def join(table):
            conditions = []

            if table.lineAnchor is not None:
                if len(table.lineAnchor) == 1:
                    anchor = f"c{table.lineAnchor[0]}.line_no"
                else:
                    anchor = f"COALESCE({', '.join(f'c{id}.line_no' for id in table.lineAnchor)})"
                for id in table.ids:
                    if [id] != table.lineAnchor:
                        if id in table.maybePseudoIds:
                            conditions.append(f"COALESCE(c{id}.line_no = {anchor}, TRUE)")
                        else:
                            conditions.append(f"c{id}.line_no = {anchor}")

            if isinstance(table, SingleTable) or isinstance(table, DummyTable):
                return conditions + [table.condition]

            if isinstance(table, AlternativeTable):
                c1 = ' AND '.join(Translator.join(table.tables[0]))
                c2 = ' AND '.join(Translator.join(table.tables[1]))
                return conditions + [f"(({c1}) OR ({c2}))"]

            if table.unordered:
                conditions.append(f"@extschema@.consecutive({table.list('position')})")
            
            for a, b in zip(table.tables[:-1], table.tables[1:]):
                if isinstance(b, DummyTable):
                    continue
                if not table.unordered:
                    if TokenType.ELLIPSIS in a.ops:
                        conditions.append(f"@extschema@.next({a.last('position')}) OPERATOR(@extschema@.<=) {b.first('position')}")
                    else:
                        conditions.append(f"@extschema@.next({a.last('position')}) OPERATOR(@extschema@.=) {b.first('position')}")
                if TokenType.WORDCON in a.ops:
                    conditions.append(f"{a.last('word_no')} = {b.first('word_no')}")
                if TokenType.COMPOUNDCON in a.ops:
                    conditions.append(f"{a.last('compound_no')} = {b.first('compound_no')}")
                if TokenType.WORDBREAK in a.ops:
                    conditions.append(f"{a.last('word_no')} != {b.first('word_no')}")
                if TokenType.COMPOUNDBREAK in a.ops:
                    conditions.append(f"{a.last('compound_no')} != {b.first('compound_no')}")
                if TokenType.LINEBREAK in a.ops:
                    conditions.append(f"{a.last('line_no')} != {b.first('line_no')}")

            for table in table.tables:
                conditions += Translator.join(table)

            return conditions


        def anchorLine(tables):
            # Anchor at a table that is never a dummy. If there is none (e.g. an alternative whose
            # branches share no ids), anchor at the first non-null line_no among all tables instead.
            ids = [id for table in tables for id in table.ids]
            maybePseudoIds = set().union(*(table.maybePseudoIds for table in tables))
            anchor = next(([id] for id in ids if id not in maybePseudoIds), ids)
            for table in tables:
                table.lineAnchor = anchor


        def process(self, tokens):
            tables = []
            ops = []
            lineTables = None
            i = 0
            while i < len(tokens):
                if tokens[i].type in [TokenType.CHAR, TokenType.PSEUDO, TokenType.LPAREN]:
                    if len(tables):
                        tables[-1].ops = ops
                        ops = []
                    if tokens[i].type == TokenType.CHAR or tokens[i].type == TokenType.PSEUDO:
                        tables.append(SingleTable(tokens[i]))
                    else:
                        t, n = self.process(tokens[i+1:])
                        tables.append(t)
                        i += n
                    if lineTables is not None:
                        lineTables.append(tables[-1])

                elif tokens[i].type == TokenType.RPAREN:
                    break
                elif tokens[i].type == TokenType.WC:
                    tables[-1].wildcard = tokens[i].id
                elif tokens[i].type == TokenType.LBRACKET:
                    lineTables = []
                elif tokens[i].type == TokenType.RBRACKET:
                    Translator.anchorLine(lineTables)
                    lineTables = None
                else:
                    ops.append(tokens[i].type)
                i += 1

            tables = Translator.processUnordered(tables)
            tables = Translator.processAlternative(tables)
            return ComplexTable(tables), i+1


        def wildcards(self, table):
            wildcards = {table.wildcard: table.matchIds} if table.wildcard is not None else {}
            if isinstance(table, ComplexTable) or isinstance(table, AlternativeTable):
                for table in table.tables:
                    wildcards.update(self.wildcards(table))
            return wildcards


        def translateWildcards(self):
            wildcards = self.wildcards(self.table)
            wildcards = [(wc, ', '.join(f"c{id}.sign_no" for id in signNos)) for wc, signNos in wildcards.items()]
            return 'ARRAY['+', '.join(f"({wc}, @extschema@.sort_uniq_remove_null({signNos}))" for wc, signNos in wildcards)+']::@extschema@.search_wildcard[]'


        def translate(self, targetTable, targetKey, targetSchema):
            conditions = Translator.join(self.table)
            for col in targetKey:
                for id in self.table.ids[1:]:
                    conditions.append(f"c{self.table.ids[0]}.{col} = c{id}.{col}")

            fromClause = ', '.join(f"{plpy.quote_ident(targetSchema)}.{plpy.quote_ident(targetTable)} c{id}" for id in self.table.ids)
            whereClause = ' AND '.join(conditions)
            keyCols = ', '.join(f"c{self.table.ids[0]}.{plpy.quote_ident(col)}" for col in targetKey)
            matchClause = '@extschema@.sort_uniq_remove_null('+', '.join(f"c{id}.sign_no" for id in self.table.matchIds)+')'
            wordMatchClause = '@extschema@.sort_uniq_remove_null('+', '.join(f"c{id}.word_no" for id in self.table.matchIds)+')'
            lineMatchClause = '@extschema@.sort_uniq_remove_null('+', '.join(f"c{id}.line_no" for id in self.table.matchIds)+')'
            wildcardClause = self.translateWildcards()

            return f'SELECT DISTINCT {keyCols}, {matchClause} AS signs, {wordMatchClause} AS words, {lineMatchClause} AS lines, {wildcardClause} AS wildcards FROM {fromClause} WHERE {whereClause}'


    if 'parser' not in SD:
        SD['parser'] = Lark(grammar, lexer='basic', maybe_placeholders=True)
    l = SD['parser']
    #try:
    tree = l.parse(search_term)
    tokens = T().transform(tree)
    #except:
    #    return f"SELECT {', '.join(target_key)}, ARRAY[]::integer[] AS signs FROM {target_table} WHERE FALSE"

    translator = Translator(tokens)


    return translator.translate(target_table, target_key, target_schema)

    

    

    

    


