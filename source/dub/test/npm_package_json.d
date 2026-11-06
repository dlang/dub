/*******************************************************************************

    Test that npm `package.json` files are not loaded as Dub recipes

    `package.json` is a historic alias for `dub.json`, but JS projects
    (e.g. an Antora docs site next to a D package) commonly ship one.
    Dub must refuse those rather than emit confusing errors (see #3118),
    while still accepting legacy Dub recipes named `package.json`.

*******************************************************************************/

module dub.test.npm_package_json;

version (unittest):

import dub.test.base;
import std.exception : assertThrown;

// An npm package.json is refused
unittest
{
    scope dub = new TestDub((scope Filesystem fs) {
        fs.writeFile(TestDub.ProjectPath ~ "package.json", `{
	"name": "npm-looking-package",
	"private": true,
	"devDependencies": {
		"antora": "^3.1.14"
	},
	"packageManager": "pnpm@9.15.0"
}`);
    });
    assertThrown!Exception(dub.loadPackage());
}

// A legacy Dub recipe named package.json still loads
unittest
{
    scope dub = new TestDub((scope Filesystem fs) {
        fs.writeFile(TestDub.ProjectPath ~ "package.json",
            `{ "name": "legacy", "targetType": "executable" }`);
    });
    dub.loadPackage();
    assert(dub.project.rootPackage.name == "legacy");
}