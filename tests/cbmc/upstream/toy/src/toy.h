/* toy.h: a toy library for the tests of tools/qp import-cbmc (tests/qp/cbmc.sh). */
#ifndef TOY_H
#define TOY_H
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifndef TOY_CONFIG
#error "TOY_CONFIG is set by the proofs' Makefile-project-defines"
#endif

/* As aws-c-common's AWS_MEM_IS_READABLE: a CBMC-only predicate under -DCBMC. */
#ifdef CBMC
#define TOY_IS_READABLE(p, n) __CPROVER_r_ok((p), (n))
#else
#define TOY_IS_READABLE(p, n) ((n) == 0 || (p) != NULL)
#endif

struct toy_buf {
	uint8_t *data;
	size_t len;
	size_t cap;
	bool owned;
};

int toy_buf_push(struct toy_buf *b, uint8_t x);
size_t toy_count(const char *s, size_t n, char c);
int toy_replaceable(int x);
int toy_twice(int x);
#endif
