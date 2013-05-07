module dub.internal.std.process;

static if (__traits(compiles, (){ import std.process; spawnProcess(""); }())) {
	public import std.process;
} else {
	public import dub.internal.std.processcompat;
}