#!/usr/bin/env dub
/+ dub.sdl:
	name "app"
+/

import std.format;
import std.path;

void main(string[] args)
{
    version (LDC)
        immutable expected = "ldc2";
    version (DigitalMars)
        immutable expected = "dmd";
    version (GNU)
        immutable expected = "gdc";

    const bn = baseName(args[1]);
    assert(expected == bn, format!"Expected '%s' but got '%s'"(expected, bn));
}
