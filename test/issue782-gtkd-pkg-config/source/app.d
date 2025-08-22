import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	chdir("sample");

    foreach (dir; ["fake-gtkd/.dub", "main/.dub"])
		if (exists(dir)) rmdirRecurse(dir);
    foreach (file; ["fake-gtkd/libfake-gtkd.so", "main/fake-gtkd-test"])
		if (exists(file)) remove(file);
	if (spawnProcess([dub, "build"], null, Config.none, "fake-gtkd").wait != 0)
		die("dub build fake-gtkd failed");

	immutable ldPath = environment.get("LD_LIBRARY_PATH");
	immutable gtkdPath = getcwd.buildPath("fake-gtkd");
	immutable newLdPath = ldPath.length ? ldPath ~ ":" ~ gtkdPath : gtkdPath;
	immutable pkgConfigPath = gtkdPath.buildPath("pkgconfig");

	auto p = spawnProcess(
		[dub, "-v", "run", "--force"],
		[ "LD_LIBRARY_PATH": newLdPath,
		  "PKG_CONFIG_PATH": pkgConfigPath,
		],
		Config.none,
		"main",
	);
	if (p.wait != 0)
		die("dub run main failed");
}
