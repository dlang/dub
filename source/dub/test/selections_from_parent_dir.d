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
