import std.algorithm;
import std.array;
import std.file;
import std.path;
import std.process;
import std.range;
import std.stdio;

import common;
import describe_test_utils;

void main()
{
	runTestCase([
		"--data-list",
		"--data=target-type",
		"--data=target-path",
		"--data=target-name",
		"--data=working-directory",
		"--data=main-source-file",
		"--data=dflags",
		"--data=lflags",
		"--data=libs",
		"--data=linker-files",
		"--data=source-files",
		"--data=copy-files",
		"--data=versions",
		"--data=debug-versions",
		"--data=import-paths",
		"--data=string-import-paths",
		"--data=import-files",
		"--data=string-import-files",
		"--data=pre-generate-commands",
		"--data=post-generate-commands",
		"--data=pre-build-commands",
		"--data=post-build-commands",
		"--data=requirements",
		"--data=options",
	]);

	runTestCase([ "--import-paths" ]);

	if (!environment.get("DC").baseName.canFind("dmd")) {
		log("Some tests were skipped because DC is not dmd-like");
		return;
	}

	runTestCase([ "--data=versions" ], lines => [ lines.join(' ') ]);

	runTestCase([ "--data=source-files" ], lines => [ lines.map!escape.join(' ') ]);

	runTestCase([ "--data=source-files" ], lines => [ lines.map!escape.join(' ') ]);
}

void runTestCase(string[] arguments, const(char[][]) delegate(const char[][]) mapper = a => a) {
	const cmd = [dub, "describe"] ~ arguments;

	immutable describeDir = buildNormalizedPath(getcwd(), "../extra/4-describe");
	auto listStyle = pipeProcess(cmd, Redirect.all, null, Config.none,
							 describeDir.buildPath("project"));
	if (listStyle.pid.wait() != 0)
		die("Printing list-style project data failed");
	auto zeroStyle = pipeProcess(cmd ~ "--data-0", Redirect.all, null, Config.none,
								 describeDir.buildPath("project"));
	if (zeroStyle.pid.wait() != 0)
		die("Printing null-delimited list-style project data failed");

	const listOutput = listStyle.stdout.byLineCopy.map!fixWindowsCR.array;
	const preZeroOutput = zeroStyle.stdout.byLineCopy(No.keepTerminator, '\0').array;
	const zeroOutput = mapper(preZeroOutput);

	if (!equal(listOutput, zeroOutput)) {
		File("list-style.txt", "w").writef("%(%(%c%)\n%)", listOutput);
		File("zero-style.txt", "w").writef("%(%(%c%)\n%)", zeroOutput);

		printDifference(listOutput, zeroOutput);
		logError("The null-delimited list-style project data did not match the expected output!");
		logError("Check list-style.txt and zero-style.txt");
		die("Dub null-delimited data did not match expected output");
	}
}
