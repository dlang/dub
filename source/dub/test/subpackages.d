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
    scope dub = new TestDub((scope Filesystem root) {
        root.writeFile(TestDub.ProjectPath ~ "dub.json",
            `{ "name": "a", "dependencies": { "b:a": "~>1.0", "b:b": "~>1.0" } }`);
        root.writePackageFile("b", "1.0.0",
            `{ "name": "b", "version": "1.0.0", "subPackages": [ { "name": "a" }, { "name": "b" } ] }`);
    });
    dub.loadPackage();

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

// https://github.com/dlang/dub/issues/2973
unittest
{
    scope dub = new TestDub((scope Filesystem root) {
        root.writeFile(TestDub.ProjectPath ~ "dub.json",
            `{ "name": "a", "dependencies": { "b:a": "~>1.0", "c:a": "~>1.0" } }`);
        root.writeFile(TestDub.ProjectPath ~ "dub.selections.json",
            `{ "fileVersion": 1, "versions": { "b": "1.0.0", "c": { "path": "c" } } }`);
        root.writePackageFile("b", "1.0.0",
            `{ "name": "b", "version": "1.0.0", "subPackages": [ { "name": "a" } ] }`);
        const cDir = TestDub.ProjectPath ~ "c";
        root.mkdir(cDir);
        root.writeFile(cDir ~ "dub.json",
            `{ "name": "c", "version": "1.0.0", "subPackages": [ { "name": "a" } ] }`);
    });
    dub.loadPackage();

    assert(dub.project.hasAllDependencies(), "project has missing dependencies");
    assert(dub.project.getDependency("b:a", true), "Missing 'b:a' dependency");
    assert(dub.project.getDependency("c:a", true), "Missing 'c:a' dependency");
}

// https://github.com/dlang/dub/issues/1615
// https://github.com/dlang/dub/pull/2972
unittest
{
    scope dub = new TestDub((scope Filesystem root) {
        root.writeFile(TestDub.ProjectPath ~ "dub.json",
            `{"name": "t9",
"subPackages":[{"name": "a","dependencies": {":b": "*"}},{"name": "b"}],
"dependencies": {":a": "*",":b": "*"}}`);
    });
    dub.loadPackage();

    assert(dub.project.hasAllDependencies(), "project has missing dependencies");
}
