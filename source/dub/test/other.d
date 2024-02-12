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
    const Template = `{"name": "%s", "version": "1.0.0", "dependencies": {
"dep1": { "repository": "%s", "version": "%s" }}}`;

    scope dub = new TestDub((scope FSEntry fs) {
        // Invalid URL, valid hash
        fs.writePackageFile("a", "1.0.0", Template.format("a", "git+https://nope.nope", ValidHash));
        // Valid URL, invalid hash
        fs.writePackageFile("b", "1.0.0", Template.format("b", ValidURL, "invalid"));
        // Valid URL, valid hash
        fs.writePackageFile("c", "1.0.0", Template.format("c", ValidURL, ValidHash));
    });
    dub.packageManager.addTestSCMPackage(
        Repository(ValidURL, ValidHash), `{ "name": "dep1" }`);

    try
        dub.loadPackage(dub.packageManager.getPackage(PackageName("a"), Version("1.0.0")));
    catch (Exception exc)
         assert(exc.message.canFind("Unable to fetch"));

    try
        dub.loadPackage(dub.packageManager.getPackage(PackageName("b"), Version("1.0.0")));
    catch (Exception exc)
        assert(exc.message.canFind("Unable to fetch"));

    dub.loadPackage(dub.packageManager.getPackage(PackageName("c"), Version("1.0.0")));
    assert(dub.project.hasAllDependencies());
    assert(dub.project.getDependency("dep1", true), "Missing 'dep1' dependency");
}
