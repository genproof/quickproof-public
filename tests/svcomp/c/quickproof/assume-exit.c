// SPDX-FileCopyrightText: 2026 GenProof
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// A test task of tools/qp import-svcomp (tests/qp/svcomp.sh): abort() and exit() end an execution without error, also inside assume helpers.

extern void __assert_fail(const char *, const char *, unsigned int, const char *) __attribute__((__nothrow__, __leaf__)) __attribute__((__noreturn__));
void reach_error() { __assert_fail("0", "assume-exit.c", 0, "reach_error"); }
extern unsigned int __VERIFIER_nondet_uint(void);
extern void abort(void);
extern void exit(int);

void assume_abort_if_not(int cond)
{
	if (!cond) {
		abort();
	}
}

void assume_or_exit(int cond)
{
	if (!cond)
		exit(1);
}

int main()
{
	unsigned int x = __VERIFIER_nondet_uint();
	assume_abort_if_not(x < 1000);
	assume_or_exit(x % 2 == 0);
	if (x >= 1000 || x % 2 != 0)
		reach_error();
	return 0;
}
