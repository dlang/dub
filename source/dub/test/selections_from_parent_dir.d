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

    scope dub = new TestDub((scope FSEntry fs) {
        fs.mkdir(pkg1Dir).writeFile(NativePath("dub.sdl"), `name "pkg1"
targetType "none"`);
        fs.mkdir(pkg2Dir).writeFile(NativePath("dub.sdl"), `name "pkg2"
targetType "library"

# don't specify a path, require inherited dub.selections.json to make it path-based (../pkg1)
dependency "pkg1" version="*"`);

        // important: dub.selections.json in *parent* directory
        fs.writeFile(path, dubSelectionsJsonContent);
    }, pkg2Dir.toNativeString()); // pkg2 is our root package

    dub.loadPackage();
    assert(dub.project.hasAllDependencies());
    // the relative path should have been adjusted (`pkg1` => `../pkg1`)
    assert(dub.project.selections.getSelectedVersion(PackageName("pkg1")).path == NativePath("../pkg1"));

    // invoking `dub upgrade` for the pkg2 root package should generate a local dub.selections.json,
    // leaving the inherited one untouched
    dub.upgrade(UpgradeOptions.select);
    const nestedPath = pkg2Dir ~ "dub.selections.json";
    assert(dub.fs.existsFile(nestedPath));
    assert(dub.fs.readFile(path) == dubSelectionsJsonContent,
        "Inherited dub.selections.json modified after dub upgrade!");
    const nestedContent = cast(string) dub.fs.readFile(nestedPath);
    assert(nestedContent == dubSelectionsJsonContent.replace(`{"path":"pkg1"}`, `{"path":"../pkg1"}`),
        "Unexpected nestedContent:\n" ~ nestedContent);
}

// a non-inheritable dub.selections.json breaks the inheritance chain
unittest
{
    const root = TestDub.ProjectPath ~ "root";
    const root_a = root ~ "a";
    const root_a_b = root_a ~ "b";

    scope dub = new TestDub((scope FSEntry fs) {
        // inheritable root/dub.selections.json
        fs.mkdir(root).writeFile(NativePath("dub.selections.json"), `{
	"fileVersion": 1,
	"inheritable": true,
	"versions": {
		"dub": "1.38.0"
	}
}
`);
        // non-inheritable root/a/dub.selections.json
        fs.mkdir(root_a).writeFile(NativePath("dub.selections.json"), `{
	"fileVersion": 1,
	"versions": {
		"dub": "1.37.0"
	}
}
`);
        // empty root/a/b/ directory
        fs.mkdir(root_a_b);
    });

    // no selections for root/a/b/
    {
        const result = dub.packageManager.readSelections(root_a_b);
        assert(result.isNull());
    }

    // local selections for root/a/
    {
        const result = dub.packageManager.readSelections(root_a);
        assert(!result.isNull());
        assert(result.get().absolutePath == root_a ~ "dub.selections.json");
        assert(!result.get().selectionsFile.inheritable);
    }

    // local selections for root/
    {
        const result = dub.packageManager.readSelections(root);
        assert(!result.isNull());
        assert(result.get().absolutePath == root ~ "dub.selections.json");
        assert(result.get().selectionsFile.inheritable);
    }

    // after removing non-inheritable root/a/dub.selections.json: inherited root selections for root/a/b/
    {
        dub.fs.removeFile(root_a ~ "dub.selections.json");

        const result = dub.packageManager.readSelections(root_a_b);
        assert(!result.isNull());
        assert(result.get().absolutePath == root ~ "dub.selections.json");
        assert(result.get().selectionsFile.inheritable);
    }
}
