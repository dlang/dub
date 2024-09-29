module app;

int main(string[] args)
{
	import std.conv: to;
	import std.stdio: writeln;
	if (args.length == 1)
		return 0;
	if (args.length == 3)
		writeln(args[2]);
	return args[1].to!int;
}
