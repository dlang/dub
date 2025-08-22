import b.foo;

void main()
{
	static assert(import("layout.diet") == "fancylayout.diet");
	assert(bar() == "fancy");
}
