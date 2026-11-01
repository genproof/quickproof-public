/* error.c: a stand-in for aws-c-common's stubs/error.c, written for the tests of tools/qp import-cbmc. */
int aws_raise_error_private(int err)
{
	(void) err;
	return -1;
}
