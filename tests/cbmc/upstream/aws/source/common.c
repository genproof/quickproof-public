/* common.c: a stand-in for aws-c-common's source/common.c, written for the tests of tools/qp import-cbmc. */
#include <aws/common/math.h>

static int init_count;

int aws_common_init_count(void)
{
	return init_count;
}
