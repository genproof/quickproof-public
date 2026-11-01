/* mylib.h: your library.  Replace this example with your own code. */
#ifndef MYLIB_H
#define MYLIB_H
#include <stddef.h>
#include <stdint.h>

/* count_byte: how many of the bytes buf[0..n-1] are equal to c. */
size_t count_byte(const uint8_t *buf, size_t n, uint8_t c);

#endif
