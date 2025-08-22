module describe_artifact_path;

import common;

import std.path;
import std.file;
import std.process;
import std.stdio;
import std.json;

void main()
{
    if (exists(dubHome))
    {
        rmdirRecurse(dubHome);
    }

    const fetchProgram = [
        environment["DUB"],
        "fetch",
        "gitcompatibledubpackage@1.0.4",
    ];
    auto dubFetch = spawnProcess(fetchProgram);
    wait(dubFetch);

    const describeProgram = [
        dub,
        "describe",
        "--build=debug",
        "--config=lib",
        "gitcompatibledubpackage@1.0.4",
    ];
    auto result = execute(describeProgram);
	if (result.status != 0)
		die("expected dub describe to return zero");
    auto json = parseJSON(result.output);

    auto cacheFile = json["targets"][0]["cacheArtifactPath"].str;
	if(exists(cacheFile))
		die("found cache file in virgin dubhome");

    const buildProgram = [
        dub,
        "build",
        "--build=debug",
        "--config=lib",
        "gitcompatibledubpackage@1.0.4",
    ];
    auto dubBuild = spawnProcess(buildProgram);
    wait(dubBuild);

	if (!exists(cacheFile))
		die("did not find cache file after build");
}
