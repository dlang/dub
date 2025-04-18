/*******************************************************************************

    Test inheritable flag of selections file

    Selections files can have an `inheritable` flag that is used to have
    a central selections file, e.g. in the case of a monorepo.

*******************************************************************************/

module dub.test.selections_from_parent_dir;

version (unittest):

import dub.test.base;
import std.string : replace;

// dub.selections.json can be inherited from parent directories
unittest
{
    const pkg1Dir = TestDub.ProjectPath ~ "pkg1";
    const pkg2Dir = TestDub.ProjectPath ~ "pkg2";
    const path = TestDub.ProjectPath ~ "dub.selections.json";
    const dubSelectionsJsonContent = `{
	"fileVersion": 1,
	"inheritable": true,
	"versions": {
		"pkg1": {"path":"pkg1"}
	}
}
`;

    scope dub = new TestDub((scope Filesystem fs) {
        fs.mkdir(pkg1Dir);
        fs.writeFile(pkg1Dir ~ "dub.sdl", `name "pkg1"
targetType "none"`);
        fs.mkdir(pkg2Dir);
        fs.writeFile(pkg2Dir ~ "dub.sdl", `name "pkg2"
targetType "library"

# don't specify a path, require inherited dub.selections.json to make it path-based (../pkg1)
dependency "pkg1" version="*"`);

        // important: dub.selections.json in *parent* directory
        fs.writeFile(path, dubSelectionsJsonContent);
    }, pkg2Dir.toNativeString()); // pkg2 is our root package

    dub.loadPackage();
    assert(dub.project.hasAllDependencies());
    // the relative path should have been adjusted (`pkg1` => `../pkg1`)
    version (Windows)
        immutable AdjustedPath = NativePath(`..\pkg1`);
    else
        immutable AdjustedPath = NativePath(`../pkg1`);
    assert(dub.project.selections.getSelectedVersion(PackageName("pkg1")).path == AdjustedPath);

    // invoking `dub upgrade` for the pkg2 root package should generate a local dub.selections.json,
    // leaving the inherited one untouched
    dub.upgrade(UpgradeOptions.select);
    const nestedPath = pkg2Dir ~ "dub.selections.json";
    assert(dub.fs.existsFile(nestedPath));
    assert(dub.fs.readFile(path) == dubSelectionsJsonContent,
        "Inherited dub.selections.json modified after dub upgrade!");
    const nestedContent = dub.fs.readText(nestedPath);
    assert(nestedContent == dubSelectionsJsonContent.replace(`{"path":"pkg1"}`, `{"path":"../pkg1"}`),
        "Unexpected nestedContent:\n" ~ nestedContent);
}

// a non-inheritable dub.selections.json breaks the inheritance chain
unittest
{
    const root = TestDub.ProjectPath ~ "root";
    const root_a = root ~ "a";
    const root_a_b = root_a ~ "b";

    scope dub_ = new TestDub((scope Filesystem fs) {
        // inheritable root/dub.selections.json
        fs.mkdir(root);
        fs.writeFile(root ~ "dub.selections.json", `{
	"fileVersion": 1,
	"inheritable": true,
	"versions": {
		"dub": "1.38.0"
	}
}
`);
        // non-inheritable root/a/dub.selections.json
        fs.mkdir(root_a);
        fs.writeFile(root_a ~ "dub.selections.json", `{
	"fileVersion": 1,
	"versions": {
		"dub": "1.37.0"
	}
}
`);
        // We need packages for `loadPackage`
        fs.mkdir(root_a_b);
        fs.writeFile(root_a_b ~ `dub.json`,
            `{"name":"ab","dependencies":{"dub":"~>1.0"}}`);
        fs.writeFile(root_a ~ `dub.json`,
            `{"name":"a","dependencies":{"dub":"~>1.0"}}`);
        fs.writeFile(root ~ `dub.json`,
            `{"name":"r","dependencies":{"dub":"~>1.0"}}`);
        fs.writePackageFile(`dub`, `1.37.0`, `{"name":"dub","version":"1.37.0"}`);
        fs.writePackageFile(`dub`, `1.38.0`, `{"name":"dub","version":"1.38.0"}`);
    });

    // no selections for root/a/b/
    {
        auto dub = dub_.newTest();
        const result = dub.packageManager.readSelections(root_a_b);
        assert(result.isNull());
        dub.loadPackage(root_a_b);
        assert(!dub.project.hasAllDependencies());
    }

    // local selections for root/a/
    {
        auto dub = dub_.newTest();
        const result = dub.packageManager.readSelections(root_a);
        assert(!result.isNull());
        assert(result.get().absolutePath == root_a ~ "dub.selections.json");
        assert(!result.get().selectionsFile.inheritable);
        dub.loadPackage(root_a);
        assert(dub.project.hasAllDependencies());
        assert(dub.project.dependencies()[0].name == "dub");
        assert(dub.project.dependencies()[0].version_ == Version("1.37.0"));
    }

    // local selections for root/
    {
        auto dub = dub_.newTest();
        const result = dub.packageManager.readSelections(root);
        assert(!result.isNull());
        assert(result.get().absolutePath == root ~ "dub.selections.json");
        assert(result.get().selectionsFile.inheritable);
        dub.loadPackage(root);
        assert(dub.project.hasAllDependencies());
        assert(dub.project.dependencies()[0].name == "dub");
        assert(dub.project.dependencies()[0].version_ == Version("1.38.0"));
    }

    // after removing non-inheritable root/a/dub.selections.json: inherited root selections for root/a/b/
    {
        auto dub = dub_.newTest((scope Filesystem fs) {
            fs.removeFile(root_a ~ "dub.selections.json");
        });
        const result = dub.packageManager.readSelections(root_a_b);
        assert(!result.isNull());
        assert(result.get().absolutePath == root ~ "dub.selections.json");
        assert(result.get().selectionsFile.inheritable);
        dub.loadPackage(root_a_b);
        assert(dub.project.hasAllDependencies());
        assert(dub.project.dependencies()[0].name == "dub");
        assert(dub.project.dependencies()[0].version_ == Version("1.38.0"));
    }
}
