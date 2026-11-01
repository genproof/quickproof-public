/* Design test 1: uninitialised locals of every kind get an arbitrary value of their type. */
#include <stdlib.h>
#include "toy_cbmc.h"

enum colour { RED, GREEN, BLUE };

typedef struct {
	bool flag;
	int *p;
} anon_t;

struct inner {
	bool b;
	char c;
	short s;
	unsigned bits : 3;
	int (*fn)(int);
};

struct outer {
	struct inner in;
	anon_t pairs[2];
	union { int i; char ch[4]; } u;
	uint8_t bytes[8];
	uint32_t words[3];
};

void harness(void)
{
	size_t n;
	bool b;
	char *p;
	struct toy_buf buf;
	struct outer o;
	anon_t a;
	struct inner arr[2];
	enum colour col;
	char c;
	short s;
	uint16_t x, y;
	if (n > 3) {
		int nested;
		__CPROVER_assume(nested > 0 && nested < 100);
		assert(toy_twice(nested) == 2 * nested);
	}
	__CPROVER_assume(b);
	__CPROVER_assume(buf.len <= buf.cap);
	__CPROVER_assume(col == RED || col == BLUE);
	__CPROVER_assert(o.in.b == 0 || o.in.b == 1, "a _Bool is 0 or 1");
	__CPROVER_assert(arr[1].b == 0 || arr[1].b == 1, "a _Bool is 0 or 1");
	__CPROVER_assert(a.flag == 0 || a.flag == 1, "a _Bool is 0 or 1");
	(void) p;
	(void) c;
	(void) s;
	(void) x;
	(void) y;
}
