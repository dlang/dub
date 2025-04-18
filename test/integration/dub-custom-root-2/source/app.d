import std.file;
import std.path;
import std.stdio;
import std.string;

void main()
{
	// run me from test/integration/ with dub --root=dub-custom-root
	string cwd = getcwd.chomp("/");
	assert(cwd.endsWith("test/integration/dub-custom-root-2/source"), cwd);
	writeln("ok");
}
