module b.foo;

string bar()
{
	static immutable l = import("layout.diet");
	pragma(msg, l);
	static assert(l == "fancylayout.diet");
	return import(l);
}
