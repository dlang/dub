import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	// Check project files generated from project "root"
	chdir("sample");

	if (exists(".dub")) rmdirRecurse(".dub");

	if (spawnProcess([dub, "generate", "visuald", ":subpackage_a"]).wait != 0)
		die("dub generate subpackage failed");

	{
		immutable path = buildPath("..", "source", "library.d");
		if (!readText(".dub/library.visualdproj").canFind(`<File path="` ~ path ~ `"`))
			die("VisualD path not correct");
	}

	{
		immutable path = buildPath("..", "sub", "subpackage_a", "source", "subpackage_a.d");
		if (!readText(".dub/library_subpackage_a.visualdproj").canFind(`<File path="` ~ path ~ `"`))
			die("VisualD path not correct");
	}

	// Check project files generated from sub package level
	chdir("sub/subpackage_a");
	if (exists(".dub")) rmdirRecurse(".dub");

	if (spawnProcess([dub, "generate", "visuald"]).wait != 0)
		die("dub generate subpackage failed");

	{
		immutable path = buildPath("..", "..", "..", "source", "library.d");
		if (!readText(".dub/library.visualdproj").canFind(`<File path="` ~ path ~ `"`))
			die("VisualD path not correct");
	}

	{
		immutable path = buildPath("..", "source", "subpackage_a.d");
		if (!readText(".dub/subpackage_a.visualdproj").canFind(`<File path="` ~ path  ~ `"`))
			die("VisualD path not correct");
	}
}
