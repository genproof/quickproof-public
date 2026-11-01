// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// quickproof libc/libc.c: the libc functions verified code usually calls, written in plain C.
//
// A project links this file as one of its units, so the functions are verified like every other
// function and no axiom about them is needed: the only external functions left are malloc/free and the
// nondet_* environment (include/quickproof.h).  The same file is linked in native and interpreter runs.
// Byte-by-byte on purpose (no word tricks).

#include <stddef.h>
#include <stdint.h>
#include <string.h>

extern void *malloc(size_t);

void *memcpy(void *restrict dest, const void *restrict src, size_t n)
{
	unsigned char *d = dest;
	const unsigned char *s = src;
	for (size_t i = 0; i < n; ++i)
		d[i] = s[i];
	return dest;
}

// No ordering comparison of pointers: d < s is undefined (in C and in CompCert's semantics) when the
// two pointers point into different objects, and memmove between different objects is legitimate
// (lz4 moves literals from its input buffer to its output buffer this way).  The ranges overlap
// with d after s exactly when d == s + i for some 0 < i < n (pointer equality is defined for pointers
// into different objects); only then is the copy done backwards.
void *memmove(void *dest, const void *src, size_t n)
{
	unsigned char *d = dest;
	const unsigned char *s = src;
	int backwards = 0;
	for (size_t i = 1; i < n; ++i)
		if (s + i == d) {
			backwards = 1;
			break;
		}
	if (backwards) {
		for (size_t i = n; i > 0; --i)
			d[i - 1] = s[i - 1];
	} else {
		for (size_t i = 0; i < n; ++i)
			d[i] = s[i];
	}
	return dest;
}

void *memset(void *s, int c, size_t n)
{
	unsigned char *p = s;
	for (size_t i = 0; i < n; ++i)
		p[i] = (unsigned char)c;
	return s;
}

int memcmp(const void *s1, const void *s2, size_t n)
{
	const unsigned char *a = s1;
	const unsigned char *b = s2;
	for (size_t i = 0; i < n; ++i)
		if (a[i] != b[i])
			return (int)a[i] - (int)b[i];
	return 0;
}

void *calloc(size_t nmemb, size_t size)
{
	if (size != 0 && nmemb > SIZE_MAX / size)
		return NULL;
	const size_t total = nmemb * size;
	unsigned char *p = malloc(total);
	if (p != NULL)
		for (size_t i = 0; i < total; ++i)
			p[i] = 0;
	return p;
}
