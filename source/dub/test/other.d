/*******************************************************************************

    Tests that don't fit in existing categories

*******************************************************************************/

module dub.test.others;

version (unittest):

import std.algorithm;
import std.format;
import dub.test.base;

// https://github.com/dlang/dub/issues/2696
unittest
{
    const ValidURL = `git+https://example.com/dlang/dub`;
    // Taken from a commit in the dub repository
    const ValidHash = "54339dff7ce9ec24eda550f8055354f712f15800";
    const Template = `{"name": "%s", "dependencies": {
"dep1": { "repository": "%s", "version": "%s" }}}`;

    scope dub = new TestDub();
    dub.packageManager.addTestSCMPackage(
        Repository(ValidURL, ValidHash),
        // Note: SCM package are always marked as using `~master`
        dub.makeTestPackage(`{ "name": "dep1" }`, Version(`~master`)),
    );

    // Invalid URL, valid hash
    const a = Template.format("a", "git+https://nope.nope", ValidHash);
    try
        dub.loadPackage(dub.addTestPackage(a, Version("1.0.0")));
    catch (Exception exc)
        assert(exc.message.canFind("Unable to fetch"));

    // Valid URL, invalid hash
    const b = Template.format("b", ValidURL, "invalid");
    try
        dub.loadPackage(dub.addTestPackage(b, Version("1.0.0")));
    catch (Exception exc)
        assert(exc.message.canFind("Unable to fetch"));

    // Valid URL, valid hash
    const c = Template.format("c", ValidURL, ValidHash);
    dub.loadPackage(dub.addTestPackage(c, Version("1.0.0")));
    assert(dub.project.hasAllDependencies());
    assert(dub.project.getDependency("dep1", true), "Missing 'dep1' dependency");
}
