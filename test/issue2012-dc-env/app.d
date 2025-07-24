#!/usr/bin/env dub
/+ dub.sdl:
	name "app"
+/

import std.format;
import std.path : baseName;
import std.algorithm : canFind;

void main(string[] args)
{
    version (LDC)
        immutable expected = "ldc2";
    version (DigitalMars)
        immutable expected = "dmd";
    version (GNU)
        immutable expected = "gdc";

    assert(args[1].baseName.canFind(expected),
	   format!"Expected '%s' but got '%s'"(expected, args[1]));
}
