module test_build_deep;

import common;

import std.array;
import std.file;
import std.path;
import std.process;
import std.stdio;

void main()
{
    const packdir = getcwd.buildPath("sample");

    if (exists(dubHome))
    {
        rmdirRecurse(dubHome);
    }

    // testing the regular way first: `dub build` only builds what is needed
    // (urld is downloaded but not built)
    const dubBuildProg = [dub, "build"];
    log("running ", dubBuildProg.join(" "), " ...");
    auto dubBuild = spawnProcess(dubBuildProg, null, Config.none, packdir);
    wait(dubBuild);
    assert(exists(buildPath(dubHome, "cache", "pack")));
    assert(isDir(buildPath(dubHome, "cache", "pack")));
    assert(exists(buildPath(dubHome, "packages", "urld")));
    assert(isDir(buildPath(dubHome, "packages", "urld")));
    assert(!exists(buildPath(dubHome, "cache", "urld")));

    // now testing the --deep switch: `dub build --deep` will build urld
    const dubBuildDeepProg = [dub, "build", "--deep"];
    log("running ", dubBuildDeepProg.join(" "), " ...");
    auto dubBuildDeep = spawnProcess(dubBuildDeepProg, null, Config.none, packdir);
    wait(dubBuildDeep);
    assert(exists(buildPath(dubHome, "cache", "pack")));
    assert(isDir(buildPath(dubHome, "cache", "pack")));
    assert(exists(buildPath(dubHome, "packages", "urld")));
    assert(isDir(buildPath(dubHome, "packages", "urld")));
    assert(exists(buildPath(dubHome, "cache", "urld")));
    assert(isDir(buildPath(dubHome, "cache", "urld")));
}
