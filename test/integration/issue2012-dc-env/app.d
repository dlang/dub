#!/usr/bin/env dub
/+ dub.sdl:
	name "app"
+/

import std.format;

void main(string[] args)
{
    version (LDC)
        immutable expected = "ldc2";
    version (DigitalMars)
        immutable expected = "dmd";
    version (GNU)
        immutable expected = "gdc";

    assert(expected == args[1], format!"Expected '%s' but got '%s'"(expected, args[1]));
}
