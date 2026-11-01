/* Law count_byte_ok: for every buffer of up to 1 KiB and every byte c, count_byte returns at most n, and at
   least 1 when the first byte is c. */
#include <stdlib.h>
#include "quickproof.h"
#include "mylib.h"

int main(void) {
    size_t n = nondet_size();          /* any length up to 1 KiB */
    qp_assume(n <= 1024);
    uint8_t *buf = malloc(n);
    if (buf == NULL)
        return 0;
    nondet_bytes(buf, n);              /* any bytes */
    uint8_t c = nondet_u8();           /* any byte to count */

    size_t r = count_byte(buf, n, c);
    qp_assert(r <= n);
    if (n > 0 && buf[0] == c)
        qp_assert(r >= 1);

    free(buf);
    return 0;
}
