module describe_artifact_path;

import std.path;
import std.file;
import std.process;
import std.stdio;
import std.json;

void main()
{
    const dubhome = __FILE_FULL_PATH__.dirName().dirName().buildNormalizedPath("dubhome");
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
    const fetchProgram = [
        environment["DUB"],
        "fetch",
        "gitcompatibledubpackage@1.0.4",
    ];
    auto dubFetch = spawnProcess(fetchProgram, stdin, stdout, stderr, env);
    wait(dubFetch);


    const describeProgram = [
        environment["DUB"],
        "describe",
        "--compiler=" ~ environment["DC"],
        "--build=debug",
        "--config=lib",
        "gitcompatibledubpackage@1.0.4",
    ];
    auto result = execute(describeProgram, env);
    assert(result.status == 0, "expected dub describe to return zero");
    auto json = parseJSON(result.output);

    auto cacheFile = json["targets"][0]["cacheArtifactPath"].str;
    assert(!exists(cacheFile), "found cache file in virgin dubhome");

    const buildProgram = [
        environment["DUB"],
        "build",
        "--compiler=" ~ environment["DC"],
        "--build=debug",
        "--config=lib",
        "gitcompatibledubpackage@1.0.4",
    ];
    auto dubBuild = spawnProcess(buildProgram, stdin, stdout, stderr, env);
    wait(dubBuild);

    assert(exists(cacheFile), "did not find cache file after build");
}
