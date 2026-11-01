/* The toy library of the per-law linking test (tests/perlaw): a bounded counter. */
struct counter { unsigned n; unsigned max; };
unsigned counter_get(struct counter *c);
int counter_inc(struct counter *c);
void counter_reset(struct counter *c);
