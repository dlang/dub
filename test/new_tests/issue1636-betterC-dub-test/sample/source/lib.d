import core.stdc.stdio : printf;

version(D_BetterC) {} else static assert(false);

int foo()
{
	return 2;
}

unittest
{
	assert(foo == 2);
	printf("TEST_WAS_RUN\n");
}
