module dynlib.app;
import std.stdio;
import staticlib.app;
version (unittest) {} else version (Windows) version (DigitalMars)
{
    import core.sys.windows.dll;
    mixin SimpleDllMain;
}

void foo()
{
    entry();
}
