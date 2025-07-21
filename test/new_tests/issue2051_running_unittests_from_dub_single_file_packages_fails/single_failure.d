#!/usr/bin/env dub
/+ dub.sdl:
	name "issue2051-failure"
+/

version(unittest) {}
else void main()
{
}

unittest
{
	assert(0);
}
