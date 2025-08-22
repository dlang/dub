#!/usr/bin/env dub
/+ dub.sdl:
	name "issue2051-success"
	dependency "taggedalgebraic" version="~>0.11.0"
+/

version(unittest) {}
else void main()
{
}

unittest
{
	import taggedalgebraic;

	static union Base {
		int i;
		string str;
	}

	auto dummy = TaggedAlgebraic!Base(1721);
	assert(dummy == 1721);
}
