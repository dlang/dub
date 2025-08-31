/+ dub.sdl:
name "single-file-test"
dependency "sourcelib-simple" path="../../extra/1-sourceLib-simple"
+/
module hello;

import sourcelib.app;

void main()
{
	entry();
}
