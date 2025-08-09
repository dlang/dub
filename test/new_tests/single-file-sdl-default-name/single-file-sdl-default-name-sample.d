/++dub.sdl:
dependency "sourcelib-simple" path="../extra/1-sourceLib-simple"
+/
module single;

void main(string[] args)
{
	import sourcelib.app;
	entry();
}
