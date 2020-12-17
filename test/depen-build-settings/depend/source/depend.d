import std.stdio;

extern (C) void depend2_func();

extern (C) void depend1_func()
{
	writeln("depend1_func");
	depend2_func();
}
