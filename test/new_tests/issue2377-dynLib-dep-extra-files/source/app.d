import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	version (DigitalMars) version (Windows)
		skip("dmd on windows");

	chdir("sample/parent");
	if (exists("output"))
		rmdirRecurse("output");


	// 1.1 dynlib config
	if (spawnProcess([dub, "build", "-c", "dynlib"]).wait != 0)
		die("`dub build -c dynlib` failed");
	chdir("output/dynlib");
	assertDynLibExists("parent");
	assertDynLibExists("dep1");
	assertDynLibExists("dep2");
	version (Windows) {
		assertFileExists("parent.pdb");
		assertFileExists("parent.lib");
		assertFileExists("parent.exp");
		assertFileExists("dep1.pdb");
		assertFileExists("dep1.lib");
		assertFileExists("dep1.exp");
		assertFileExists("dep2.pdb");
		assertFileExists("dep2.lib");
		assertFileExists("dep2.exp");
	}
	chdir("../..");

	// 1.2 dynlib_static config
	if (spawnProcess([dub, "build", "-c", "dynlib_static"]).wait != 0)
		die("`dub build -c dynlib_static` failed");
	chdir("output/dynlib_static");
	assertDynLibExists("parent");
	version (Windows) {
		assertFileExists("parent.pdb");
		assertFileExists("parent.lib");
		assertFileExists("parent.exp");
	}
	if (canFindFiles("*dep*"))
		die("unexpected dependency files in statically linked dynlib output dir");
	chdir("../..");

	// 1.3 exe_static config
	if (spawnProcess([dub, "build", "-c", "exe_static"]).wait != 0)
		die("`dub build -c exe_static` failed");
	chdir("output/exe_static");
	if (spawnProcess(["./parent"]).wait != 0)
		die("Running the parent failed");
	version (Windows) {
		assertFileExists("parent.pdb");
		if (exists("parent.lib"))
			die("unexpected import .lib for executable");
		if (exists("parent.exp"))
			die("unexpected .exp file for executable");
	}
	if (canFindFiles("*dep*"))
		die("unexpected dependency files in statically linked executable output dir");
	chdir("../..");

	// 1.4 exe_dynamic config
	if (spawnProcess([dub, "build", "-c", "exe_dynamic"]).wait != 0)
		die("`dub build -c exe_dynamic` failed");
	chdir("output/exe_dynamic");

	string[string] env;
	version (Posix) env["LD_LIBRARY_PATH"] = ".:" ~ environment.get("LD_LIBRARY_PATH", "");
	if (spawnProcess(["./parent"], env).wait != 0)
		die("Running the parent failed");
	assertDynLibExists("dep1");
	assertDynLibExists("dep2");
	version (Windows) {
		assertFileExists("dep1.pdb");
		assertFileExists("dep2.pdb");
		if (canFindFiles("*.lib"))
			die("unexpected import libs in dynamically linked executable output dir");
		if (canFindFiles("*.exp"))
			die("unexpected import libs in dynamically linked executable output dir");
	}
	chdir("../..");

	// 2. `framework` as root package (targetType `none`)
	chdir("../framework");
	if (spawnProcess([dub, "build"]).wait != 0)
		die("`dub build` failed for framework");
	assertDynLibExists("dep1");
	assertDynLibExists("dep2");
	version (Windows) {
		assertFileExists("dep1.pdb");
		assertFileExists("dep1.lib");
		assertFileExists("dep1.exp");
		assertFileExists("dep2.pdb");
		assertFileExists("dep2.lib");
		assertFileExists("dep2.exp");
	}
}


void assertFileExists(string path) {
	if (!exists(path))
		die("Expected file '", path, "' not found");
}

void assertDynLibExists(string name) {
	version (Windows) {
		enum prefix = "";
		enum suffix = ".dll";
	} else version (OSX) {
		enum prefix = "lib";
		enum suffix = ".dylib";
	} else {
		enum prefix = "lib";
		enum suffix = ".so";
	}

	assertFileExists(prefix ~ name ~ suffix);
}

bool canFindFiles(string pattern) {
	auto entries = dirEntries(".", pattern, SpanMode.shallow);
	return !entries.empty();
}
