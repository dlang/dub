/+ dub.sdl:
   name "single-file-test-dynamic-library"
   targetType "dynamicLibrary"
+/

module hellolib;

version(Windows)
{
    import core.sys.windows.dll;

    mixin SimpleDllMain;
}
