// SPDX-FileCopyrightText: 2026 GenProof
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// A test task of tools/qp import-svcomp (tests/qp/svcomp.sh), refused: inline assembly.

extern void __assert_fail(const char *, const char *, unsigned int, const char *);
void reach_error() { __assert_fail("0", "refuse-asm.c", 0, "reach_error"); }
int main() { int x = 0; __asm__ __volatile__ ("" : "+r" (x)); return x; }
