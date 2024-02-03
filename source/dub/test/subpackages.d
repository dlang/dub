/*******************************************************************************

    Test for subpackages

    Subpackages are packages that are part of a 'main' packages. Their version
    is that of their main (parent) package. They are referenced using a column,
    e.g. `mainpkg:subpkg`. Nested subpackages are disallowed.

*******************************************************************************/

module dub.test.subpackages;

version(unittest):

import dub.test.base;

/// Test of the PackageManager APIs
unittest
{
    const a = `{ "name": "a", "dependencies": { "b:a": "~>1.0", "b:b": "~>1.0" } }`;
    const b = `{ "name": "b", "subPackages": [ { "name": "a" }, { "name": "b" } ] }`;

    scope dub = new TestDub();
    dub.addTestPackage(`b`, Version("1.0.0"), b);
    auto mainPackage = dub.addTestPackage(`a`, Version("1.0.0"), a);
    dub.loadPackage(mainPackage);
    dub.upgrade(UpgradeOptions.select);

    assert(dub.project.hasAllDependencies(), "project has missing dependencies");
    assert(dub.project.getDependency("b:b", true), "Missing 'b:b' dependency");
    assert(dub.project.getDependency("b:a", true), "Missing 'b:a' dependency");
    assert(dub.project.getDependency("no", true) is null, "Returned unexpected dependency");

    assert(dub.packageManager().getPackage(PackageName("b:a"), Version("1.0.0")).name == "b:a");
    assert(dub.packageManager().getPackage(PackageName("b:b"), Version("1.0.0")).name == "b:b");
    assert(dub.packageManager().getPackage(PackageName("b"), Version("1.0.0")).name == "b");

    assert(!dub.packageManager().getPackage(PackageName("b:b"), Version("1.1.0")));
}
