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
    const a = `name "a"
dependency "b" version="*"
dependency "c" version="*"
`;
    const b = `name "b"`;
    const c = `name "c"`;

    scope dub = new TestDub();
    dub.addTestPackage(`c`, Version("1.0.0"), c, PackageFormat.sdl);
    dub.addTestPackage(`b`, Version("1.0.0"), b, PackageFormat.sdl);
    dub.loadPackage(dub.addTestPackage(`a`, Version("1.0.0"), a, PackageFormat.sdl));

    dub.upgrade(UpgradeOptions.select);

    assert(dub.project.hasAllDependencies(), "project has missing dependencies");
    assert(dub.project.getDependency("b", true), "Missing 'b' dependency");
    assert(dub.project.getDependency("c", true), "Missing 'c' dependency");
    assert(dub.project.getDependency("no", true) is null, "Returned unexpected dependency");
}

// Test that indirect dependencies get resolved correctly
unittest
{
    const a = `name "a"
dependency "b" version="*"
`;
    const b = `name "b"
dependency "c" version="*"
`;
    const c = `name "c"`;

    scope dub = new TestDub();
    dub.addTestPackage(`c`, Version("1.0.0"), c, PackageFormat.sdl);
    dub.addTestPackage(`b`, Version("1.0.0"), b, PackageFormat.sdl);
    dub.loadPackage(dub.addTestPackage(`a`, Version("1.0.0"), a, PackageFormat.sdl));

    dub.upgrade(UpgradeOptions.select);

    assert(dub.project.hasAllDependencies(), "project has missing dependencies");
    assert(dub.project.getDependency("b", true), "Missing 'b' dependency");
    assert(dub.project.getDependency("c", true), "Missing 'c' dependency");
    assert(dub.project.getDependency("no", true) is null, "Returned unexpected dependency");
}

// Simple diamond dependency
unittest
{
    const a = `name "a"
dependency "b" version="*"
dependency "c" version="*"
`;
    const b = `name "b"
dependency "d" version="*"
`;
    const c = `name "c"
dependency "d" version="*"
`;
    const d = `name "d"`;

    scope dub = new TestDub();
    dub.addTestPackage(`d`, Version("1.0.0"), d, PackageFormat.sdl);
    dub.addTestPackage(`c`, Version("1.0.0"), c, PackageFormat.sdl);
    dub.addTestPackage(`b`, Version("1.0.0"), b, PackageFormat.sdl);
    dub.loadPackage(dub.addTestPackage(`a`, Version("1.0.0"), a, PackageFormat.sdl));

    dub.upgrade(UpgradeOptions.select);

    assert(dub.project.hasAllDependencies(), "project has missing dependencies");
    assert(dub.project.getDependency("b", true), "Missing 'b' dependency");
    assert(dub.project.getDependency("c", true), "Missing 'c' dependency");
    assert(dub.project.getDependency("c", true), "Missing 'd' dependency");
    assert(dub.project.getDependency("no", true) is null, "Returned unexpected dependency");
}

// Missing dependencies trigger an error
unittest
{
    const a = `name "a"
dependency "b" version="*"
`;

    scope dub = new TestDub();
    dub.loadPackage(dub.addTestPackage(`a`, Version("1.0.0"), a, PackageFormat.sdl));

    try
        dub.upgrade(UpgradeOptions.select);
    catch (Exception exc)
        assert(exc.message() == `Failed to find any versions for package b, referenced by a 1.0.0`);

    assert(!dub.project.hasAllDependencies(), "project should have missing dependencies");
    assert(dub.project.getDependency("b", true) is null, "Found 'b' dependency");
    assert(dub.project.getDependency("no", true) is null, "Returned unexpected dependency");

    // Add the missing dependency to our PackageManager
    dub.addTestPackage(`b`, Version("1.0.0"), `name "b"`, PackageFormat.sdl);
    dub.upgrade(UpgradeOptions.select);
    assert(dub.project.hasAllDependencies(), "project have missing dependencies");
    assert(dub.project.getDependency("b", true), "Missing 'b' dependency");
    assert(dub.project.getDependency("no", true) is null, "Returned unexpected dependency");
}
