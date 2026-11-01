// SPDX-FileCopyrightText: 2026 GenProof
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// A test task of tools/qp import-svcomp (tests/qp/svcomp.sh), refused: a nondet pointer value.

extern void __assert_fail(const char *, const char *, unsigned int, const char *);
void reach_error() { __assert_fail("0", "refuse-pointer.c", 0, "reach_error"); }
extern void *__VERIFIER_nondet_pointer(void);
int main() { void *p = __VERIFIER_nondet_pointer(); return p == 0; }
