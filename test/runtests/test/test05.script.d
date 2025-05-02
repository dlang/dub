/+ dub.sdl:
name "runtest-testcase-05"
dependency "runtests" path=".."
subConfiguration "runtests" "lib"
+/
module test05;

import lib;

void main()
{
	assert(foo(40, 2) == 42);
}
