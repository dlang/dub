import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	chdir("sample");

	if (spawnProcess([dub, "generate", "visuald"]).wait != 0)
		die("Dub couldn't generate visuald project");

	immutable proj = readText(".dub/extra_files.visualdproj");

	foreach (needle; ["saturate.vert" , "saturate.vert" , "LICENSE.txt" , "README.txt" ])
		if (!proj.canFind(needle))
			die("regression of issue #1053");

	immutable lineWithREADME = proj.splitter('\n').filter!(line => line.canFind("README.txt")).front;
	if (!lineWithREADME.canFind("copy /Y $(InputPath) $(TargetDir)"))
		die("Copying of copyFiles seems broken for visuald.");
}
