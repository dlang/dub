import std.stdio;

version (must_be_defined) {} else static assert(0, "Expected must_be_defined to be set");

extern (C) void depend2_func()
{
	writeln("depend2_func");
}
