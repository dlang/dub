import std.file;
import std.path;
import std.stdio;
import std.string;

void main()
{
	// run me from test/dub-custom-root with dub --root=custom-root-2
	string cwd = getcwd;
	immutable expected = buildPath("test", "dub-custom-root", "custom-root-2", "source");
	assert(cwd.endsWith(expected), cwd);
}
