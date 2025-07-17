import std.stdio;
import std.file;

extern (C) void depend1_func();

version (must_be_defined) static assert(0, "Expected must_be_defined not to be set");

void main()
{
	writeln("Edit source/app.d to start your project.");
	depend1_func();
	assert(!exists("depen-build-settings.json"));
	assert(exists("depend2.json"));
	assert(exists("depend.json"));
}
