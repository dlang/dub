void main()
{
	import std.stdio : write;
	static if (__traits(compiles, import("inputs/first.txt")))
		write("first");
	static if (__traits(compiles, import("inputs/second.txt")))
		write("second");
}
