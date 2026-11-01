// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// quickproof libc/string.c: string functions in plain C, for laws whose code calls them.
//
// A sibling of libc/libc.c (which has memcpy, memmove, memset, memcmp and calloc).  Laws imported by
// `tools/qp import-cbmc` link it: CBMC has its own models of these functions, and the harnesses and the
// code under test call them.  A project links this file as one of its units, so the functions are verified
// like every other function and no axiom about them is needed.  The same file is linked in interpreter
// runs; native runs use the system's C library.  Index-based, no pointer comparisons.

#include <stddef.h>
#include <string.h>

size_t strlen(const char *s)
{
	size_t i = 0;
	while (s[i] != '\0')
		i = i + 1;
	return i;
}

size_t strnlen(const char *s, size_t n)
{
	size_t i = 0;
	while (i < n && s[i] != '\0')
		i = i + 1;
	return i;
}

int strcmp(const char *a, const char *b)
{
	size_t i = 0;
	while (a[i] != '\0' && a[i] == b[i])
		i = i + 1;
	return (int) (unsigned char) a[i] - (int) (unsigned char) b[i];
}

int strncmp(const char *a, const char *b, size_t n)
{
	size_t i = 0;
	while (i < n) {
		unsigned char x = (unsigned char) a[i];
		unsigned char y = (unsigned char) b[i];
		if (x != y)
			return (int) x - (int) y;
		if (x == '\0')
			return 0;
		i = i + 1;
	}
	return 0;
}

void *memchr(const void *s, int c, size_t n)
{
	const unsigned char *p = s;
	size_t i = 0;
	while (i < n) {
		if (p[i] == (unsigned char) c)
			return (void *) (p + i);
		i = i + 1;
	}
	return NULL;
}
