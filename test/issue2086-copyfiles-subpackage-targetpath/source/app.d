import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	chdir("sample");

	immutable path = "sub/to_be_deployed.txt";
	if (path.exists) path.remove;

	if (spawnProcess([dub, "build"]).wait != 0)
		die("Dub build falied");
	if (spawnProcess("./sub/sub").wait != 0)
		die("Running the subpackage failed");
}
