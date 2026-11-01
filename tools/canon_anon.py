#!/usr/bin/env python3
"""quickproof tools/canon_anon.py CODE.v...: one name for an anonymous struct/union shared by units.

clightgen names an anonymous composite (`typedef struct { ... } T;`) after a counter local to the
translation unit (`__334`), so the same type from a shared header gets a different name in each unit
(an encoder's state type can be `__334` in the harness and `__406` in the encoder).  QPlink only
compares machine signatures, so the link succeeds, but every call from one unit to the other then has a
function type that differs from the callee's, and the call is stuck in Clight's semantics.

Anonymous composites with the same kind and the same members in two or more of the given units are the
same type in C (C11 6.2.7: compatible types across translation units).  They are renamed, in every file,
to `__anon_<hash of kind and members>` (the identifier and its string).  Anonymous composites that occur
in one unit only are left alone.  The rewriting is a consistent renaming of one identifier per file.
"""
import hashlib
import os
import re
import sys

COMP = re.compile(r'Composite (__\d+) (Struct|Union)\s*\((.*?)\)\s*\n\s*noattr', re.S)


def canon(files):
    texts = {f: open(f).read() for f in files}
    # per file: anonymous name -> (kind, members), with references to other anonymous composites of the
    # same file resolved to their canonical names (iterated, members may nest anonymous composites)
    names = {}
    for f, t in texts.items():
        comps = {m.group(1): (m.group(2), ' '.join(m.group(3).split())) for m in COMP.finditer(t)}
        can = {}
        for _ in range(len(comps) + 1):
            new = {}
            for n, (kind, mem) in comps.items():
                resolved = re.sub(r'\b(__\d+)\b', lambda m: can.get(m.group(1), '?'), mem)
                new[n] = '__anon_' + hashlib.sha1((kind + ' ' + resolved).encode()).hexdigest()[:12]
            if new == can:
                break
            can = new
        # two distinct anonymous composites with the same members in one file (the result structs of two
        # encode functions of one codec) stay distinct: numbered in their order in the file
        seen = {}
        for n in sorted(can, key=lambda n: t.index('Composite %s ' % n)):
            k = seen.get(can[n], 0)
            seen[can[n]] = k + 1
            if k:
                can[n] = '%s_%d' % (can[n], k)
        names[f] = can
    count = {}
    for can in names.values():
        for c in set(can.values()):
            count[c] = count.get(c, 0) + 1
    for f, t in texts.items():
        ren = {n: c for n, c in names[f].items() if count[c] >= 2}
        if not ren:
            continue
        for n, c in ren.items():
            t = re.sub(r'\$"%s"' % re.escape(n[1:]), '$"%s"' % c[1:], t)
            t = re.sub(r'\b%s\b' % re.escape(n), c, t)
        open(f, 'w').write(t)
        print('%s: %s' % (f, ', '.join('%s=%s' % kv for kv in sorted(ren.items()))))


GVAR = re.compile(r'^Definition v_(\w+) := \{\|', re.M)
PUBLIC = re.compile(r'Definition public_idents : list ident :=\s*\((.*?)\)\.', re.S)


def private_globals(files):
    """A static variable of a shared header (a `static const size_t` constant) is
    an initialized global of every unit that includes it, and QPlink rejects two initialized
    definitions ("Gvars both initialized").  Static linkage makes each a private object of its unit, so
    such globals (not in the unit's public_idents, defined in two or more units) are renamed per unit
    to <unit>__name, like the clashing statics of clight.sh."""
    texts = {f: open(f).read() for f in files}
    private = {}
    for f, t in texts.items():
        m = PUBLIC.search(t)
        public = set(re.findall(r'\b_(\w+)\b', m.group(1))) if m else set()
        private[f] = set(GVAR.findall(t)) - public
    count = {}
    for names in private.values():
        for n in names:
            count[n] = count.get(n, 0) + 1
    for f, t in texts.items():
        ren = sorted(n for n in private[f] if count[n] >= 2 and not n.startswith('__stringlit_'))
        if not ren:
            continue
        unit = re.sub(r'[^A-Za-z0-9_]', '_', os.path.basename(os.path.dirname(os.path.abspath(f))))
        for n in ren:
            new = '%s__%s' % (unit, n)
            t = re.sub(r'\$"%s"' % re.escape(n), '$"%s"' % new, t)
            t = re.sub(r'(?<![\w])_%s\b' % re.escape(n), '_' + new, t)
            t = re.sub(r'\bv_%s\b' % re.escape(n), 'v_' + new, t)
        open(f, 'w').write(t)
        print('%s: private globals renamed: %s' % (f, ', '.join(ren)))


if __name__ == '__main__':
    canon(sys.argv[1:])
    private_globals(sys.argv[1:])
