import std.stdio;

extern(C) string funkekw ();
extern(C) int fun42 ();

void main()
{
	writefln("ShouldBe42: %s", fun42());
	writefln("Juan: %s", funkekw());
}
