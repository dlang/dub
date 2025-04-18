import std.file;
import std.path;
import std.stdio;

void main()
{
	// run me from test/integration/ with dub --root=test/integration/dub-custom-root
	assert(getcwd.baseName == "integration", getcwd);
	writeln("ok");
}
