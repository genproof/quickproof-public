/* Law adler32_split: for every buffer of up to 4 KiB and every split point, checksumming the buffer in two
   pieces gives the same Adler-32 as checksumming it in one call. */
#include <stdlib.h>
#include "quickproof.h"
#include "adler32.h"

int main(void) {
    size_t n = nondet_size();          /* any length up to 4 KiB */
    qp_assume(n <= 4096);
    uint8_t *buf = malloc(n);
    if (buf == NULL)
        return 0;
    nondet_bytes(buf, n);              /* any bytes */
    size_t k = nondet_size();          /* any split point */
    qp_assume(k <= n);

    uint32_t whole = adler32(1, buf, n);
    uint32_t first = adler32(1, buf, k);
    uint32_t both = adler32(first, buf + k, n - k);
    qp_assert(whole == both);

    free(buf);
    return 0;
}
