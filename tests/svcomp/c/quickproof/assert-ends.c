// SPDX-FileCopyrightText: 2026 GenProof
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// A test task of tools/qp import-svcomp (tests/qp/svcomp.sh): a failing assert() outside reach_error ends the
// execution without error, as abort() does (x == 7 never reaches reach_error).

extern void __assert_fail(const char *, const char *, unsigned int, const char *) __attribute__((__nothrow__, __leaf__)) __attribute__((__noreturn__));
void reach_error() { __assert_fail("0", "assert-ends.c", 0, "reach_error"); }
extern int __VERIFIER_nondet_int(void);

void check(int c)
{
	if (!c)
		__assert_fail("c", "assert-ends.c", 13, "check");
}

int main()
{
	int x = __VERIFIER_nondet_int();
	check(x != 7);
	if (x == 7)
		reach_error();
	return 0;
}
