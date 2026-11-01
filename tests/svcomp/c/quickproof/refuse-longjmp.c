// SPDX-FileCopyrightText: 2026 GenProof
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// A test task of tools/qp import-svcomp (tests/qp/svcomp.sh), refused: setjmp/longjmp.

extern void __assert_fail(const char *, const char *, unsigned int, const char *);
void reach_error() { __assert_fail("0", "refuse-longjmp.c", 0, "reach_error"); }
typedef long jmp_buf[8];
extern int setjmp(jmp_buf);
extern void longjmp(jmp_buf, int);
jmp_buf env;
int main() { if (setjmp(env) == 0) longjmp(env, 1); return 0; }
