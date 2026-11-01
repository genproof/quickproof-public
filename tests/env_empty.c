/* The environment must touch no memory for an empty NULL or non-NULL buffer. */
#include "quickproof.h"

static void failed(void) { *(volatile int *)0 = 0; }

int main(void)
{
    uint8_t guard[2] = {42, 43};
    nondet_bytes(NULL, 0);
    nondet_bytes(guard + 1, 0);
    if (guard[0] != 42 || guard[1] != 43) failed();
    nondet_bytes(guard, 1);
    if (guard[1] != 43) failed();
    return 0;
}
