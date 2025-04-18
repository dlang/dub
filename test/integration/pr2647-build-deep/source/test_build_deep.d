module test_build_deep;

import std.array;
import std.file;
import std.path;
import std.process;
import std.stdio;

void main()
{
    const dubhome = __FILE_FULL_PATH__.dirName().dirName().buildNormalizedPath("dubhome");
    const packdir = __FILE_FULL_PATH__.dirName().dirName().buildNormalizedPath("pack");
    const dub = absolutePath(environment["DUB"]);

    if (exists(dubhome))
    {
        rmdirRecurse(dubhome);
    }

    scope (success)
    {
        // leave dubhome in the tree for analysis in case of failure
        rmdirRecurse(dubhome);
    }

    const string[string] env = [
        "DUB_HOME": dubhome,
    ];

    // testing the regular way first: `dub build` only builds what is needed
    // (urld is downloaded but not built)
    const dubBuildProg = [dub, "build"];
    writefln("running %s ...", dubBuildProg.join(" "));
    auto dubBuild = spawnProcess(dubBuildProg, stdin, stdout, stderr, env, Config.none, packdir);
    wait(dubBuild);
    assert(exists(buildPath(dubhome, "cache", "pack")));
    assert(isDir(buildPath(dubhome, "cache", "pack")));
    assert(exists(buildPath(dubhome, "packages", "urld")));
    assert(isDir(buildPath(dubhome, "packages", "urld")));
    assert(!exists(buildPath(dubhome, "cache", "urld")));

    // now testing the --deep switch: `dub build --deep` will build urld
    const dubBuildDeepProg = [dub, "build", "--deep"];
    writefln("running %s ...", dubBuildDeepProg.join(" "));
    auto dubBuildDeep = spawnProcess(dubBuildDeepProg, stdin, stdout, stderr, env, Config.none, packdir);
    wait(dubBuildDeep);
    assert(exists(buildPath(dubhome, "cache", "pack")));
    assert(isDir(buildPath(dubhome, "cache", "pack")));
    assert(exists(buildPath(dubhome, "packages", "urld")));
    assert(isDir(buildPath(dubhome, "packages", "urld")));
    assert(exists(buildPath(dubhome, "cache", "urld")));
    assert(isDir(buildPath(dubhome, "cache", "urld")));
}
