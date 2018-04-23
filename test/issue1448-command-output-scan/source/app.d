int main()
{
	return 0;
}

unittest {
	import std.stdio;
	writeln(import("file"));
	assert(import("file") == "string from non-default dir set with script.sh");
}
