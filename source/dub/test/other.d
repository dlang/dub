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

// Test for https://github.com/dlang/dub/pull/2481
// Make sure packages found with `add-path` take priority.
unittest
{
    const AddPathDir = TestDub.Paths.temp ~ "addpath/";
    const BDir = AddPathDir ~ "b/";
    scope dub = new TestDub((scope FSEntry root) {
            root.writeFile(TestDub.ProjectPath ~ "dub.json",
                `{ "name": "a", "dependencies": { "b": "~>1.0" } }`);

            root.writePackageFile("b", "1.0.0", `name "b"
version "1.0.0"`, PackageFormat.sdl);
            root.mkdir(BDir);
            root.writeFile(BDir ~ "dub.json", `{"name": "b", "version": "1.0.0" }`);
    });

    dub.loadPackage();
    assert(!dub.project.hasAllDependencies());
    dub.upgrade(UpgradeOptions.select);
    // Test that without add-path, we get a package in the userPackage
    const oldDir = dub.project.getDependency("b", true).path();
    assert(oldDir == TestDub.Paths.userPackages ~ "packages/b/1.0.0/b/",
           oldDir.toNativeString());
    // Now run `add-path`
    dub.addSearchPath(AddPathDir.toNativeString(), dub.defaultPlacementLocation);
    // We need a new instance to test
    scope newDub = dub.newTest();
    newDub.loadPackage();
    assert(newDub.project.hasAllDependencies());
    const actualDir = newDub.project.getDependency("b", true).path();
    assert(actualDir == BDir, actualDir.toNativeString());
}
