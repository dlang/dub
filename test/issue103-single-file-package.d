#!../bin/dub
/+ dub.sdl:
   name "hello_world"
+/
module hello;

void main(string[] args)
{
	import std.stdio : writeln;
	assert(args.length == 4 && args[1 .. 4] == ["foo", "--", "bar"]);
	writeln("Hello, World!");
}
