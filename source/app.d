/**
	Application entry point.

	Copyright: © 2013 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module app;

import dub.commandline;

// Set output path and options for coverage reports
version (DigitalMars) version (D_Coverage)
{
	shared static this()
	{
		import core.runtime, std.file, std.path, std.stdio;
		dmd_coverSetMerge(true);
		auto path = buildPath(dirName(thisExePath()), "../cov");
		if (!path.exists)
			mkdir(path);
		dmd_coverDestPath(path);
	}
}

/**
 * Workaround https://github.com/dlang/dub/issues/1812
 *
 * On Linux, a segmentation fault happens when dub is compiled with a recent
 * compiler. While not confirmed, the logs seem to point to parallel marking
 * done by the GC. Hence this disables it.
 *
 * https://dlang.org/changelog/2.087.0.html#gc_parallel
 */
extern(C) __gshared string[] rt_options = [ "gcopt=parallel:0" ];

int main(string[] args)
{
	return runDubCommandLine(args);
}
