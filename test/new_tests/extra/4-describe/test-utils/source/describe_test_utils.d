module describe_test_utils;

void printDifference(const char[][] dubOutput, const char[][] expected)
{
	import std.stdio;
	import std.algorithm;
	import std.range;
	import std.array;

	writefln("   dub   vs   us");
	foreach (it, us; lockstep(dubOutput, expected)) {
		if (it == us) {
			writefln("✅ '%s' vs '%s'", it, us);
		} else {
			writefln("❌ '%s' vs '%s'", it, us);
		}
	}

	const(const char[])[] extra;
	if (dubOutput.length < expected.length) {
		writeln("Dub output was cut short:");
		extra = expected[dubOutput.length .. $];
	} else if (dubOutput.length > expected.length) {
		writeln("Dub output was too much:");
		extra = dubOutput[expected.length .. $];
	}
	foreach (line; extra)
		writeln(line);
}
inout(char[]) escape(inout char[] input) {
	version(Posix)
		immutable escapeChar = '\'';
	else
		immutable escapeChar = '"';

	if (doEscape)
		return escapeChar ~ input ~ escapeChar;
	return input;
}

version(Posix) {
	immutable bool doEscape;
	shared static this() {
		import std.process;
		import std.uni;
		import std.file;
		import std.algorithm;
		import std.conv;
		doEscape = __VERSION__ < 2103 || getcwd().any!isSpace;
	}
} else
	immutable bool doEscape = true;

string myBuildPath (string[] segments...) {
	import std.path;
	// On windows:
	//
	// std.path.buildPath("c:\foo", "bar", "")
	//   => "c:\foo\bar"
	//
	// but we want "c:\foo\bar\"
	auto result = buildPath(segments);
	if (segments[$ - 1] == "")
		result ~= dirSeparator;
	return result;
}

string libName(string base) {
	version(Posix)
		return "lib" ~ base ~ ".a";
	else
		return base ~ ".lib";
}

string libSuffix() {
	version(Posix)
		return ".a";
	else
		return ".lib";
}

string fixWindowsCR(string line) {
	// FIXME: dub listing output contains \r\r\n instead of \r\n on windows
	while (line.length && line[$ - 1] == '\r')
		line = line[0 .. $ - 1];
	return line;
}
