/* Law rle_decode_safe: for every input of up to 4 KiB, rle_decode never reports more output than the buffer it
   was given, and never reads or writes out of bounds. */
#include <stdlib.h>
#include "quickproof.h"
#include "rle.h"

int main(void) {
    size_t n = nondet_size();          /* any length ...    */
    qp_assume(n <= 4096);              /* ... up to 4 KiB   */
    uint8_t *in = malloc(n);
    if (in == NULL)
        return 0;
    nondet_bytes(in, n);               /* any bytes         */

    uint8_t out[256];
    size_t m = rle_decode(in, n, out, sizeof out);
    qp_assert(m <= sizeof out);

    free(in);
    return 0;
}
