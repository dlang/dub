import std.json;
import std.path;
import std.process;
import std.stdio;

string getCacheFile (in string[] program) {
	auto p = execute(program);
	with (p) {
		if (status != 0) {
			assert(false, "Failed to invoke dub describe: " ~ output);
		}
		return output.parseJSON["targets"][0]["cacheArtifactPath"].str;
	}
}

void main()
{
	version (X86_64)
		string archArg = "x86_64";
	else version (X86)
		string archArg = "x86";
	else {
		string archArg;
		writeln("Skipping because of unsupported architecture");
		return;
	}

	const describeProgram = [
		environment["DUB"],
		"describe",
		"--compiler=" ~ environment["DC"],
		"--root=" ~ __FILE_FULL_PATH__.dirName.dirName,
	];
	immutable plainCacheFile = describeProgram.getCacheFile;

	const describeWithArch = describeProgram ~ [ "--arch=" ~ archArg ];
	immutable archCacheFile = describeWithArch.getCacheFile;

	assert(plainCacheFile == archCacheFile, "--arch shouldn't have modified the cache file");
}
