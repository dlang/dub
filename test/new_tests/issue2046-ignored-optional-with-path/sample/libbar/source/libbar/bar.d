module libbar.bar;

void function() bar;
static this()
{
	version (Have_libfoo)
		import libfoo.foo;
	else
		static void foo() { import std; writeln("no-foo"); }
	bar = &foo;
}
