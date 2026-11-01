/* Law law_pair: pair_sum adds, and a counter of bound 1 goes to 1 once and then refuses. */
#include "quickproof.h"
#include "counter.h"
struct pair { unsigned a; unsigned b; };
unsigned pair_sum(struct pair *p);

int main(void)
{
	struct pair p;
	struct counter c;
	p.a = 1;
	p.b = 2;
	gp_assert(pair_sum(&p) == 3);
	c.n = 0;
	c.max = 1;
	gp_assert(counter_inc(&c) == 1);
	gp_assert(counter_inc(&c) == 0);
	return 0;
}
