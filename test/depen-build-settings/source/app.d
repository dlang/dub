import std.stdio;
import std.file;

extern (C) void depend1_func();

void main()
{
	writeln("Edit source/app.d to start your project.");
	depend1_func();
	assert(exists("depend2.json"));
	assert(exists("depend.json"));
}
