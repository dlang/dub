import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	immutable files = [
		"libsingle-file-test-dynamic-library.so",
		"libsingle-file-test-dynamic-library.dylib",
		"single-file-test-dynamic-library.dll",
	];
	foreach (file; files)
		if (exists(file)) remove(file);

	if (spawnProcess([dub, "build", "--single", "sample.d"]).wait != 0)
		die("Dub build failed");

	foreach (file; files)
		if (exists(file)) return;

	die("Normal invocation did not produce a dynamic library in the current directory");
}
