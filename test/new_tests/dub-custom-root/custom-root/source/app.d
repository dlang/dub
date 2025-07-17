import std.file;
import std.path;
import std.stdio;

void main()
{
	// run me from test/dub-custom-root with dub --root=custom-root
	// TODO: new_tests => tests
	assert(getcwd.baseName == "dub-custom-root", getcwd);
}
