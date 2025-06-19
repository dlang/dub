module app;

int main()
{
    version (special)
    {
        // Expected.
		return 0;
    }
    else
    {
        // Failure.
		return 1;
    }
}
