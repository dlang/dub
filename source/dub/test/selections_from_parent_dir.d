module dub.test.selections_from_parent_dir;

version (unittest):

import dub.test.base;

// dub.selections.json can be inherited from parent directories, adjusting relative paths accordingly
unittest
{
    scope dub = new TestDub((scope FSEntry fs) {
        fs.mkdir(TestDub.ProjectPath ~ "pkg1").writeFile(NativePath("dub.sdl"), `name "pkg1"
targetType "none"`);
        fs.mkdir(TestDub.ProjectPath ~ "pkg2").writeFile(NativePath("dub.sdl"), `name "pkg2"
targetType "library"

# don't specify a path, require inherited dub.selections.json to make it path-based (../pkg1)
dependency "pkg1" version="*"`);

        // important: dub.selections.json in *parent* directory
        fs.writeFile(TestDub.ProjectPath ~ "dub.selections.json", `{
	"fileVersion": 1,
	"inheritable": true,
	"versions": {
		"pkg1": {"path": "pkg1"}
	}
}`);
    });

    dub.loadPackage(TestDub.ProjectPath ~ "pkg2");
    assert(dub.project.hasAllDependencies());
    assert(dub.project.selections.getSelectedVersion(PackageName("pkg1")).path == NativePath("../pkg1"));
}
