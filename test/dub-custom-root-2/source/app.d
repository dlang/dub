import std.file;
import std.path;
import std.stdio;
import std.string;

void main()
{
	// run me from test/ with dub --root=dub-custom-root
	string cwd = getcwd.chomp("/");
	assert(cwd.endsWith("test/dub-custom-root-2/source"), cwd);
	writeln("ok");
}
