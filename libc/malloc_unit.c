// quickproof libc/malloc_unit.c: the unit that owns malloc and free.
//
// Built with tools/clight.sh, malloc/free become the externals quickproof_malloc/quickproof_free of the
// honest environment (QuickProof.Env).  In a VSU-style proof this unit's component provides VST's
// mem_mgr resource (create_mem_mgr) and exports malloc/free; the placeholder function only makes both
// externals part of the unit.

#include <stddef.h>

extern void *malloc(size_t);
extern void free(void *);

int malloc_placeholder (void) {
  return &malloc, &free, 0;
}
