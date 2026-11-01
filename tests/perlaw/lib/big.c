/* A unit no law references (the stand-in for an imported fuzz target's cone in another law). */
struct big { unsigned x[4]; };
unsigned big_first(struct big *b) { return b->x[0]; }
