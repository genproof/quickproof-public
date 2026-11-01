// SPDX-FileCopyrightText: 2026 GenProof
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// A test task of tools/qp import-svcomp (tests/qp/svcomp.sh): every __VERIFIER_nondet_* function returns a value of its type.

extern void __assert_fail(const char *, const char *, unsigned int, const char *) __attribute__((__nothrow__, __leaf__)) __attribute__((__noreturn__));
void reach_error() { __assert_fail("0", "nondet-values.c", 0, "reach_error"); }
extern char __VERIFIER_nondet_char(void);
extern unsigned char __VERIFIER_nondet_uchar(void);
extern short __VERIFIER_nondet_short(void);
extern unsigned short __VERIFIER_nondet_ushort(void);
extern int __VERIFIER_nondet_int(void);
extern unsigned int __VERIFIER_nondet_uint(void);
extern unsigned __VERIFIER_nondet_unsigned(void);
extern unsigned int __VERIFIER_nondet_u32(void);
extern long __VERIFIER_nondet_long(void);
extern unsigned long __VERIFIER_nondet_ulong(void);
extern long long __VERIFIER_nondet_longlong(void);
extern unsigned long long __VERIFIER_nondet_ulonglong(void);
extern unsigned long __VERIFIER_nondet_size_t(void);
extern _Bool __VERIFIER_nondet_bool(void);
extern void __VERIFIER_nondet_memory(void *, unsigned long);
extern void __VERIFIER_assume(int);

int main()
{
	_Bool b = __VERIFIER_nondet_bool();
	char c = __VERIFIER_nondet_char();
	unsigned char uc = __VERIFIER_nondet_uchar();
	short s = __VERIFIER_nondet_short();
	unsigned short us = __VERIFIER_nondet_ushort();
	int i = __VERIFIER_nondet_int();
	unsigned int u = __VERIFIER_nondet_uint() ^ __VERIFIER_nondet_unsigned() ^ __VERIFIER_nondet_u32();
	long l = __VERIFIER_nondet_long();
	unsigned long ul = __VERIFIER_nondet_ulong() ^ __VERIFIER_nondet_size_t();
	long long ll = __VERIFIER_nondet_longlong();
	unsigned long long ull = __VERIFIER_nondet_ulonglong();
	unsigned char buf[8];
	__VERIFIER_nondet_memory(buf, sizeof buf);
	__VERIFIER_assume(i >= 0 && i < 100);
	if (b != 0 && b != 1)
		reach_error();
	if (c < -128 || c > 127 || uc > 255 || s < -32768 || s > 32767 || us > 65535)
		reach_error();
	if (i < 0 || i >= 100)
		reach_error();
	if (u / 2 > 2147483647U || ul / 2 > 9223372036854775807UL || ull / 2 > 9223372036854775807ULL)
		reach_error();
	if ((l < 0) != (l <= -1) || (ll < 0) != (ll <= -1))
		reach_error();
	if (buf[7] > 255)
		reach_error();
	return 0;
}
