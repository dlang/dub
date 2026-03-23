import std.stdio;
import std.path;
import std.file;

void main()
{
    assert(baseName(getcwd()) == "bin");
    writeln("ok");
}
