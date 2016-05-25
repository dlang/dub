/+ dub.sdl:
name "hello_world"
dependency "sourcelib-simple" path="1-sourceLib-simple"
+/
module hello;

import sourcelib.app;

void main()
{
	entry();
}
