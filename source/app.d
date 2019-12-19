/**
	Application entry point.

	Copyright: © 2013 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module app;

import dub.commandline;

/**
 * Workaround https://github.com/dlang/dub/issues/1812
 *
 * On Linux, a segmentation fault happens when dub is compiled with a recent
 * compiler. While not confirmed, the logs seem to point to parallel marking
 * done by the GC. Hence this disables it.
 *
 * https://dlang.org/changelog/2.087.0.html#gc_parallel
 */
static if (__VERSION__ >= 2087)
    extern(C) __gshared string[] rt_options = [ "gcopt=parallel:0" ];

int main(string[] args)
{
	return runDubCommandLine(args);
}
