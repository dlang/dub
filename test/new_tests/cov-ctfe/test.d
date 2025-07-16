int f(int x)
{
	return x + 1;
}

int g(int x)
{
	return x * 2;
}

enum gResult = g(12);			// execute g() at compile-time

int main(string[] args)
{
	assert(f(11) + gResult == 36);
	return 0;
}
