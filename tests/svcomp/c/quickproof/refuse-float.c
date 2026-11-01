// SPDX-FileCopyrightText: 2026 GenProof
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// A test task of tools/qp import-svcomp (tests/qp/svcomp.sh), refused: a nondet floating-point value.

extern void __assert_fail(const char *, const char *, unsigned int, const char *);
void reach_error() { __assert_fail("0", "refuse-float.c", 0, "reach_error"); }
extern double __VERIFIER_nondet_double(void);
int main() { double d = __VERIFIER_nondet_double(); if (d != d) return 1; return 0; }
