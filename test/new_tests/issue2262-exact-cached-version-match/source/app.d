import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	chdir("sample");

	// make sure that there are no left-over selections files
	if (exists("dub.selections.json")) remove("dub.selections.json");

	// make sure that there are no cached versions of the dependency
	// dub remove fails to remove the git package on windows
	if (exists(dubHome)) rmdirRecurse(dubHome);

	// build normally, should select 1.0.4
	auto p = teeProcess([dub, "build"]);
	if (p.wait != 0 || !p.stdout.canFind(`gitcompatibledubpackage 1.0.4:`))
		die("The initial build failed.");

	spawnProcess([dub, "remove", "gitcompatibledubpackage@*", "-n"]).wait;

	// build with git dependency to a specific commit
	write("dub.selections.json", `
{
    "fileVersion": 1,
    "versions": {
        "gitcompatibledubpackage": {
            "repository": "git+https://github.com/dlang-community/gitcompatibledubpackage.git",
            "version": "ccb31bf6a655437176ec02e04c2305a8c7c90d67"
        }
    }
}
`);
	p = teeProcess([dub, "build"]);
	if (p.wait != 0 || !p.stdout.canFind(`gitcompatibledubpackage 1.0.4+commit.2.gccb31bf:`)) {
		die("The build with a specific commit failed.");
	}

	// select 1.0.4 again
	write("dub.selections.json", `
{
    "fileVersion": 1,
    "versions": {
        "gitcompatibledubpackage": "1.0.4"
    }
}
`);
	p = teeProcess([dub, "build"]);
	if (p.wait != 0 || !p.stdout.canFind(`gitcompatibledubpackage 1.0.4:`))
		die("The second 1.0.4 build failed.");
}
