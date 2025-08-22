import common;

import std.algorithm;
import std.path;
import std.array;
import std.datetime.systime;
import std.file;
import std.process;
import std.stdio : File;

void main()
{
	chdir("sample");
	immutable colorEscape = "\033[";
	immutable colorSwitch = environment["DC"].baseName.canFind("ldc") ?
		" -enable-color " : " -color ";

	runTestCase(["--color=never"], false, colorEscape);
	runTestCase(["--color=auto"], false, colorEscape);
	runTestCase([], false, colorEscape);
	runTestCase(["--color=always"], true, colorEscape);

	runTestCase(["--force", "-v", "--color=never"], false, colorSwitch);
	runTestCase(["--force", "-v", "--color=auto"], false, colorSwitch);
	runTestCase(["--force", "-v", "--color=always"], true, colorSwitch);
}

void runTestCase(string[] args, bool expectToFind, string outputMatch) {
	auto p = teeProcess([dub, "build"] ~ args, Redirect.stdout | Redirect.stderrToStdout);
	p.wait;

	immutable found = p.stdout.canFind(outputMatch);
	if (found == expectToFind) return;

	if (found) {
		die("Got color output but didn't expect it");
	} else {
		die("Didn't get color output but expected it");
	}
}
