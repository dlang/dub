import common;

import std.algorithm;
import std.file;
import std.json;
import std.path;
import std.process;
import std.stdio : File;

void main () {
	chdir("sample");
	environment.remove("DC");
	immutable dubDir = dub.dirName;

	{
		immutable path = dubDir.buildPath("foo");
		immutable configPath = "foo";
		immutable needle = "Unknown compiler: " ~ absolutePath(path);
		immutable errorMessage = "DUB did not find the local configuration with an adjacent compiler.";

		testCase(path, configPath, needle, errorMessage);
	}

	{
		immutable path = getcwd.buildPath("foo");
		immutable configPath = path;
		immutable needle = "Unknown compiler: " ~ path;
		immutable errorMessage = "DUB did not find a locally-configured compiler with an absolute path.";

		testCase(path, configPath, needle, errorMessage);
	}

	version(Posix)
	{{
		immutable path = getcwd.buildPath("foo");
		immutable configPath = "~/foo";
		immutable needle = "Unknown compiler: ";
		immutable errorMessage = "DUB did not find a locally-configured compiler with a tilde-prefixed path.";

		testCase(path, configPath, needle, errorMessage, ["HOME": getcwd]);
	}}

	{
		immutable path = getcwd.buildPath("foo");

		immutable relPath = relativePath(path, dubDir);
		immutable configPath = "$DUB_BINARY_PATH".buildPath(relPath);

		immutable needle = "Unknown compiler: " ~ dubDir.buildPath(relPath);
		immutable errorMessage = "DUB did not find a locally-configured compiler with a DUB-relative path.";

		testCase(path, configPath, needle, errorMessage);
	}

	{
		immutable path = null;
		immutable configPath = "../foo";
		immutable needle = "defaultCompiler specified in a DUB config file cannot use an unqualified relative path";
		immutable errorMessage = "DUB did not error properly for a locally-configured compiler with a relative path.";

		testCase(path, configPath, needle, errorMessage);
	}

	{
		immutable path = dubDir.buildPath("ldc2");
		immutable configPath = null;
		version(Posix)
			immutable needle = "Failed to execute '" ~ absolutePath(path) ~ "'";
		else
			immutable needle = `Failed to spawn process "` ~ absolutePath(path) ~ `.exe"`;
		immutable errorMessage = "DUB did not find ldc2 adjacent to it.";

		testCase(path, configPath, needle, errorMessage);
	}

	{
		immutable path = getcwd.buildPath("foo");
		immutable configPath = "foo";
		immutable needle = "Unknown compiler: foo";
		immutable errorMessage = "DUB did not find a locally-configured compiler in its PATH.";

		testCase(path, configPath, needle, errorMessage, ["PATH": getcwd ~ pathSeparator ~ environment["PATH"]]);
	}
}

void testCase(string path, string configPath, string needle, string errorMessage, const string[string] env = null) {
	immutable cmd = [ dub, "describe", "--data=main-source-file" ];

	if (path)
		path ~= DotExe;

	if (path) write(path, "An empty file");
	scope(exit) if (path) remove(path);

	if (configPath)
		File("dub.settings.json", "w").writefln(`{ "defaultCompiler": %s }`, JSONValue(configPath).toString());
	// leave dub.settings.json in the test dir when it fails
	scope(success) if (configPath) remove("dub.settings.json");

	auto p = teeProcess(cmd, Redirect.stdout | Redirect.stderrToStdout, env);
	p.wait;
	if (!p.stdout.canFind(needle))
		die(errorMessage);
}
