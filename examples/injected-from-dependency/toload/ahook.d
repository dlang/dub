module toload.ahook;

version(D_BetterC) {
    pragma(crt_constructor)
    extern(C) void someInitializer() {
        import core.stdc.stdio;
        printf("Hook ran!\n");
    }
} else {
    shared static this() {
        import std.stdio;
        writeln("We have a runtime!!!!");
    }
}
