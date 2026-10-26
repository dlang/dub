/*******************************************************************************

    Test for dependencies

    This module is mostly concerned with dependency resolutions and visible user
    behavior. Tests that check how different recipe would interact with one
    another, and how conflicts are resolved or reported, belong here.

    The project (the loaded package) is usually named 'a' and dependencies use
    single-letter, increasing name, for simplicity. Version 1.0.0 is used where
    versions do not matter. Packages are usually created in reverse dependency
    order when possible, unless the creation order matters.

    Test that deal with dependency resolution should not concern themselves with
    the registry: instead, packages are added to the `PackageManager`, as that
    makes testing the core logic more robust without adding a layer
    of complexity brought by the `PackageSupplier`.

    Most tests have 3 parts: First, setup the various packages. Then, run
    `dub.upgrade(UpgradeOptions.select)` to create the selection. Finally,
    run tests on the resulting state.

*******************************************************************************/

module dub.test.dependencies;

version (unittest):

import dub.test.base;

// Ensure that simple dependencies get resolved correctly
unittest
{
    scope dub = new TestDub((scope Filesystem root) {
            root.writeFile(TestDub.ProjectPath ~ "dub.sdl", `name "a"
version "1.0.0"
dependency "b" version="*"
dependency "c" version="*"
`);
            root.writePackageFile("b", "1.0.0", `name "b"
version "1.0.0"`, PackageFormat.sdl);
            root.writePackageFile("c", "1.0.0", `name "c"
version "1.0.0"`, PackageFormat.sdl);
        });
    dub.loadPackage();

    dub.upgrade(UpgradeOptions.select);

    assert(dub.project.hasAllDependencies(), "project has missing dependencies");
    assert(dub.project.getDependency("b", true), "Missing 'b' dependency");
    assert(dub.project.getDependency("c", true), "Missing 'c' dependency");
    assert(dub.project.getDependency("no", true) is null, "Returned unexpected dependency");
}

// Test that indirect dependencies get resolved correctly
unittest
{
    scope dub = new TestDub((scope Filesystem root) {
            root.writeFile(TestDub.ProjectPath ~ "dub.sdl", `name "a"
dependency "b" version="*"`);
            root.writePackageFile("b", "1.0.0", `name "b"
version "1.0.0"
dependency "c" version="*"`, PackageFormat.sdl);
            root.writePackageFile("c", "1.0.0", `name "c"
version "1.0.0"`, PackageFormat.sdl);
    });
    dub.loadPackage();

    dub.upgrade(UpgradeOptions.select);

    assert(dub.project.hasAllDependencies(), "project has missing dependencies");
    assert(dub.project.getDependency("b", true), "Missing 'b' dependency");
    assert(dub.project.getDependency("c", true), "Missing 'c' dependency");
    assert(dub.project.getDependency("no", true) is null, "Returned unexpected dependency");
}

// Simple diamond dependency
unittest
{
    scope dub = new TestDub((scope Filesystem root) {
            root.writeFile(TestDub.ProjectPath ~ "dub.sdl", `name "a"
dependency "b" version="*"
dependency "c" version="*"`);
            root.writePackageFile("b", "1.0.0", `name "b"
version "1.0.0"
dependency "d" version="*"`, PackageFormat.sdl);
            root.writePackageFile("c", "1.0.0", `name "c"
version "1.0.0"
dependency "d" version="*"`, PackageFormat.sdl);
            root.writePackageFile("d", "1.0.0", `name "d"
version "1.0.0"`, PackageFormat.sdl);

    });
    dub.loadPackage();

    dub.upgrade(UpgradeOptions.select);

    assert(dub.project.hasAllDependencies(), "project has missing dependencies");
    assert(dub.project.getDependency("b", true), "Missing 'b' dependency");
    assert(dub.project.getDependency("c", true), "Missing 'c' dependency");
    assert(dub.project.getDependency("d", true), "Missing 'd' dependency");
    assert(dub.project.getDependency("no", true) is null, "Returned unexpected dependency");
}

// Missing dependencies trigger an error
unittest
{
    scope dub = new TestDub((scope Filesystem root) {
            root.writeFile(TestDub.ProjectPath ~ "dub.sdl", `name "a"
dependency "b" version="*"`);
    });
    dub.loadPackage();

    try
        dub.upgrade(UpgradeOptions.select);
    catch (Exception exc)
        assert(exc.message() == `Failed to find any versions for package b, referenced by a ~master`);

    assert(!dub.project.hasAllDependencies(), "project should have missing dependencies");
    assert(dub.project.getDependency("b", true) is null, "Found 'b' dependency");
    assert(dub.project.getDependency("no", true) is null, "Returned unexpected dependency");

    // Add the missing dependency to our PackageManager
    dub.fs.writePackageFile(`b`, "1.0.0", `name "b"
version "1.0.0"`, PackageFormat.sdl);
    dub.packageManager.refresh();
    dub.upgrade(UpgradeOptions.select);
    assert(dub.project.hasAllDependencies(), "project have missing dependencies");
    assert(dub.project.getDependency("b", true), "Missing 'b' dependency");
    assert(dub.project.getDependency("no", true) is null, "Returned unexpected dependency");
}

// Issue 2695 - Nonsensical dependencies
// Dependencies should resolve versions correctly regardless of the order they get requested
unittest
{
    scope dub = new TestDub((scope Filesystem root) {
            root.writeFile(TestDub.ProjectPath ~ "dub.sdl", `name "main"
dependency "a" version="*"
dependency "b" version="*"`);
            root.writePackageFile("a", "0.0.0", `name "a"
dependency "c" version="~>0.0.0"`, PackageFormat.sdl);
            root.writePackageFile("b", "0.0.0", `name "b"
dependency "c" version="0.0.0"`, PackageFormat.sdl);
            root.writePackageFile("c", "0.0.0", `name "c"
version "0.0.0"`, PackageFormat.sdl);
            root.writePackageFile("c", "0.0.1", `name "c"
version "0.0.1"`, PackageFormat.sdl);
    });
    dub.loadPackage();

    dub.upgrade(UpgradeOptions.select);

    assert(dub.project.hasAllDependencies(), "project have missing dependencies");
    assert(dub.project.getDependency("c", true).version_ == Version("0.0.0"));
}

unittest
{
    scope dub = new TestDub((scope Filesystem root) {
            root.writeFile(TestDub.ProjectPath ~ "dub.sdl", `name "main"
dependency "a" version="*"
dependency "b" version="*"`);
            root.writePackageFile("a", "1.0.0", `name "a"
dependency "c" version="0.0.0"`, PackageFormat.sdl);
            root.writePackageFile("b", "1.0.0", `name "b"
dependency "c" version="~>0.0.0"`, PackageFormat.sdl);
            root.writePackageFile("c", "0.0.0", `name "c"
version "0.0.0"`, PackageFormat.sdl);
            root.writePackageFile("c", "0.0.1", `name "c"
version "0.0.1"`, PackageFormat.sdl);
    });
    dub.loadPackage();

    dub.upgrade(UpgradeOptions.select);

    assert(dub.project.hasAllDependencies(), "project have missing dependencies");
    assert(dub.project.getDependency("c", true).version_ == Version("0.0.0"));
}

// https://github.com/dlang/dub/issues/1024
// `dub upgrade <pkg>` upgrades only the specified dependency,
// leaving other selected versions untouched.
unittest
{
    scope dub = new TestDub((scope Filesystem root) {
            root.writeFile(TestDub.ProjectPath ~ "dub.sdl", `name "main"
dependency "a" version="~>1.0.0"
dependency "b" version="~>1.0.0"
`);
            root.writeFile(TestDub.ProjectPath ~ "dub.selections.json",
`{ "fileVersion": 1, "versions": { "a": "1.0.0", "b": "1.0.0" } }`);
    });
    dub.loadPackage();

    foreach (vers; ["1.0.0", "1.0.1"]) {
        foreach (name; ["a", "b"]) {
            dub.getRegistry().add(Version(vers), (scope Filesystem pkg) {
                pkg.writeFile(NativePath(`dub.sdl`), `name "` ~ name ~ `"`);
            });
        }
    }

    dub.upgrade(UpgradeOptions.select | UpgradeOptions.upgrade, ["a"]);

    assert(dub.project.selections.getSelectedVersion(PackageName("a"))
        == Dependency(Version("1.0.1")), "Specified dependency was not upgraded.");
    assert(dub.project.selections.getSelectedVersion(PackageName("b"))
        == Dependency(Version("1.0.0")), "Non-specified dependency got upgraded.");
}
