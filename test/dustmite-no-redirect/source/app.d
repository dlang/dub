import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;
import std.stdio;

void main () {
	// are DFLAGS unquoted?
	environment.remove("DFLAGS");

	bool doSkip = false;
	try {
		if (!execute("dustmite").status != 0)
			doSkip = true;
	} catch (ProcessException)
		doSkip = true;

	if (doSkip)
		skip("dustmite not found in $PATH");

	immutable testDir = "sample";
	immutable tmpDir = "sample-dusting";
	immutable expected = "This text should be shown!";

	dirEntries(".", tmpDir ~ "*", SpanMode.shallow)
		.each!rmdirRecurse;

	auto p = execute([dub, "--root=" ~ testDir, "dustmite", "--no-redirect", "--program-status=1", tmpDir]);

	if (!p.output.canFind(expected)) {
		writeln(p.output);
		die("Diff between expected and actual output");
	}
}
