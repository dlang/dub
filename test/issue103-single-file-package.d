#!../bin/dub
/+ dub.sdl:
   name "hello_world"
+/
module hello;

void main()
{
	import std.stdio : writeln;
	writeln("Hello, World!");
}
