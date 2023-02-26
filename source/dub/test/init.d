/*******************************************************************************

    Tests for `dub init`

*******************************************************************************/

module dub.test.init;

version (unittest):

import dub.test.base;

import std.array;

/// Test dub init works
unittest
{
    string[][] argSet = [
        [],
        [ "-f", "sdl" ],
        [ "-f", "json" ],
    ];

    foreach (arg; argSet) {
        scope dub = new TestCLIApp();
        auto res = dub.run(["init", "-n", "pack"] ~ arg);
        assert(res.status == 0);
        auto format = arg.length ? arg[1] : "json";
        assert(std.file.exists(dub.path.buildPath("pack", "dub." ~ format)),
               "dub." ~ format ~ " does not exists");
    }
}

/// Test `dub init` correctly fails with a non-existing dependency
unittest
{
    string[][] argSet = [
        [],
        [ "-f", "sdl" ],
        [ "-f", "json" ],
    ];

    foreach (arg; argSet) {
        scope dub = new TestCLIApp();
        auto res = dub.run(
            ["init", "-n", "pack", "logger", "PACKAGE_DONT_EXIST"] ~ arg);
        assert(res.status != 0);
        foreach (file; std.file.dirEntries(dub.path, std.file.SpanMode.shallow))
            assert(0, "Found file: " ~ file);
        // Note: While offline, you might get an error for both
        assert(res.stderr.canFind("Error Couldn't find package: PACKAGE_DONT_EXIST.") ||
               res.stderr.canFind("Error Couldn't find packages: logger, PACKAGE_DONT_EXIST."));
    }
}

/// Test a more advanced init scenario
unittest
{
    scope const expectedDeps = ["logger", "openssl", "vibe-d"].sort;

    foreach (fmt; ["sdl", "json"]) {
        scope dub = new TestCLIApp();
        auto res = dub.run(
            ["init", "-n", "pack", "openssl", "logger", "--type=vibe.d", "--format", fmt]);
        assert(res.status == 0);

        scope lib = dub.makeLib(dub.path.buildPath("pack"));
        lib.loadPackage();
        assert(lib.project !is null);
        const actualDeps = lib.project.rootPackage.getAllDependencies.map!(dep => dep.name)
            .array.sort;

        assert(actualDeps == expectedDeps);
    }
}

/// Interactive init tests
unittest
{
    scope dub = new TestCLIApp();
    auto res = dub.run(["init"], "sdl\ntest\ndesc\nauthor\ngpl\ncopy\n\n");
    assert(res.status == 0);
    const content = std.file.read(dub.path.buildPath("dub.sdl"));
    const expected = `name "test"
description "desc"
authors "author"
copyright "copy"
license "gpl"
`;
    assert(content == expected);
}
