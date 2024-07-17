/+ dub.json: {
   "name": "dynlib-monolith-script"
} +/
module dynlib_monolith_script;

import std.algorithm, std.path, std.process, std.stdio;

int main()
{
    const dc = environment.get("DC", "dmd");
    if (!dc.startsWith("ldc"))
    {
        writeln("Skipping test, needs LDC");
        return 0;
    }

    // enforce a full build (2 static libs, 1 dynamic one) and collect -v output
    enum projDir = dirName(__FILE_FULL_PATH__).buildPath("dynLib-monolith");
    const res = execute([environment.get("DUB", "dub"), "build", "-f", "-v", "--root", projDir]);

    int errorOut(string msg)
    {
        writeln("Error: " ~ msg);
        writeln("===========================================================");
        writeln(res.output);
        writeln("===========================================================");
        return 1;
    }

    if (res.status != 0)
        return errorOut("The dub invocation failed:");

    version (Windows) enum needle = " -fvisibility=hidden -dllimport=defaultLibsOnly";
    else              enum needle = " -fvisibility=hidden";
    if (res.output.count(needle) != 3)
        return errorOut("Cannot find exactly 3 occurrences of '" ~ needle ~ "' in the verbose dub output:");

    return 0;
}
