/**
	Application entry point.

	Copyright: © 2013 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module app;

import dub.commandline;

int main(string[] args)
{
	return runDubCommandLine(args);
}
