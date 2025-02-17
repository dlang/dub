module lib;

int foo(int a, int b)
{
	return a + b;
}

unittest
{
	assert(foo(1, 2) == 3);
}
