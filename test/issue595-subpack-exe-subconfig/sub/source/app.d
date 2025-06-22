import std.stdio;

void main()
{
    version (special)
    {
        writeln("Special version");
    }
    else
    {
        writeln("Standard version");
    }
}
