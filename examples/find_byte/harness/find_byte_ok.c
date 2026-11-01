/* Law find_byte_ok: for every buffer of up to 1 KiB and every byte c, find_byte returns an index r <= n, and
   when r < n the byte at r is c.  (A stronger law would also say that no byte before r is c.) */
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
    uint8_t c = nondet_u8();           /* any byte to look for */

    size_t r = find_byte(buf, n, c);
    qp_assert(r <= n);
    if (r < n)
        qp_assert(buf[r] == c);

    free(buf);
    return 0;
}
