import common;

import std.algorithm;
import std.conv;
import std.file;
import std.path;
import std.process;
import std.range;
import std.string;

void main () {
	immutable baseDir = getcwd.buildPath("sample");
	chdir("sample/issue616-describe-vs-generate-commands");

	auto p = teeProcess([dub, "describe", "--data-list", "--data=target-name"],
						Redirect.stdout | Redirect.stderrToStdout);
	if (p.wait != 0)
		die("dub describe failed");
	const got = p.stdout.splitLines;

	string[] expected;
	version(Posix)
		expected ~= [
		`preGenerateCommands: DUB_PACKAGES_USED=issue616-describe-vs-generate-commands,issue616-subpack,issue616-subsubpack`,
		baseDir.myBuildPath("issue616-describe-vs-generate-commands", "src", ""),
		baseDir.myBuildPath("issue616-subpack", "src", ""),
		baseDir.myBuildPath("issue616-subsubpack", "src", ""),
	];

	expected ~= [ `issue616-describe-vs-generate-commands` ];

	if (equal(got, expected)) return;

	foreach (g, e; lockstep(got, expected)) {
		if (g == e) continue;

		log("Expected: ", text([e]), " but got ", text([g]));
	}
	die("dub describe output differs");
}

string myBuildPath(const(char)[][] segments...) {
	immutable result = buildPath(segments);
	if (segments[$ - 1] == "")
		return result ~ dirSeparator;
	return result;
}
