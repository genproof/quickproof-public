"""tools/clight_audit.py: the audit of a law's cone on the generated Clight (`tools/qp audit`, the lint of
`tools/qp lint` and `check`, and the cone check of `tools/qp import-fuzz`).

The cone of a law is every function with a body reachable from the harness's `main` -- a call, or a
function's address taken (an Evar of function type), also through the initialiser of a global variable -- over the
library units and that law's own harness unit (each law is its own program).

Two kinds of results:
  - BLOCKERS: constructs that VST 2.15 cannot prove or that are undefined in CompCert's semantics whatever the
    values, so a contract whose cone contains one is not provable: a switch whose scrutinee is not an int (VST's
    only switch rule needs is_int_type: a switch on a long/size_t is provable only under a False precondition),
    goto and labels, struct assignment, struct parameters and results, builtins, external functions outside the
    framework's environment, memcpy/memmove/memcmp of memory whose type holds a pointer (a stored pointer read
    byte by byte is Vundef in CompCert: the copy is stuck), and conversions between pointers and integers (below);
  - REVIEW items, counted per function: constructs that are fine on some values only (pointer arithmetic: not on
    NULL for VST; ordering comparisons: one object; equality: valid pointers or NULL; signed arithmetic: no
    overflow; division; shifts; narrowing casts; memset of pointer-holding memory), or only where the function's
    precondition is False (a volatile access, as in a deliberate crash path).

Conversions between pointers and integers (cast_hits; VST 2.15 veric/expr.v isCastResultType, x86_64): a pointer
converted to a 64-bit integer (`cast_case_pointer`) typechecks only when it is NULL (tc_iszero); to a narrower integer
(`cast_case_l2i`) never, not even NULL (and CompCert's cast is stuck on a pointer); an integer converted to a pointer
only when it is 0.  So, explicit (Ecast) or implicit (the conversion of an assignment, a return or a call argument):
  - BLOCKER: a pointer-to-integer cast (not to _Bool: that is a comparison with NULL); an integer-to-pointer cast of a
    value derived from a pointer (a pointer-to-integer cast, through integer arithmetic and the function's temporaries
    and local variables, such as `(void *)((size_t)p)`); an integer-to-pointer cast of a
    non-zero constant;
  - review instead when provably harmless: the pointer is provably NULL (a null constant, or a temporary that the
    enclosing `if` compares with NULL and the branch never reassigns), for a cast to a 64-bit integer; or the cast is
    in dead code (a branch of a constant condition, e.g. `sizeof(void *) == 4`, or after a return/break/continue);
  - review: an integer-to-pointer cast of any other integer (provable only for 0).
"""
import collections
import os
import re

ENV = {'quickproof_malloc', 'quickproof_free', 'gp_assert', 'gp_assume', 'nondet_u8', 'nondet_u32', 'nondet_size',
       'nondet_bytes'}
COPIES = ('memcpy', 'memmove', 'memcmp', 'memset')
INT_TYPES = ('tint', 'tuint', 'tschar', 'tuchar', 'tshort', 'tushort', 'tbool')   # Tint of any size: is_int_type
BLOCKER = 'BLOCKER'
REVIEW = 'review'


def tokenize(s):
    return re.findall(r'\(|\)|"[^"]*"|[^\s()]+', s)


def parse(tokens, i=0):
    out = []
    while i < len(tokens):
        t = tokens[i]
        if t == '(':
            sub, i = parse(tokens, i + 1)
            out.append(sub)
        elif t == ')':
            return out, i + 1
        else:
            out.append(t)
            i += 1
    return out, i


def show(e):
    return '(' + ' '.join(show(x) for x in e) + ')' if isinstance(e, list) else e


def typ(e):     # a Clight expression's type is its last component
    return show(e[-1]) if isinstance(e, list) and e else '?'


def isptr(t):
    return t.startswith('(tptr') or t.startswith('(tarray')


def is_null(e):
    """A null pointer constant: (Ecast (Econst_int/long (Int.repr 0) ..) ..), possibly nested casts."""
    while isinstance(e, list) and e and e[0] == 'Ecast':
        e = e[1]
    return isinstance(e, list) and e and e[0] in ('Econst_int', 'Econst_long') and show(e[1]) in (
        '(Int.repr 0)', '(Int64.repr 0)')


def load(paths):
    """funcs: name -> (code.v path, body); gvars: name -> body; comps: name -> [member type texts]."""
    funcs, gvars, comps = {}, {}, {}
    for path in paths:
        s = open(path).read()
        for fn, body in re.findall(r'Definition f_(\w+) := \{\|(.*?)\|\}\.', s, re.S):
            funcs[fn] = (path, body)
        for v, body in re.findall(r'Definition v_(\w+) := \{\|(.*?)\|\}\.', s, re.S):
            gvars[v] = body
        m = re.search(r'Definition composites : list composite_definition :=(.*?)\.\n', s, re.S)
        if m:
            for name, members in re.findall(r'Composite (_\w+) (?:Struct|Union)\s*\((.*?)\)\s*noattr', m.group(1), re.S):
                comps[name] = re.findall(r'Member_plain _\w+ (.*?)(?= ::|$)', members.replace('\n', ' '))
    return funcs, gvars, comps


def pointer_holding(comps):
    """Composite names whose objects hold a pointer (a member of pointer type, also inside arrays and members)."""
    holds = set()
    changed = True
    while changed:
        changed = False
        for c, members in comps.items():
            if c in holds:
                continue
            for t in members:
                if 'tptr' in t or any(re.search(r'\b(?:Tstruct|Tunion) %s\b' % re.escape(h), t) for h in holds):
                    holds.add(c)
                    changed = True
                    break
    return holds


def type_holds_pointer(t, holds):
    if 'tptr' in t:
        return True
    return any(re.search(r'\b(?:Tstruct|Tunion) %s\b' % re.escape(h), t) for h in holds)


def refs(text):
    local = set()
    m = re.search(r'fn_vars :=(.*?);\s*fn_temps', text, re.S)
    if m:
        local = set(re.findall(r'\(_(\w+),', m.group(1)))
    return (set(re.findall(r'\(Evar _(\w+)', text)) - local) | set(re.findall(r'Init_addrof _(\w+)', text))


def cone(funcs, gvars, root='main'):
    """(functions with a body reachable from root, external names reached)."""
    seen, seen_v, todo, externals = set(), set(), [root], set()
    while todo:
        x = todo.pop()
        if x in funcs:
            if x not in seen:
                seen.add(x)
                todo.extend(refs(funcs[x][1]))
        elif x in gvars:
            if x not in seen_v:
                seen_v.add(x)
                todo.extend(refs(gvars[x]))
        else:
            externals.add(x)
    return seen, externals


# ---------------------------------------------------------------------------------------------------------------
# Conversions between pointers and integers (see the module's docstring)
# ---------------------------------------------------------------------------------------------------------------

INTEGER = ('tint', 'tuint', 'tschar', 'tuchar', 'tshort', 'tushort', 'tlong', 'tulong')   # not tbool
STATEMENT_ENDS = ('Sreturn', 'Sbreak', 'Scontinue', 'Sgoto')
SCALAR_SIZE = {'tbool': 1, 'tschar': 1, 'tuchar': 1, 'tshort': 2, 'tushort': 2, 'tint': 4, 'tuint': 4, 'tlong': 8,
               'tulong': 8, 'tfloat': 4, 'tdouble': 8}


def is_pointer_type(t):          # pointer, array and function designators all convert as pointers
    return t.startswith(('(tptr', '(tarray', '(Tpointer', '(Tarray', '(Tfunction'))


def is_integer_type(t):
    return t in INTEGER or (t.startswith(('(Tint ', '(Tlong ')) and 'IBool' not in t)


def is_long_type(t):
    return t in ('tlong', 'tulong') or t.startswith('(Tlong ')


def const_value(e, env=None):
    """The value of a constant integer expression (approximate arithmetic, enough to decide a branch), or None.
    env: temporaries known constant ({name: value}, program_constants)."""
    if not isinstance(e, list) or not e:
        return None
    h = e[0]
    if h == 'Etempvar' and len(e) >= 2 and env and e[1] in env:
        return env[e[1]]
    if h in ('Econst_int', 'Econst_long') and len(e) >= 2:
        m = re.match(r'^\(Int(?:64)?\.repr \(?(-?\d+)\)?\)$', show(e[1]))
        return int(m.group(1)) if m else None
    if h == 'Esizeof' and len(e) >= 2:
        t = show(e[1])
        return 8 if t.startswith(('(tptr', '(Tpointer')) else SCALAR_SIZE.get(t)
    if h == 'Ecast' and len(e) >= 3:
        v = const_value(e[1], env)
        return None if v is None else (int(v != 0) if show(e[2]) == 'tbool' else v)
    if h == 'Eunop' and len(e) >= 3:
        v = const_value(e[2], env)
        return None if v is None else {'Onotbool': int(v == 0), 'Oneg': -v}.get(e[1])
    if h == 'Ebinop' and len(e) >= 4:
        a, b = const_value(e[2], env), const_value(e[3], env)
        if a is None or b is None:
            return None
        ops = {'Oeq': lambda: int(a == b), 'One': lambda: int(a != b), 'Olt': lambda: int(a < b),
               'Ogt': lambda: int(a > b), 'Ole': lambda: int(a <= b), 'Oge': lambda: int(a >= b),
               'Oadd': lambda: a + b, 'Osub': lambda: a - b, 'Omul': lambda: a * b,
               'Oand': lambda: a & b, 'Oor': lambda: a | b}
        return ops[e[1]]() if e[1] in ops else None
    return None


def ends(s, env=None):
    """The statement never completes normally (control leaves by return, break, continue or goto)."""
    if not isinstance(s, list) or not s:
        return False
    h = s[0]
    if h in STATEMENT_ENDS:
        return True
    if h == 'Ssequence' and len(s) >= 3:
        return ends(s[1], env) or ends(s[2], env)
    if h == 'Slabel' and len(s) >= 3:
        return ends(s[2], env)
    if h == 'Sifthenelse' and len(s) >= 4:
        v = const_value(s[1], env)
        return ends(s[2], env) if v not in (None, 0) else ends(s[3], env) if v == 0 else ends(s[2], env) and ends(s[3], env)
    return False


def children(e):
    """The sub-terms of a parsed term: all but its head constructor (a list of terms, e.g. the top of a body, has none)."""
    return e[1:] if e and isinstance(e[0], str) else e


def contains(e, head):
    return isinstance(e, list) and bool(e) and (e[0] == head or any(contains(x, head) for x in children(e)))


def assigned_temps(s):
    """The temporaries a statement assigns (Sset, and the result of Scall/Sbuiltin)."""
    out = set()
    if isinstance(s, list) and s:
        if s[0] == 'Sset' and len(s) >= 2:
            out.add(s[1])
        if s[0] in ('Scall', 'Sbuiltin') and len(s) >= 2 and isinstance(s[1], list) and s[1][:1] == ['Some']:
            out.add(s[1][1])
        for x in children(s):
            out |= assigned_temps(x)
    return out


def null_temps(cond):
    """(temporaries NULL in the then branch, in the else branch) of an `if` on this condition."""
    def temp(e):
        return e[1] if isinstance(e, list) and len(e) >= 3 and e[0] == 'Etempvar' and is_pointer_type(typ(e)) else None
    if isinstance(cond, list) and cond:
        if cond[0] == 'Etempvar' and temp(cond):
            return set(), {cond[1]}
        if cond[0] == 'Eunop' and len(cond) >= 3 and cond[1] == 'Onotbool' and temp(cond[2]):
            return {cond[2][1]}, set()
        if cond[0] == 'Ebinop' and len(cond) >= 4 and cond[1] in ('Oeq', 'One'):
            a, b = cond[2], cond[3]
            t = temp(a) if is_null(b) else temp(b) if is_null(a) else None
            if t:
                return ({t}, set()) if cond[1] == 'Oeq' else (set(), {t})
    return set(), set()


def pointer_derived(e, tainted):
    """An integer expression whose value comes from a pointer: a pointer-to-integer cast (not of a null constant),
    through integer arithmetic, casts, and the temporaries/local variables in `tainted`."""
    if not isinstance(e, list) or not e:
        return False
    h = e[0]
    if h == 'Ecast' and len(e) >= 3:
        if is_pointer_type(typ(e[1])):
            return not is_null(e[1]) and is_integer_type(show(e[2]))
        return pointer_derived(e[1], tainted)
    if h in ('Etempvar', 'Evar') and len(e) >= 3:
        return e[1] in tainted and is_integer_type(typ(e))
    if h == 'Ebinop' and len(e) >= 4 and e[1] in ('Oadd', 'Osub', 'Omul', 'Oand', 'Oor', 'Oxor', 'Oshl', 'Oshr',
                                                   'Odiv', 'Omod'):
        return pointer_derived(e[2], tainted) or pointer_derived(e[3], tainted)
    if h == 'Eunop' and len(e) >= 3 and e[1] in ('Onotint', 'Oneg'):
        return pointer_derived(e[2], tainted)
    return False


def derived_variables(tree):
    """The temporaries and local variables that hold a pointer-derived integer somewhere in the function (flow
    insensitive, to a fixpoint)."""
    tainted = set()
    assigns = []

    def collect(s):
        if isinstance(s, list) and s:
            if s[0] == 'Sset' and len(s) >= 3:
                assigns.append((s[1], s[2]))
            elif s[0] == 'Sassign' and len(s) >= 3 and isinstance(s[1], list) and s[1][:1] == ['Evar']:
                assigns.append((s[1][1], s[2]))
            for x in children(s):
                collect(x)
    collect(tree)
    changed = True
    while changed:
        changed = False
        for x, e in assigns:
            if x not in tainted and pointer_derived(e, tainted):
                tainted.add(x)
                changed = True
    return tainted


def param_types(fn_type):
    """The parameter types of a Tfunction type text (clightgen prints the list as `(t1 :: t2 :: nil)` or as
    `(Tcons t1 (Tcons t2 Tnil))`)."""
    e = parse(tokenize(fn_type))[0]
    e = e[0] if e and isinstance(e[0], list) else e
    if isinstance(e, list) and len(e) >= 2 and e[0] in ('tptr', 'Tpointer'):     # a call through a function pointer
        e = e[1]
    if not (isinstance(e, list) and len(e) >= 2 and e[0] == 'Tfunction'):
        return []
    args, out = e[1], []
    if isinstance(args, list) and '::' in args:
        cur = []
        for x in args:
            if x == '::':
                out.append(show(cur[0]) if len(cur) == 1 else show(cur))
                cur = []
            elif x != 'nil':
                cur.append(x)
        return out
    while isinstance(args, list) and args[:1] == ['Tcons'] and len(args) >= 3:
        out.append(show(args[1]))
        args = args[2]
    return out


def arguments(lst):
    """The expressions of a Clight argument list `(e1 :: e2 :: nil)` (or `(Econs e1 (Econs e2 Enil))`)."""
    if not isinstance(lst, list):
        return []
    if lst[:1] == ['Econs']:
        out = []
        while isinstance(lst, list) and lst[:1] == ['Econs'] and len(lst) >= 3:
            out.append(lst[1])
            lst = lst[2]
        return out
    return [x for x in lst if isinstance(x, list)]


def subterms(e, head):
    """The sub-terms of e (e included) whose head is `head`."""
    if not isinstance(e, list) or not e:
        return
    if e[0] == head:
        yield e
    for x in children(e):
        yield from subterms(x, head)


def program_constants(trees, params, gvars):
    """{function: {temporary: value}} over a law's cone (trees: function name -> parsed body, params: function name ->
    its parameter identifiers): the parameters that every call site passes the same constant (no reassignment, the function's
    address never taken), and the temporaries whose every assignment is that constant, also through the result of
    a function whose every return is one constant (LZ4_initStream's LZ4_isAligned(buffer, LZ4_stream_t_alignment()),
    alignment 1 with LZ4_ALIGN_TEST=0).  Callers outside the cone never run in the law's program."""
    calls, taken = {}, set()
    for f, t in trees.items():
        callees = [c[2] for c in subterms(t, 'Scall') if len(c) >= 4]
        direct = collections.Counter(id(c) for c in callees if isinstance(c, list) and c[:1] == ['Evar'])
        for v in subterms(t, 'Evar'):
            if len(v) >= 3 and show(v[-1]).startswith('(Tfunction') and id(v) not in direct:
                taken.add(v[1][1:])
        for c in subterms(t, 'Scall'):
            if len(c) >= 4 and isinstance(c[2], list) and c[2][:1] == ['Evar']:
                calls.setdefault(c[2][1][1:], []).append((f, arguments(c[3])))
    for body in gvars.values():
        taken |= set(re.findall(r'Init_addrof _(\w+)', body))
    env = {f: {} for f in trees}
    returns = {}
    for _ in range(8):
        new = {}
        for f, t in trees.items():
            assigned = collections.defaultdict(set)
            for x in subterms(t, 'Sset'):
                if len(x) >= 3:
                    assigned[x[1]].add(const_value(x[2], env[f]))
            for x in list(subterms(t, 'Scall')) + list(subterms(t, 'Sbuiltin')):
                if len(x) >= 3 and isinstance(x[1], list) and x[1][:1] == ['Some']:
                    g = x[2][1][1:] if x[0] == 'Scall' and isinstance(x[2], list) and x[2][:1] == ['Evar'] else None
                    assigned[x[1][1]].add(returns.get(g))
            e = {x: vs.pop() for x, vs in assigned.items() if len(vs) == 1 and None not in vs and x not in params[f]}
            sites = calls.get(f, [])
            if sites and f not in taken:
                for i, x in enumerate(params[f]):
                    vs = {const_value(a[i], env[caller]) if i < len(a) else None for caller, a in sites}
                    if len(vs) == 1 and None not in vs and x not in assigned:
                        e[x] = vs.pop()
            new[f] = e
        rets = {}
        for f, t in trees.items():
            vs = {const_value(r[1][1], new[f]) if isinstance(r[1], list) and r[1][:1] == ['Some'] else None
                  for r in subterms(t, 'Sreturn') if len(r) >= 2}
            if len(vs) == 1 and None not in vs:
                rets[f] = vs.pop()
        if new == env and rets == returns:
            break
        env, returns = new, rets
    return env


def cast_hits(tree, fn_return, env=None):
    """[(kind, category, text)]: the conversions between pointers and integers of one function body (env: its
    temporaries known constant, program_constants)."""
    hits = []
    env = env or {}
    tainted = derived_variables(tree)

    def conversion(src, dst, operand, node, dead, null, how):
        def add(kind, cat):
            hits.append((kind, cat, (how + ': ' if how else '') + show(node)[:200]))
        if is_pointer_type(src) and is_integer_type(dst):
            known_null = is_null(operand) or (isinstance(operand, list) and operand[:1] == ['Etempvar']
                                              and operand[1] in null)
            if dead:
                add(REVIEW, 'pointer-to-integer cast (dead code)')
            elif known_null and is_long_type(dst):
                add(REVIEW, 'pointer-to-integer cast (NULL only)')
            else:
                add(BLOCKER, 'pointer-to-integer cast')
        elif is_integer_type(src) and is_pointer_type(dst):
            v = const_value(operand)
            if v == 0:
                return
            if dead:
                add(REVIEW, 'integer-to-pointer cast (dead code)')
            elif v is not None:
                add(BLOCKER, 'integer-to-pointer cast of a non-zero constant')
            elif pointer_derived(operand, tainted):
                add(BLOCKER, 'integer-to-pointer cast of a pointer-derived value')
            else:
                add(REVIEW, 'integer-to-pointer cast (provable for 0 only)')

    def expr(e, dead, null):
        if not isinstance(e, list) or not e:
            return
        if e[0] == 'Ecast' and len(e) >= 3:
            conversion(typ(e[1]), show(e[2]), e[1], e, dead, null, '')
        if e[0] in ('Esizeof', 'Ealignof'):
            return
        for x in children(e):
            expr(x, dead, null)

    def stmt(s, dead, null):
        if not isinstance(s, list) or not s:
            return
        h = s[0]
        if h == 'Ssequence' and len(s) >= 3:
            stmt(s[1], dead, null)
            stmt(s[2], dead or (ends(s[1], env) and not contains(s[2], 'Slabel')), null)
        elif h == 'Sifthenelse' and len(s) >= 4:
            expr(s[1], dead, null)
            v = const_value(s[1], env)
            nt, ne = null_temps(s[1])
            stmt(s[2], dead or v == 0, null | (nt - assigned_temps(s[2])))
            stmt(s[3], dead or v not in (None, 0), null | (ne - assigned_temps(s[3])))
        elif h == 'Sassign' and len(s) >= 3:
            expr(s[1], dead, null)
            expr(s[2], dead, null)
            conversion(typ(s[2]), typ(s[1]), s[2], s, dead, null, 'implicit, assignment')
        elif h == 'Sset' and len(s) >= 3:
            expr(s[2], dead, null)
        elif h == 'Sreturn' and len(s) >= 2:
            if isinstance(s[1], list) and s[1][:1] == ['Some'] and len(s[1]) >= 2:
                expr(s[1][1], dead, null)
                conversion(typ(s[1][1]), fn_return, s[1][1], s, dead, null, 'implicit, return')
        elif h == 'Scall' and len(s) >= 4:
            expr(s[2], dead, null)
            args = arguments(s[3])
            for a in args:
                expr(a, dead, null)
            for a, t in zip(args, param_types(typ(s[2]))):
                conversion(typ(a), t, a, s, dead, null, 'implicit, call argument')
        elif h in ('Sbuiltin',) and len(s) >= 5:
            for a in arguments(s[4]):
                expr(a, dead, null)
        elif h == 'Sswitch' and len(s) >= 3:
            expr(s[1], dead, null)
            stmt(s[2], dead, null)
        elif h in ('LScons',) and len(s) >= 4:
            stmt(s[2], dead, null)
            stmt(s[3], dead, null)
        else:
            for x in children(s):
                stmt(x, dead, null)

    stmt(tree, False, frozenset())
    return hits


def parsed_body(body):
    m = re.search(r'fn_body :=(.*)$', body, re.S)
    return parse(tokenize(m.group(1)))[0]


def param_names(body):
    m = re.search(r'fn_params :=(.*?);\s*fn_vars', body, re.S)
    return re.findall(r'\((_\w+),', m.group(1)) if m else []


def audit_function(fn, body, holds, env=None):
    """[(kind, category, text)] for one function body (env: its temporaries known constant, program_constants)."""
    hits = []

    def add(kind, cat, e):
        hits.append((kind, cat, show(e)[:220] if e is not None else ''))

    def visit(e):
        if not isinstance(e, list) or not e:
            return
        h = e[0]
        if h == 'Ebinop' and len(e) >= 5:
            op, a, b, t = e[1], e[2], e[3], show(e[4])
            ta, tb = typ(a), typ(b)
            if op in ('Oadd', 'Osub') and (isptr(ta) or isptr(tb)):
                add(REVIEW, 'pointer arithmetic %s' % ('pointer-pointer' if isptr(ta) and isptr(tb) else 'pointer-int'), e)
            if op in ('Olt', 'Ole', 'Ogt', 'Oge') and (isptr(ta) or isptr(tb)):
                add(REVIEW, 'pointer comparison (ordering)', e)
            if op in ('Oeq', 'One') and (isptr(ta) or isptr(tb)):
                if is_null(a) or is_null(b):
                    add(REVIEW, 'pointer comparison with NULL', e)
                else:
                    add(REVIEW, 'pointer comparison (equality of two pointers)', e)
            if op in ('Oadd', 'Osub', 'Omul', 'Oshl') and t in ('tint', 'tlong', 'tschar', 'tshort'):
                add(REVIEW, 'signed arithmetic %s' % t, e)
            if op in ('Odiv', 'Omod'):
                add(REVIEW, 'division', e)
            if op in ('Oshl', 'Oshr'):
                add(REVIEW, 'shift', e)
        elif h == 'Ecast' and len(e) >= 3:
            src, dst = typ(e[1]), show(e[2])
            rank = {'tbool': 0, 'tschar': 1, 'tuchar': 1, 'tshort': 2, 'tushort': 2, 'tint': 3, 'tuint': 3,
                    'tlong': 4, 'tulong': 4}
            if src in rank and dst in rank and rank[dst] < rank[src]:
                add(REVIEW, 'narrowing cast', e)
        elif h in ('Sgoto', 'Slabel'):
            add(BLOCKER, 'goto/label', e)
        elif h == 'Sbuiltin':
            ef = show(e[2]) if len(e) > 2 else ''
            if ef.startswith('(EF_vstore') or ef.startswith('(EF_vload'):
                # a volatile access: VST has no rule for it, so it is provable only where the precondition is False,
                # i.e. on a deliberate crash path (a store through a volatile null pointer)
                add(REVIEW, 'volatile access (provable only where unreachable)', e)
            else:
                add(BLOCKER, 'builtin', e)
        elif h == 'Sassign' and len(e) >= 3 and re.match(r'\((Tstruct|Tunion)', typ(e[1])):
            add(BLOCKER, 'struct assignment', e)
        elif h == 'Sswitch':
            t = typ(e[1])
            if t not in INT_TYPES:
                add(BLOCKER, 'switch on %s' % t, e[1])
        elif h == 'Scall' and len(e) >= 4 and isinstance(e[2], list) and len(e[2]) >= 2 and e[2][0] == 'Evar' \
                and e[2][1][1:] in COPIES:
            callee = e[2][1][1:]
            args = e[3] if isinstance(e[3], list) else []
            types = []
            for x in args:
                if isinstance(x, list) and x and x[0] == 'Ecast':
                    types.append(typ(x[1]))
                elif isinstance(x, list):
                    types.append(typ(x))
            inner = []
            for t in types:   # the pointee of a pointer argument, the element of an array argument
                m = re.match(r'^\(tptr (.*)\)$', t) or re.match(r'^\(tarray (.*) \d+\)$', t)
                if m:
                    inner.append(m.group(1))
            if any(type_holds_pointer(t, holds) for t in inner):
                add(BLOCKER if callee != 'memset' else REVIEW,
                    '%s of pointer-holding memory' % callee, e)
            else:
                add(REVIEW, '%s (%s)' % (callee, ', '.join(inner) or '?'), None)
        for x in e:
            visit(x)

    tree = parsed_body(body)
    visit(tree)
    ret = re.search(r'fn_return :=(.*?);\s*fn_callconv', body, re.S)
    hits.extend(cast_hits(tree, show(parse(tokenize(ret.group(1)))[0][0]) if ret else '?', env))
    if re.search(r'fn_return :=\s*\(?(Tstruct|Tunion)', body) or 'cc_structret:=true' in body:
        add(BLOCKER, 'struct result', None)
    params = re.search(r'fn_params :=(.*?);\s*fn_vars', body, re.S)
    if params and re.search(r',\s*\(?(Tstruct|Tunion)', params.group(1)):
        add(BLOCKER, 'struct parameter', None)
    return hits


def audit_law(tree, harness_out, lib_outs):
    """The audit of one law: harness_out/lib_outs are output directories (src/...) of tools/clight.sh."""
    paths = [os.path.join(tree, o, 'code.v') for o in lib_outs + [harness_out]]
    funcs, gvars, comps = load(paths)
    holds = pointer_holding(comps)
    c, externals = cone(funcs, gvars)
    consts = program_constants({f: parsed_body(funcs[f][1]) for f in c}, {f: param_names(funcs[f][1]) for f in c},
                               gvars)
    rows = []
    for f in sorted(c):
        unit = os.path.relpath(os.path.dirname(funcs[f][0]), tree)
        for kind, cat, txt in audit_function(f, funcs[f][1], holds, consts.get(f)):
            rows.append((kind, cat, f, unit, txt))
    for x in sorted(externals - ENV - set(gvars)):
        rows.append((BLOCKER, 'external outside the framework environment', x, '-', ''))
    return dict(cone=c, externals=externals, rows=rows, holds=holds)


def blockers(result):
    return [r for r in result['rows'] if r[0] == BLOCKER]


def summary(results, verbose=False):
    """Text tables: blockers per law, then review items per category over the union of the cones."""
    out = []
    laws = sorted(results)
    out.append('cones: ' + ', '.join('%s %d functions' % (l, len(results[l]['cone'])) for l in laws))
    out.append('')
    out.append('BLOCKERS (not provable as is):')
    any_b = False
    for l in laws:
        for kind, cat, f, unit, txt in blockers(results[l]):
            any_b = True
            out.append('  %-20s %-44s %s (%s)%s' % (l, cat, f, unit, (': ' + txt) if verbose and txt else ''))
    if not any_b:
        out.append('  none')
    out.append('')
    out.append('review items (over the union of the cones: occurrences, then per function):')
    union = {}
    for l in laws:
        per = collections.Counter((cat, f) for kind, cat, f, unit, txt in results[l]['rows'] if kind == REVIEW)
        for (cat, f), n in per.items():
            fs = union.setdefault(cat, collections.Counter())
            fs[f] = max(fs[f], n)
    for cat in sorted(union):
        fs = union[cat]
        out.append('  %-48s %5d  %s' % (cat, sum(fs.values()), ', '.join('%s:%d' % kv for kv in sorted(fs.items()))[:400]))
    return '\n'.join(out)
