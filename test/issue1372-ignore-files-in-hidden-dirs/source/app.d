import std.stdio;

void main()
{
    version(UseHiddenFile)
    {
        import hello;
        helloFun();
    }
    else
    {
        static assert(!__traits(compiles, {
            import hello;
            helloFun();
        }));
        writeln("no hidden file compiled");
    }
}
