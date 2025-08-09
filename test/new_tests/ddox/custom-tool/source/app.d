import std.file, std.stdio, std.string;

void main(string[] args)
{
	if (args[1] != "generate-html")
		return;
	mkdirRecurse(args[$-1]);
	File(args[$-1]~"/custom_tool_output", "w").writeln(args.join(" "));
}
