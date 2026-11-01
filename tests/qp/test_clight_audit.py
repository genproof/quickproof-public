#!/usr/bin/env python3
"""tests/qp/test_clight_audit.py: a regression test of tools/clight_audit.py (the Clight audit of a law's cone,
used by `tools/qp audit`, the VST lint of `tools/qp lint`/`check` and the cone check of `tools/qp import-fuzz`).

The cases come from real code: a switch on a size_t (lz4's xxhash.c, XXH32_finalize: VST's only switch rule needs an
int scrutinee), a memcpy of a struct holding pointers (lz4's LZ4_compress_fast_continue), and a
`(void *)((size_t)p)` (VST typechecks a pointer-to-integer cast only for NULL).
This test translates a small two-unit program with clightgen and checks that the audit:
  - reports, as blockers in the cone of `main`: the switch on a size_t, the switch on a long long, the goto, the
    struct assignment, the struct parameter and result, the memcpy of a struct holding a pointer; pointer-to-integer
    casts (explicit, to a 64-bit or a 32-bit integer, and implicit in a return), integer-to-pointer casts of a
    pointer-derived value (directly, and through a temporary and integer arithmetic) and of a non-zero
    constant, and a cast under a NULL test whose branch reassigns the pointer;
  - does not report a switch on an int or on an unsigned char, a memcpy of octets, a memset of a struct with a
    pointer (a review item), nor anything in a function `main` does not reach;
  - makes review items, not blockers, of a pointer-to-integer cast of a provably NULL pointer (a null constant, a
    pointer tested NULL by the enclosing `if`) and of one in dead code (`if (sizeof(void *) == 4)`, after a return,
    and lz4's LZ4_isAligned: a branch on a parameter that every call passes the same constant, also as the result
    of a constant function; not when calls pass different values), and of an integer-to-pointer cast of a plain
    integer; and reports nothing for a pointer-to-_Bool cast or NULL;
  - follows function pointers (an address taken) into the cone.
Needs clightgen (CompCert 3.15) in PATH, or in the opam switch QP_OPAM_SWITCH.  Exit 0 = pass."""
import importlib.util
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.realpath(__file__))
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('clight_audit', os.path.join(HERE, '..', '..', 'tools', 'clight_audit.py'))
ca = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ca)

LIB = r'''
#include <stddef.h>
#include <stdint.h>
#include <string.h>
struct holder { char *p; int n; };
struct plain { unsigned char b[8]; };
int sw_size(size_t len) { switch (len & 3) { case 0: return 1; default: return 2; } }
int sw_ll(long long v) { switch (v) { case 1: return 1; default: return 0; } }
int sw_int(int v) { switch (v) { case 1: return 1; default: return 0; } }
int sw_uchar(unsigned char c) { switch (c) { case 'a': return 1; default: return 0; } }
int jumps(int x) { if (x) goto out; x = 1; out: return x; }
void copy_holder(struct holder *d, const struct holder *s) { memcpy(d, s, sizeof *d); }
void copy_plain(struct plain *d, const struct plain *s) { memcpy(d, s, sizeof *d); }
void clear_holder(struct holder *d) { memset(d, 0, sizeof *d); }
void assign_holder(struct holder *d, struct holder *s) { *d = *s; }
int by_value(struct plain v) { return v.b[0]; }
struct plain returns(void) { struct plain v; v.b[0] = 1; return v; }
int via_pointer(size_t len) { switch (len) { case 0: return 0; default: return 1; } }
int unreached(size_t len) { switch (len) { case 0: return 0; default: return 1; } }
void *cast_roundtrip(const void *p) { return (void *)((size_t)p); }
void *cast_align(char *p) { uintptr_t u = (uintptr_t)p; u &= ~(uintptr_t)7; return (void *)u; }
int cast_to_int(char *p) { return (int)p; }
long cast_implicit(char *p) { return p; }
void *cast_sentinel(void) { return (void *)1; }
long cast_null_reassigned(char *p, char *q) { if (p == NULL) { p = q; return (long)p; } return 0; }
long cast_null_guard(char *p) { if (p == NULL) return (long)p; return 0; }
long cast_null_const(void) { return (long)(void *)0; }
long cast_dead(char *p) { if (sizeof(void *) == 4) return (long)p; return 1; }
long cast_after_return(char *p) { if (p) return 1; else return 2; return (long)p; }
void *cast_from_int(size_t n) { return (void *)n; }
int cast_to_bool(char *p) { _Bool b = (_Bool)p; return b; }
void *cast_null(void) { return (void *)0; }
long unreached_cast(char *p) { return (long)p; }
static size_t align_one(void) { return 1; }
static int aligned_const(const void *p, size_t a) { return (a <= 1) || (((size_t)p & (a - 1)) == 0); }
static int aligned_var(const void *p, size_t a) { return (a <= 1) || (((size_t)p & (a - 1)) == 0); }
int cast_aligned(void *b) { return aligned_const(b, align_one()) + aligned_var(b, 1) + aligned_var(b, 8); }
'''

HARNESS = r'''
#include <stddef.h>
struct holder { char *p; int n; };
struct plain { unsigned char b[8]; };
int sw_size(size_t); int sw_ll(long long); int sw_int(int); int sw_uchar(unsigned char); int jumps(int);
void copy_holder(struct holder *, const struct holder *); void copy_plain(struct plain *, const struct plain *);
void clear_holder(struct holder *); void assign_holder(struct holder *, struct holder *);
int by_value(struct plain); struct plain returns(void); int via_pointer(size_t);
void *cast_roundtrip(const void *); void *cast_align(char *); int cast_to_int(char *); long cast_implicit(char *);
void *cast_sentinel(void); long cast_null_reassigned(char *, char *); long cast_null_guard(char *);
long cast_null_const(void); long cast_dead(char *); long cast_after_return(char *); void *cast_from_int(size_t);
int cast_to_bool(char *); void *cast_null(void); int cast_aligned(void *);
int (*fp)(size_t) = via_pointer;
int main(void)
{
	struct holder a, b; struct plain x, y; char c = 0;
	a.p = 0; a.n = 0; x.b[0] = 0;
	copy_holder(&b, &a); copy_plain(&y, &x); clear_holder(&b); assign_holder(&b, &a);
	cast_roundtrip(&c); cast_align(&c); cast_to_int(&c); cast_implicit(&c); cast_sentinel(); cast_null_reassigned(0, &c);
	cast_null_guard(&c); cast_null_const(); cast_dead(&c); cast_after_return(&c); cast_from_int(0); cast_to_bool(&c);
	cast_null(); cast_aligned(&c);
	return sw_size(3) + sw_ll(2) + sw_int(1) + sw_uchar('a') + jumps(0) + by_value(x) + returns().b[0] + fp(1);
}
'''


def clightgen(src, out, d):
    os.makedirs(os.path.join(d, out))
    c = os.path.join(d, os.path.basename(out) + '.c')
    open(c, 'w').write(src)
    env = dict(os.environ)
    if os.environ.get('QP_OPAM_SWITCH'):
        opam = subprocess.run(['opam', 'env', '--switch=' + os.environ['QP_OPAM_SWITCH'], '--set-switch'],
                              capture_output=True, text=True).stdout
        env.update(dict(re.findall(r"^(\w+)='([^']*)'", opam, re.M)))
    subprocess.run(['clightgen', '-normalize', '-fstruct-passing', c, '-o', os.path.join(d, out, 'code.v')],
                   check=True, env=env, capture_output=True)   # warns of the implicit conversion in cast_implicit


def main():
    with tempfile.TemporaryDirectory() as d:
        clightgen(LIB, 'src/lib', d)
        clightgen(HARNESS, 'src/harness/h', d)
        r = ca.audit_law(d, 'src/harness/h', ['src/lib'])
        blockers = {(cat, f) for kind, cat, f, unit, txt in ca.blockers(r)}
        reviews = {(cat, f) for kind, cat, f, unit, txt in r['rows'] if kind == ca.REVIEW}
        want = {('switch on tulong', 'sw_size'), ('switch on tlong', 'sw_ll'), ('goto/label', 'jumps'),
                ('memcpy of pointer-holding memory', 'copy_holder'), ('struct assignment', 'assign_holder'),
                ('struct parameter', 'by_value'), ('struct result', 'returns'), ('switch on tulong', 'via_pointer'),
                ('pointer-to-integer cast', 'cast_roundtrip'),
                ('integer-to-pointer cast of a pointer-derived value', 'cast_roundtrip'),
                ('pointer-to-integer cast', 'cast_align'),
                ('integer-to-pointer cast of a pointer-derived value', 'cast_align'),
                ('pointer-to-integer cast', 'cast_to_int'), ('pointer-to-integer cast', 'cast_implicit'),
                ('integer-to-pointer cast of a non-zero constant', 'cast_sentinel'),
                ('pointer-to-integer cast', 'cast_null_reassigned'), ('pointer-to-integer cast', 'aligned_var')}
        want_reviews = {('pointer-to-integer cast (NULL only)', 'cast_null_guard'),
                        ('pointer-to-integer cast (NULL only)', 'cast_null_const'),
                        ('pointer-to-integer cast (dead code)', 'cast_dead'),
                        ('pointer-to-integer cast (dead code)', 'cast_after_return'),
                        ('integer-to-pointer cast (provable for 0 only)', 'cast_from_int'),
                        ('pointer-to-integer cast (dead code)', 'aligned_const')}
        missing = want - blockers
        unwanted = {b for b in blockers if b[1] in ('sw_int', 'sw_uchar', 'copy_plain', 'clear_holder', 'unreached',
                                                    'cast_null_guard', 'cast_null_const', 'cast_dead',
                                                    'cast_after_return', 'cast_from_int', 'cast_to_bool', 'cast_null',
                                                    'aligned_const')}
        casts = {(cat, f) for kind, cat, f, unit, txt in r['rows'] if 'cast' in cat and 'narrowing' not in cat}
        ok = True
        if missing:
            print('FAIL: blockers not reported: %s' % sorted(missing)); ok = False
        if unwanted:
            print('FAIL: false blockers: %s' % sorted(unwanted)); ok = False
        if ('memset of pointer-holding memory', 'clear_holder') not in reviews:
            print('FAIL: the memset of a struct with a pointer is not a review item'); ok = False
        if want_reviews - reviews:
            print('FAIL: review items not reported: %s' % sorted(want_reviews - reviews)); ok = False
        if {c for c in casts if c[1] in ('cast_to_bool', 'cast_null')}:
            print('FAIL: casts reported for _Bool or NULL: %s' % sorted(c for c in casts if c[1] in ('cast_to_bool', 'cast_null'))); ok = False
        if 'unreached_cast' in r['cone']:
            print('FAIL: a function main does not reach is in the cone'); ok = False
        if 'unreached' in r['cone']:
            print('FAIL: a function main does not reach is in the cone'); ok = False
        print('PASS' if ok else 'FAILED')
        return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
