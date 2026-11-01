/* math.h: a stand-in for aws-c-common's checked arithmetic, written for the tests of tools/qp import-cbmc (it
 * is not aws-c-common's code).  Under -DCBMC it uses CBMC's overflow predicates, as aws-c-common's
 * math.cbmc.inl does: the importer refuses that unless the library is built without CBMC (--undef CBMC). */
#ifndef AWS_COMMON_MATH_H
#define AWS_COMMON_MATH_H
#include <stdint.h>
#include <stddef.h>

#define AWS_OP_SUCCESS 0
#define AWS_OP_ERR (-1)

#ifdef CBMC
static inline int aws_add_u64_checked(uint64_t a, uint64_t b, uint64_t *r)
{
	if (__CPROVER_overflow_plus(a, b))
		return AWS_OP_ERR;
	*r = a + b;
	return AWS_OP_SUCCESS;
}
#else
static inline int aws_add_u64_checked(uint64_t a, uint64_t b, uint64_t *r)
{
	if (b > 0 && a > UINT64_MAX - b)
		return AWS_OP_ERR;
	*r = a + b;
	return AWS_OP_SUCCESS;
}
#endif

static inline int aws_add_u32_checked(uint32_t a, uint32_t b, uint32_t *r)
{
	if (b > 0 && a > UINT32_MAX - b)
		return AWS_OP_ERR;
	*r = a + b;
	return AWS_OP_SUCCESS;
}

int aws_common_init_count(void);
#endif
