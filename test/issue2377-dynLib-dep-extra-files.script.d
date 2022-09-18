/+ dub.sdl:
name "issue2377_dynlib_dep_extra_files"
+/

module issue2377_dynlib_dep_extra_files.script;

import std.exception : enforce;
import std.file;
import std.path;

version (DigitalMars) version (Windows) version = DMD_Windows;
version (DMD_Windows) {
    void main() {
        import std.stdio;
        writeln("WARNING: skipping test '" ~ __FILE_FULL_PATH__.baseName ~ "' with DMD on Windows.");
    }
} else:

void main() {
    import std.process : environment;

    version (Windows) enum exeExt = ".exe";
    else              enum exeExt = "";
    const dub = environment.get("DUB", buildPath(__FILE_FULL_PATH__.dirName.dirName, "bin", "dub"~exeExt));

    enum testDir = buildPath(__FILE_FULL_PATH__.dirName, "issue2377-dynLib-dep-extra-files");

    // 1. `parent` as root package (depending on dynamic/static dep1, which depends on dynamic/static dep2)
    chdir(buildPath(testDir, "parent"));
    if (exists("output"))
        rmdirRecurse("output");

    // 1.1 dynlib config
    run(dub ~ " build -c dynlib");
    chdir("output/dynlib");
    assertDynLibExists("parent");
    assertDynLibExists("dep1");
    assertDynLibExists("dep2");
    version (Windows) {
        assertFileExists("parent.pdb");
        assertFileExists("parent.lib");
        assertFileExists("parent.exp");
        assertFileExists("dep1.pdb");
        assertFileExists("dep1.lib");
        assertFileExists("dep1.exp");
        assertFileExists("dep2.pdb");
        assertFileExists("dep2.lib");
        assertFileExists("dep2.exp");
    }
    chdir("../..");

    // 1.2 dynlib_static config
    run(dub ~ " build -c dynlib_static");
    chdir("output/dynlib_static");
    assertDynLibExists("parent");
    version (Windows) {
        assertFileExists("parent.pdb");
        assertFileExists("parent.lib");
        assertFileExists("parent.exp");
    }
    enforce(!canFindFiles("*dep*"), "unexpected dependency files in statically linked dynlib output dir");
    chdir("../..");

    // 1.3 exe_static config
    run(dub ~ " build -c exe_static");
    chdir("output/exe_static");
    version (Windows) run(`.\parent.exe`);
    else              run("./parent");
    version (Windows) {
        assertFileExists("parent.pdb");
        enforce(!exists("parent.lib"), "unexpected import .lib for executable");
        enforce(!exists("parent.exp"), "unexpected .exp file for executable");
    }
    enforce(!canFindFiles("*dep*"), "unexpected dependency files in statically linked executable output dir");
    chdir("../..");

    // 1.4 exe_dynamic config
    run(dub ~ " build -c exe_dynamic");
    chdir("output/exe_dynamic");
    version (Windows) run(`.\parent.exe`);
    else              run(`LD_LIBRARY_PATH=".:${LD_LIBRARY_PATH:-}" ./parent`);
    assertDynLibExists("dep1");
    assertDynLibExists("dep2");
    version (Windows) {
        assertFileExists("dep1.pdb");
        assertFileExists("dep2.pdb");
        enforce(!canFindFiles("*.lib"), "unexpected import libs in dynamically linked executable output dir");
        enforce(!canFindFiles("*.exp"), "unexpected .exp files in dynamically linked executable output dir");
    }
    chdir("../..");

    // 2. `framework` as root package (targetType `none`)
    chdir(buildPath(testDir, "framework"));
    run(dub ~ " build");
    assertDynLibExists("dep1");
    assertDynLibExists("dep2");
    version (Windows) {
        assertFileExists("dep1.pdb");
        assertFileExists("dep1.lib");
        assertFileExists("dep1.exp");
        assertFileExists("dep2.pdb");
        assertFileExists("dep2.lib");
        assertFileExists("dep2.exp");
    }
}

void run(string command) {
    import std.process;
    const status = spawnShell(command).wait();
    enforce(status == 0, "command '" ~ command ~ "' failed");
}

void assertFileExists(string path) {
    enforce(exists(path), "expected file '" ~ path ~ "' not found");
}

void assertDynLibExists(string name) {
    version (Windows) {
        enum prefix = "";
        enum suffix = ".dll";
    } else version (OSX) {
        enum prefix = "lib";
        enum suffix = ".dylib";
    } else {
        enum prefix = "lib";
        enum suffix = ".so";
    }

    assertFileExists(prefix ~ name ~ suffix);
}

bool canFindFiles(string pattern) {
    auto entries = dirEntries(".", pattern, SpanMode.shallow);
    return !entries.empty();
}
