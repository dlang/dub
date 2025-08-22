import common;

import std.json;
import std.path;
import std.process;

string getCacheFile (in string[] args) {
	auto p = execute([dub, "describe"] ~ args);
	with (p) {
		if (status != 0) {
			log("dub describe failed. Output:");
			log(output);
			die("Failed to invoke dub describe");
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
		skip("Unsupported architecture");
	}

	immutable plainCacheFile = getCacheFile([]);
	immutable archCacheFile = getCacheFile(["--arch=" ~ archArg]);

	if (plainCacheFile != archCacheFile)
		die("--arch shouldn't have modified the cache file");
}
