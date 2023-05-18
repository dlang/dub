module test_cache_db;

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

    const string[string] env = [
        "DUB_HOME": dubhome,
    ];
    const fetchProgram = [
        environment["DUB"],
        "fetch",
        "vibe-d@0.9.6",
    ];
    auto dubFetch = spawnProcess(fetchProgram, stdin, stdout, stderr, env);
    wait(dubFetch);
    const buildProgram = [
        environment["DUB"],
        "build",
        "--build=debug",
        "vibe-d:http@0.9.6",
    ];
    auto dubBuild = spawnProcess(buildProgram, stdin, stdout, stderr, env);
    wait(dubBuild);

    scope (success)
    {
        // leave dubhome in the tree for analysis in case of failure
        rmdirRecurse(dubhome);
    }

    const buildDbPath = buildNormalizedPath(dubhome, "cache", "vibe-d", "0.9.6", "+http", "db.json");
    assert(exists(buildDbPath), buildDbPath ~ " should exist");
    const buildDbStr = readText(buildDbPath);
    auto json = parseJSON(buildDbStr);
    assert(json.type == JSONType.array, "build db should be an array");
    assert(json.array.length == 1);
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
    assertString("configuration", "library");
    assertString("package", "vibe-d:http");
    assertArray("platform");
    assertString("targetBinaryPath");
    assertString("version", "0.9.6");

    const binName = db["targetBinaryPath"].str;
    assert(isFile(binName), "expected " ~ binName ~ " to be a file.");
}
