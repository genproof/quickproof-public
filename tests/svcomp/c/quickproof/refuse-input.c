// SPDX-FileCopyrightText: 2026 GenProof
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// A test task of tools/qp import-svcomp (tests/qp/svcomp.sh), refused: it reads input (fgets).

extern void __assert_fail(const char *, const char *, unsigned int, const char *);
void reach_error() { __assert_fail("0", "refuse-input.c", 0, "reach_error"); }
struct _IO_FILE;
extern struct _IO_FILE *stdin;
extern char *fgets(char *, int, struct _IO_FILE *);
int main() { char buf[8]; if (fgets(buf, 8, stdin) == 0) return 0; return buf[0] == 0; }
