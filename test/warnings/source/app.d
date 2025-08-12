import std.stdio;

version(Include_Warning)
{
	void foo()
	{
		return;
		writeln("unreachable statement");
	}
}

version(Include_Deprecation)
{
	deprecated void bar()
	{
		writeln("called bar");
	}
}

void main()
{
	version(Include_Warning)
		foo();

	version(Include_Deprecation)
		bar();

	writeln("done");
}
