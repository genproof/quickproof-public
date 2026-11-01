// SPDX-FileCopyrightText: 2026 GenProof
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// A test task of tools/qp import-svcomp (tests/qp/svcomp.sh), refused: an unknown __VERIFIER function.

extern void __assert_fail(const char *, const char *, unsigned int, const char *);
void reach_error() { __assert_fail("0", "refuse-unknown.c", 0, "reach_error"); }
extern int __VERIFIER_nondet_foo(void);
int main() { return __VERIFIER_nondet_foo() == 0; }
