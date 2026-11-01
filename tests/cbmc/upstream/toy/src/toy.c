/* toy.c: a toy library for the tests of tools/qp import-cbmc (tests/qp/cbmc.sh). */
#include "toy.h"

int toy_buf_push(struct toy_buf *b, uint8_t x)
{
	if (b == NULL || b->data == NULL || b->len >= b->cap)
		return -1;
	b->data[b->len] = x;
	b->len = b->len + 1;
	return 0;
}

size_t toy_count(const char *s, size_t n, char c)
{
	size_t i, k = 0;
	for (i = 0; i < n; i = i + 1)
		if (s[i] == c)
			k = k + 1;
	return k;
}

static int toy_hidden(int x)
{
	return x / 2;
}

int toy_replaceable(int x)
{
	return toy_hidden(x) + TOY_CONFIG;
}

int toy_twice(int x)
{
	if (x > 1000000 || x < -1000000)
		return 0;
	return 2 * x;
}
