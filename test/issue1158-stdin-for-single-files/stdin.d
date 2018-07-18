/+ dub.sdl:
	name "hello"
+/
void main(string[] args) {
	import std.stdio : writeln;
	writeln(args[1..$]);
}