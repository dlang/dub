/+ dub.sdl:
   name "hash"
 +/

import std.algorithm : any;
import std.array : array;
import std.string : lineSplitter;
import std.datetime : dur, SysTime;
import std.file;
import std.format : format;
import std.path;
import std.process;
import std.stdio : stderr, writeln;

enum TestProjectName = "hash-dependent-build";
immutable source_name = "source/app.d";
version(Windows) immutable artifact_name = TestProjectName ~ ".exe";
else             immutable artifact_name = TestProjectName;

enum HashKind { default_, time, sha1, sha256 }

/// extract hash kind from line containing dub output
auto extractBuildCachePolicy(string str) {
	import std.string : lineSplitter;
	import std.regex : regex, matchAll;
	static re = regex(`hash-dependent-build ~master: (\w+\W)+configuration \"application\" (\w+\W)*\((\w+( |: ))*(sha256|sha1|time)\).`);

	foreach(line; str.lineSplitter)
	{
		auto m = line.matchAll(re);
		if (!m.empty)
			return m.front[5];
	}

	return "";
}

/// build target using given hash kind
auto buildTargetUsing(HashKind kind, string[string] env = null) {
	import std.exception : enforce;

	auto dub = executeShell(buildNormalizedPath("..", "..", "bin", "dub") ~ 
		" build --build-cache-policy=%s".format(kind), env);
	writeln("dub output:");
	import std.string : lineSplitter;
	foreach(line; dub.output.lineSplitter)
		writeln("\t", line);
	writeln("end of dub output");

	enforce(dub.status == 0, "couldn't build the project, see above");

	return dub.output;
}

/// check dub output to determine rebuild has not been triggered
auto checkIfNoRebuild(string output) {
	import std.regex : regex, matchAll;
	static re = regex(`hash-dependent-build ~master: target for configuration \"application\" is up to date \((sha256|sha1|time)\).`);

	if (output.lineSplitter.any!(a=>!a.matchAll(re).empty)) {
		writeln("\tOk. No rebuild triggered");
		return true;
	}
	else
		writeln("\tFail. Rebuild has been triggered");
	return false;
}

/// check dub output to determine rebuild has been triggered
auto checkIfRebuildTriggered(string output) {
	import std.regex : regex, matchAll;
	static re = regex(`hash-dependent-build ~master: building configuration \"application\" \((sha256|sha1|time)\).`);

	if (output.lineSplitter.any!(a=>!a.matchAll(re).empty)) {
		writeln("Ok. Rebuild has been triggered");
		return true;
	}
	else
		writeln("Fail. No rebuild triggered");
	return false;
}

int main()
{
	// delete old artifacts if any
	const projectDir = buildPath(getcwd, "test", TestProjectName);
	if (projectDir.exists)
		projectDir.rmdirRecurse;
	projectDir.mkdir;

	chdir(projectDir);

	// create test_project
	{
		auto dub = executeShell(buildNormalizedPath("..", "..", "bin", "dub") ~ " init --non-interactive");
		if (dub.status != 0)
		{
			stderr.writeln("couldn't execute 'dub init test_project'");
			stderr.writeln(dub.output);
			return 1;
		}
	}

	// build the project first time
	writeln("\n---");
	writeln("Build #1 (using hash dependent cache)");
	writeln("Building the project from scratch");
	writeln("Hash dependent build should be triggered");
	auto output = buildTargetUsing(HashKind.sha256);
	if (!checkIfRebuildTriggered(output))
		return 1;

	writeln("\n---");
	writeln("Building #2 (using hash dependent cache)");
	writeln("building the project that has been built (using hash dependent cache)");
	writeln("Hash dependent build should NOT be triggered");
	output = buildTargetUsing(HashKind.sha256);
	if (!checkIfNoRebuild(output))
		return 1;

	// touch some source file(s)
	{
		SysTime atime, mtime;
		const delay = dur!"msecs"(10);
		getTimes(artifact_name, atime, mtime);
		setTimes(source_name, atime + delay, mtime + delay);

		// wait for the delay to avoid time related issues
		import core.thread : Thread;
		Thread.sleep(delay);
	}

	writeln("\n---");
	writeln("Build #3 (using hash dependent cache)");
	writeln("building the project that has been built (using hash dependent cache)");
	writeln("but timestamp of source file(s) has been changed to be younger");
	writeln("Hash dependent build should NOT be triggered");
	output = buildTargetUsing(HashKind.sha256);
	if (!checkIfNoRebuild(output))
		return 1;

	writeln("\n---");
	writeln("build #4 (using time dependent cache)");
	writeln("building the project that has been built (using hash dependent cache)");
	writeln("but timestamp of source file(s) has been changed to be younger");
	writeln("Time dependent build should be triggered");
	output = buildTargetUsing(HashKind.time);
	if (!checkIfRebuildTriggered(output))
		return 1;

	// edit some source file(s) preserving the file timestamp
	{
		SysTime atime, mtime;
		getTimes(source_name, atime, mtime);

		import std.file : copy, append;
		copy(source_name, source_name ~ ".tmp");
		append(source_name, " ");

		setTimes(source_name, atime, mtime);
	}

	writeln("\n---");
	writeln("build #5 (using time dependent cache)");
	writeln("building the project that has been built (using both hash- and time- dependent cache)");
	writeln("but source file(s) has been changed and timestamp of them was preserved");
	writeln("Time dependent build should NOT be triggered");
	output = buildTargetUsing(HashKind.time);
	if (!checkIfNoRebuild(output))
		return 1;

	writeln("\n---");
	writeln("build #6 (using hash dependent cache)");
	writeln("building the project that has been built once (using both hash- and time- dependent cache)");
	writeln("but source file(s) has been changed and timestamp of them was preserved");
	writeln("Hash dependent build should be triggered");
	output = buildTargetUsing(HashKind.sha256);
	if (!checkIfRebuildTriggered(output))
		return 1;

	// undo changes in source/app.d (i.e. restore its content)
	{
		SysTime atime, mtime;
		getTimes(source_name, atime, mtime);

		import std.file : rename;
		rename(source_name ~ ".tmp", source_name);

		setTimes(source_name, atime, mtime);
	}
	writeln("\n---");
	writeln("build #7 (using hash dependent cache)");
	writeln("building the project that has been built then modifiend and then reverted");
	writeln("the previous state");
	writeln("Hash dependent build should NOT be triggered");
	output = buildTargetUsing(HashKind.sha256);
	if (!checkIfNoRebuild(output))
		return 1;

	// Tests for command line interface option, environment variable and
	// settings file values combination
	{
		string[string[3]] preset = [
			// cli        env        settings
			["default_", "default_", "default_"]: "time",
			["default_", "default_", "sha1"   ]: "sha1",
			["default_", "sha256",   "sha1"   ]: "sha256",
			["default_", "sha1",     "sha256" ]: "sha1",
			["sha256",   "sha1",     "time"   ]: "sha256",
			["sha1",     "sha256",   "time"   ]: "sha1",
			["sha256",   "time",     "sha1"   ]: "sha256",
			["sha1",     "time",     "sha256" ]: "sha1",
		];
		foreach(key, value; preset)
		{
			import std.conv : to, text;
			import std.stdio : File, writefln;

			writefln("cli: %s\tenv: %s\tsetting: %s\tresult: %s", key[0], key[1], key[2], value);

			// write to settings file
			{
				File("./dub.settings.json", "w").writefln("{ \"buildCachePolicy\" : \"%s\" }", key[2]);
			}

			output = buildTargetUsing(key[0].to!HashKind, ["DUB_BUILD_CACHE_POLICY":key[1]]);
			auto str = extractBuildCachePolicy(output);
			assert(str == value, text("Given ", key, " but got `", str, "` instead of `", value, "`"));
		}
	}

	return 0;
}