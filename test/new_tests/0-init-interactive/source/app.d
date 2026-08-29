import common;

void main()
{
	runTest("1\ntest\ndesc\nauthor\ngpl\ncopy\n\n", "dub.sdl");
	runTest("3\n1\ntest\ndesc\nauthor\ngpl\ncopy\n\n", "dub.sdl");
	runTest("sdl\ntest\ndesc\nauthor\ngpl\ncopy\n\n", "dub.sdl");
	runTest("sdlf\n1\ntest\ndesc\nauthor\ngpl\ncopy\n\n", "dub.sdl");
	runTest("1\n\ndesc\nauthor\ngpl\ncopy\n\n", "default_name.dub.sdl");
	runTest("2\ntest\ndesc\nauthor\ngpl\ncopy\n\n", "dub.json");
	runTest("\ntest\ndesc\nauthor\ngpl\ncopy\n\n", "dub.json");
	runTest("1\ntest\ndesc\nauthor\n6\n3\ncopy\n\n", "license_gpl3.dub.sdl");
	runTest("1\ntest\ndesc\nauthor\n9\n3\ncopy\n\n", "license_mpl2.dub.sdl");
	runTest("1\ntest\ndesc\nauthor\n21\n6\n3\ncopy\n\n", "license_gpl3.dub.sdl");
	runTest("1\ntest\ndesc\nauthor\n\ncopy\n\n", "license_proprietary.dub.sdl");
}

void runTest(string input, string expectedPath) {
	import std.array;
	import std.algorithm;
	import std.range;
	import std.process;
	import std.file;
	import std.path;
	import std.string;

	immutable test = baseName(expectedPath);
	immutable dub_ext = expectedPath[expectedPath.lastIndexOf(".") + 1 .. $];

	const dir = "new-package";

	if (dir.exists) rmdirRecurse(dir);
	auto pipes = pipeProcess([dub, "init", dir],
							 Redirect.stdin | Redirect.stdout | Redirect.stderrToStdout);
	scope(success) rmdirRecurse(dir);

	immutable escapedInput = format("%(%s%)", [input]);
	pipes.stdin.writeln(input);
	pipes.stdin.close();
	if (pipes.pid.wait != 0) {
		die("Dub failed to generate init file for "  ~ escapedInput);
	}

	scope(failure) {
		logError("You can find the generated files in ", absolutePath(dir));
	}

	if (!exists(dir ~ "/dub." ~ dub_ext)) {
		logError("No dub." ~ dub_ext ~ " file has been generated for test " ~ test);
		logError("with input " ~ escapedInput ~ ". Output:");
		foreach (line; pipes.stdout.byLine)
			logError(line);
		die("No dub." ~ dub_ext ~ " file has been found");
	}

	immutable got = readText(dir ~ "/dub." ~ dub_ext).replace("\r\n", "\n");
	immutable expPath = "exp/" ~ expectedPath;
	immutable exp = expPath.readText.replace("\r\n", "\n");

	if (got != exp) {
		die("Contents of generated dub." ~ dub_ext ~ " does not match " ~ expPath);
	}
}
