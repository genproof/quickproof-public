// SPDX-FileCopyrightText: 2026 GenProof
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// A test task of tools/qp import-svcomp (tests/qp/svcomp.sh): reach_error() is reachable (x == 5).

extern void __assert_fail(const char *, const char *, unsigned int, const char *) __attribute__((__nothrow__, __leaf__)) __attribute__((__noreturn__));
void reach_error() { __assert_fail("0", "reach-false.c", 0, "reach_error"); }
extern int __VERIFIER_nondet_int(void);

int main()
{
	int x = __VERIFIER_nondet_int();
	if (x >= 0 && x < 50) {
		if (x * 2 == 10)
			reach_error();
	}
	return 0;
}
