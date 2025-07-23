import run_unittest.log;
import run_unittest.runner;

import std.file;
import std.getopt;
import std.stdio;
import std.path;

int main(string[] args) {
	bool verbose;
	bool color;
	int jobs;
	version(Posix)
		color = true;

	auto help = getopt(args,
		"v|verbose", &verbose,
		"color", &color,
		"j|jobs", &jobs,
	);
	if (help.helpWanted) {
		defaultGetoptPrinter(`run_unittest [-v|--verbose] [--color] [-j|--jobs] [<patterns>...]

<patterns> are shell globs matching directory names under test/
`, help.options);
		return 0;
	}

	auto testDir = buildNormalizedPath(__FILE_FULL_PATH__, "..", "..", "..", "new_tests");
	chdir(testDir);

	ErrorSink sink;
	{
		ErrorSink fileSink = new FileSink("test.log");
		ErrorSink consoleSink = new ConsoleSink(color);
		if (!verbose)
			consoleSink = new NonVerboseSink(consoleSink);
		sink = new GroupSink(fileSink, consoleSink);
	}
	auto config = generateRunnerConfig(sink);
	config.color = color;
	config.jobs = jobs;

    auto runner = Runner(config, sink);
	return runner.run(args[1 .. $]);
}
