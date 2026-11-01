#!/usr/bin/env python3
"""tests/qp/test_vst_lint.py: a test of qp's VST lint (`qp lint`, the lint step of `qp check`).

It builds a small tree in a temporary directory, with quickproof/ = this framework (as in a tree of `qp tree`).
The tree has a header with three bitfield declarations and a unit that uses only the first:
- a struct the unit uses;
- a struct it never uses;
- a typedef'd anonymous struct it never uses (a second unit uses it).
CompCert's clightgen drops the types a unit does not use, so `make_compspecs` (VST 2.15 has no bitfields) would
fail on the first struct only.  The test checks the following:
- the lint reports exactly that composite, with its members and its declaration's location;
- the other two declarations are info only;
- a switch that falls off its last case is still reported;
- a unit with no bitfield type in its Clight and no such switch is clean.

Needs clightgen (CompCert 3.15) in PATH, or in the opam switch QP_OPAM_SWITCH.  Exit status 0 = pass.
"""
import importlib.util
import importlib.machinery
import os
import shutil
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
loader = importlib.machinery.SourceFileLoader('qp', os.path.join(ROOT, 'tools', 'qp'))
spec = importlib.util.spec_from_loader('qp', loader)
qp = importlib.util.module_from_spec(spec)
loader.exec_module(qp)

TYPES_H = """\
#ifndef TYPES_H
#define TYPES_H
struct used {
    unsigned a : 3;
    unsigned b : 5;
    int c;
};
struct unused {
    unsigned x : 1;
    int y;
};
typedef struct {
    unsigned f : 1;
} anon_t;
struct plain { int p; };
#endif
"""

UNIT_C = """\
#include "types.h"
int get(struct used *u, struct plain *q) { return u->a + u->c + q->p; }
"""

CLEAN_C = """\
#include "types.h"
int get_plain(struct plain *q) { return q->p; }
"""

ANON_C = """\
#include "types.h"
int flag(anon_t *t) { return t->f; }
"""

SWITCH_C = """\
#include "types.h"
int pick(int k, struct plain *q) {
    int r = 0;
    switch (k) {
    case 0: r = q->p; break;
    default: r = 1;
    }
    return r;
}
"""

failures = []


def expect(cond, what):
    print('%s  %s' % ('ok  ' if cond else 'FAIL', what))
    if not cond:
        failures.append(what)


tree = tempfile.mkdtemp(prefix='qp-lint-test-')
try:
    # quickproof/ = this framework, as in a tree of `qp tree`: its include/ and tools/tag_anon.py
    fw = qp.FRAMEWORK_HOME
    os.symlink(fw, os.path.join(tree, qp.FW))
    anon = '__gp_anon_t' if os.path.exists(os.path.join(fw, 'tools', 'tag_anon.py')) else 'anonymous struct/union'
    for name, text in (('types.h', TYPES_H), ('unit.c', UNIT_C), ('clean.c', CLEAN_C), ('anon.c', ANON_C),
                       ('switch.c', SWITCH_C)):
        open(os.path.join(tree, name), 'w').write(text)

    lint, info = qp.vst_lint(tree, ['unit.c'], ['-I.'], [])
    print('-- unit.c\nlint: %s\ninfo: %s' % (lint, info))
    expect(len(lint) == 1, 'unit.c: exactly one lint line')
    expect(bool(lint) and lint[0].startswith('types.h:3: composite `used` has bitfield members (a, b)'),
           'unit.c: the used struct, its members and its declaration (types.h:3)')
    expect(not any('unused' in l or 'anon' in l for l in lint), 'unit.c: the unused declarations are not lint')
    expect(bool(info) and info[0].startswith('3 bitfield declaration(s) in the sources, 1 of them in the Clight'),
           'unit.c: info counts 3 source declarations, 1 in the Clight')
    expect('types.h:8: unused (not in the Clight)' in info, 'unit.c: struct unused is info, not in the Clight')
    expect('types.h:12: %s (not in the Clight)' % anon in info,
           'unit.c: the typedef\'d anonymous struct (%s, as clight.sh tags it) is info, not in the Clight' % anon)

    lint, info = qp.vst_lint(tree, ['clean.c'], ['-I.'], [])
    print('-- clean.c\nlint: %s\ninfo: %s' % (lint, info))
    expect(lint == [], 'clean.c: clean (bitfield declarations in its headers, none in its Clight)')
    expect(bool(info) and info[0].startswith('3 bitfield declaration(s) in the sources, 0 of them in the Clight'),
           'clean.c: the source count is kept as info')

    lint, info = qp.vst_lint(tree, ['anon.c'], ['-I.'], [])
    print('-- anon.c\nlint: %s' % lint)
    expect(len(lint) == 1 and lint[0].startswith('types.h:12: composite `%s` has bitfield members (f)' % anon)
           if anon.startswith('__gp_') else len(lint) == 1 and '(f)' in lint[0],
           'anon.c: a used typedef\'d anonymous struct is reported (located when clight.sh tags it)')

    lint, info = qp.vst_lint(tree, ['switch.c'], ['-I.'], [])
    print('-- switch.c\nlint: %s' % lint)
    expect(lint == ['switch.c:4: the last case of this switch does not end with break/return'],
           'switch.c: the switch fall-off is still reported')
finally:
    shutil.rmtree(tree, ignore_errors=True)

print('%d failure(s)' % len(failures))
sys.exit(1 if failures else 0)
