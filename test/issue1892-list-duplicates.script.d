/+ dub.sdl:
    name "list-duplicates-test"
+/
module list_duplicates_test;

import std.algorithm : count;
import std.conv : text;
import std.exception : enforce;
import std.file : mkdir, rmdirRecurse, tempDir, write;
import std.path : buildPath, dirSeparator;
import std.process : Config, environment, execute;
import std.random : uniform;
import std.string : splitLines;

void main()
{
	auto root = buildPath(tempDir(), text("dub-list-", uniform(ulong.min, ulong.max)));
	mkdir(root);
	scope (exit) rmdirRecurse(root);

	// Make the user cache coincide with the project-local cache.
	string run(string[] args) {
		auto result = execute([environment["DUB"]] ~ args, ["DUB_HOME": buildPath(root, ".dub")],
			Config.none, size_t.max, root);
		enforce(result.status == 0, result.output);
		return result.output;
	}

	auto paths = [buildPath(root, "first"), buildPath(root, "second")];
	foreach (path; paths) {
		mkdir(path);
		write(buildPath(path, "dub.json"), `{"name":"issue1892"}`);
		run(["add-local", path, "1.0.0"]);
	}
	foreach (args; [["list", "--color=never"], ["list", "issue1892@1.0.0", "--color=never"]]) {
		auto output = run(args);
		foreach (path; paths)
			enforce(output.splitLines.count("  issue1892 1.0.0: " ~ path ~ dirSeparator) == 1, output);
	}
}
