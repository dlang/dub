import common;

import std.algorithm;
import std.process;
import std.file;
import std.path;

void main () {
	auto p = spawnProcess([dub, "build", "--build=ddox"], null, Config.none, "default");
	if (p.wait != 0)
		die("Dub default ddox build failed");

	assertContains("default/docs/index.html", "ddox_project");

	p = spawnProcess([dub, "add-local", "custom-tool"]);
	if (p.wait != 0)
		die("Dub add-local failed");

	p = spawnProcess([dub, "build", "--build=ddox"], null, Config.none, "custom");
	if (p.wait != 0)
		die("Dub build ddox failed with custom tool");

	assertContains("custom/docs/custom_tool_output", "custom-tool");

	{
		immutable expected = readText("custom-tool/public/copied");
		immutable got = readText("custom/docs/copied");
		if (expected != got)
			die("The 2 'copied' files dont' match");
	}
}

void assertContains(string path, string content) {
	if (!exists(path))
		die("ddox run did not create: ", path);

	if (!readText(path).canFind(content))
		die(path, " does not contain '", content, "'");
}
