#!/usr/bin/env dub
/+ dub.sdl:
	name "app"
+/

import std.stdio;
import std.format;
import std.path;
import std.regex;

int main(string[] args)
{
    version (LDC)
        immutable expected = "ldmd|ldc";
    version (DigitalMars)
        immutable expected = "dmd";
    version (GNU)
        immutable expected = "gdmd|gdc";

	immutable dc = args[1];
	immutable dcBase = dc.baseName;
	if (dcBase.matchFirst(expected)) return 0;

	writefln("[FAIL]: Expected '%s' but DC is '%s'", expected, dcBase);
	return 1;
}
