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
	if (dubCodeCachePath.exists) dubCodeCachePath.rmdirRecurse;
	string[string] env;

	runTestCase(env, "*dub_test_root.d");

	env["DFLAGS"] = "";
	runTestCase(env, "*DFLAGS*dub_test_root.d");

	env["DFLAGS"] = "-g";
	runTestCase(env, "*DFLAGS*dub_test_root.d");
}

immutable string dubCodeCachePath;
shared static this() {
	dubCodeCachePath = dubHome ~ "/cache/cache-generated-test-config/~master/code/";
}
immutable executableName = "cache-generated-test-config-test-library" ~ DotExe;

SysTime mainTime, executableTime;

void runTestCase(const string[string] env, string pattern) {
	invokeDubTest(env);
	updateTimes(pattern);

	invokeDubTest(env);
	checkTimesDidntChange(pattern);
}

void invokeDubTest(const string[string] env) {
	if (spawnProcess([dub, "test"], env).wait != 0)
		die("Dub test failed");
}

void updateTimes(string pattern) {
	executableTime = executableName.timeLastModified;
	mainTime = getMainTime(pattern);
}

void checkTimesDidntChange(string pattern) {
	if (executableTime != executableName.timeLastModified)
		die("The executable has been rebuilt");

	if (mainTime != getMainTime(pattern))
		die("The test main file has been rebuilt");
}

SysTime getMainTime(string pattern) {
	const files = dubCodeCachePath
		.dirEntries(SpanMode.depth)
		.map!(e => e.name)
		.filter!(name => name.globMatch(pattern))
		.array;

	if (files.length == 0)
		die("Dub did not generate a source file");
	if (files.length > 1)
		die("Dub generated more than one main file");

	return files[0].timeLastModified;
}
