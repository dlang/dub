import common;

import std.algorithm;
import std.process;
import std.file;

void main () {
	chdir("sample");
	immutable exePath = "single-file-test" ~ DotExe;

	if (spawnProcess([dub, "run", "--single", "json.d"]).wait != 0)
		die("Dub couldn't run single file json package");
	if (!exists(exePath))
		die("Normal invocation did not produce a binary in the current directory");
	remove(exePath);

	version(Posix)
	if (spawnProcess(["./sdl.d", "foo", "--", "bar"]).wait != 0)
		die("Failed running shebang script with extension");

	if (spawnProcess([dub, "./sdl.d", "foo", "--", "bar"]).wait != 0)
		die("Dub failed to run script with shebang");

	version(Posix)
	if (spawnProcess(["./no-ext", "foo", "--", "bar"]).wait != 0)
		die("Failed running shebang script without extension");

	if (spawnProcess([dub, "w-dep.d"]).wait != 0)
		die("Dub couldn't run single file package with dependency");

	if (exists(exePath))
		die("Shebang invocation produced binary in current directory");

    {
        auto p = execute([dub, "run", "w-dep.d", "--temp-build"]);
        if (p.output.canFind("To force a rebuild"))
            die("Invocation triggered unnecessary rebuild.");
	}

	// missing from git? https://github.com/dlang/dub/pull/1177 was the one that should have added it
	version(none)
	if (spawnProcess([dub, "error.d"]).wait == 0)
	    die("Invalid package comment syntax did not trigger an error.");
}
