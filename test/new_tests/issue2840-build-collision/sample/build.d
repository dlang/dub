#!/usr/bin/env dub
/++ dub.json:
   {
       "name": "build"
   }
+/

import std.format;

immutable FullPath = __FILE_FULL_PATH__;

void main (string[] args)
{
    assert(args.length == 2, "Expected a single argument");
    assert(args[1] == FullPath, format("%s != %s -- %s", args[1], FullPath, args[0]));
}
