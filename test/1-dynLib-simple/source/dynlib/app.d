module dynlib.app;
import std.stdio;
version (unittest) {} else version (Windows) version (DigitalMars)
{
    import core.sys.windows.dll;
    mixin SimpleDllMain;
}

export void entry()
{
    writeln(__FUNCTION__);
}
