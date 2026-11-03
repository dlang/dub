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
 * Default druntime options for the `dub` executable
 *
 * By default, druntime performs a full collection when the program exits,
 * which also spawns the parallel marking threads (one per core). For a
 * short-lived process like `dub` this is pure overhead: it accounts for
 * a significant part of the run time of an up-to-date `dub run`, which
 * is noticeable when `dub` is used as a script interpreter (shebang).
 * `dub` doesn't rely on GC finalizers for cleanup: temporary files are
 * removed in a module destructor and the C runtime flushes open streams.
 *
 * Those can still be overridden using `--DRT-gcopt=...` on the command line.
 */
extern(C) __gshared string[] rt_options = [ "gcopt=cleanup:none" ];

int main(string[] args)
{
	return runDubCommandLine(args);
}
