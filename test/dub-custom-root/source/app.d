import std.file;
import std.path;
import std.stdio;

void main()
{
	// run me from test/ with dub --root=test/dub-custom-root
	assert(getcwd.baseName == "test", getcwd);
	writeln("ok");
}
