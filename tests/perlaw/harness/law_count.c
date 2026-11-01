/* Law law_count: counter_inc on a fresh counter with any bound succeeds exactly when the bound is not 0,
   and counter_get then returns the number of successful increments. */
#include "quickproof.h"
#include "counter.h"

int main(void)
{
	struct counter c;
	int r;
	c.n = 0;
	c.max = nondet_u32();
	r = counter_inc(&c);
	gp_assert(r == (c.max != 0));
	gp_assert(counter_get(&c) == (unsigned) r);
	return 0;
}
