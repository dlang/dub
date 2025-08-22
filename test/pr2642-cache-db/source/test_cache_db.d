module test_cache_db;

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
        dub,
        "fetch",
        "gitcompatibledubpackage@1.0.4",
    ];
    auto dubFetch = spawnProcess(fetchProgram);
    wait(dubFetch);

    const buildProgramLib = [
		dub,
        "build",
        "--build=debug",
        "--config=lib",
        "gitcompatibledubpackage@1.0.4",
    ];
    auto dubBuild = spawnProcess(buildProgramLib);
    wait(dubBuild);

    const buildProgramExe = [
        dub,
        "build",
        "--build=debug",
        "--config=exe",
        "gitcompatibledubpackage@1.0.4",
    ];
    dubBuild = spawnProcess(buildProgramExe);
    wait(dubBuild);

    const buildDbPath = buildNormalizedPath(dubHome, "cache", "gitcompatibledubpackage", "1.0.4", "db.json");
    assert(exists(buildDbPath), buildDbPath ~ " should exist");
    const buildDbStr = readText(buildDbPath);
    auto json = parseJSON(buildDbStr);
    assert(json.type == JSONType.array, "build db should be an array");
    assert(json.array.length == 2, "build db should have 2 entries");

    auto db = json.array[0].object;

    void assertArray(string field)
    {
        assert(field in db, "db.json should have an array field " ~ field);
        assert(db[field].type == JSONType.array, "expected field " ~ field ~ " to be an array");
    }

    void assertString(string field, string value = null)
    {
        assert(field in db, "db.json should have an string field " ~ field);
        assert(db[field].type == JSONType.string, "expected field " ~ field ~ " to be a string");
        if (value)
            assert(db[field].str == value, "expected field " ~ field ~ " to equal " ~ value);
    }

    assertArray("architecture");
    assertString("buildId");
    assertString("buildType", "debug");
    assertString("compiler");
    assertString("compilerBinary");
    assertString("compilerVersion");
    assertString("configuration", "lib");
    assertString("package", "gitcompatibledubpackage");
    assertArray("platform");
    assertString("targetBinaryPath");
    assertString("version", "1.0.4");

    auto binName = db["targetBinaryPath"].str;
    assert(isFile(binName), "expected " ~ binName ~ " to be a file.");

    db = json.array[1].object;

    assertArray("architecture");
    assertString("buildId");
    assertString("buildType", "debug");
    assertString("compiler");
    assertString("compilerBinary");
    assertString("compilerVersion");
    assertString("configuration", "exe");
    assertString("package", "gitcompatibledubpackage");
    assertArray("platform");
    assertString("targetBinaryPath");
    assertString("version", "1.0.4");

    binName = db["targetBinaryPath"].str;
    assert(isFile(binName), "expected " ~ binName ~ " to be a file.");
}
