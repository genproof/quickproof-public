#include "counter.h"
extern void log_reset(void);

unsigned counter_get(struct counter *c) { return c->n; }

int counter_inc(struct counter *c)
{
	if (c->n >= c->max)
		return 0;
	c->n = c->n + 1;
	return 1;
}

/* Reached by no law; it references log.c, which every law that links counter.c therefore links too. */
void counter_reset(struct counter *c)
{
	c->n = 0;
	log_reset();
}
