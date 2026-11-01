#!/usr/bin/env python3
"""quickproof tools/tag_anon.py FILE.i: give every `typedef struct { ... } T;` (and union) of a
preprocessed unit the tag `__gp_T`.

clightgen names an anonymous composite after a counter local to the translation unit, and emits only
the composites the unit uses, so the same header type gets unrelated names in different units, and two
anonymous types with equal members cannot be told apart (the result structs of one codec, say).  Calls
between units then have mismatched types, and Clight's semantics is stuck.  A tag taken from the
typedef name is the same in every unit that includes the header.  Tagging an untagged structure
changes nothing within a unit, and across units both declarations get the same tag and members, so
they stay compatible (C11 6.2.7).  Anonymous composites without a typedef are left to canon_anon.py.
"""
import re
import sys

HEAD = re.compile(r'\btypedef(\s+(?:const\s+|volatile\s+)*)(struct|union)(\s*)\{')


def tag(text):
    out, pos = [], 0
    for m in HEAD.finditer(text):
        if m.start() < pos:
            continue
        depth, i = 0, m.end() - 1
        while i < len(text):
            if text[i] == '{':
                depth += 1
            elif text[i] == '}':
                depth -= 1
                if depth == 0:
                    break
            i += 1
        rest = text[i + 1:]
        d = re.match(r'(?:\s|__attribute__\s*\(\(.*?\)\)|\bconst\b|\bvolatile\b|\*)*([A-Za-z_]\w*)', rest, re.S)
        if not d:
            continue
        out.append(text[pos:m.start()])
        out.append('typedef%s%s __gp_%s%s{' % (m.group(1), m.group(2), d.group(1), m.group(3) or ' '))
        pos = m.end()
    out.append(text[pos:])
    return ''.join(out)


if __name__ == '__main__':
    for f in sys.argv[1:]:
        t = open(f).read()
        open(f, 'w').write(tag(t))
