module dynlib.app;
import std.stdio;

export void entry()
{
    writeln(__FUNCTION__);
}
