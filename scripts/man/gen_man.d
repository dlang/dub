#!/usr/bin/env dub
/+dub.sdl:
dependency "dub" path="../.."
+/

import std.algorithm, std.conv, std.format, std.path, std.range, std.stdio;
import dub.commandline;

string italic(string w)
{
	return `\fI` ~ w ~ `\fR`;
}

string bold(string w)
{
	return `\fB` ~ w ~ `\fR`;
}

string header(string heading)
{
	return ".SH " ~ heading;
}

string br(string s)
{
	return ".BR " ~ s;
}

struct Config
{
	import std.datetime;
	SysTime date;

	static Config init(){
		import std.process : environment;
		Config config;
		config.date = Clock.currTime;
		auto diffable = environment.get("DIFFABLE", "0");
		if (diffable == "1")
			config.date = SysTime(DateTime(2018, 01, 01));

		config.cwd = __FILE_FULL_PATH__.dirName;
		return config;
	}
	string cwd;
}

void writeHeader(ref File manFile, string manName, const Config config)
{
	static immutable manHeader =
`.TH %s 1 "%s" "The D Language Foundation" "The D Language Foundation"
.SH NAME`;
	manFile.writefln(manHeader, manName, config.date.toISOExtString.take(10));
}

void writeFooter(ref File manFile, string seeAlso, const Config config)
{
	static immutable manFooter =
`.SH FILES
\fIdub\&.sdl\fR, \fIdub\&.json\fR
.SH AUTHOR
Copyright (c) 1999-%s by The D Language Foundation
.SH "ONLINE DOCUMENTATION"
.UR http://code.dlang.org/docs/commandline
.UE http://code.dlang.org/docs/commandline
.SH "SEE ALSO"
%s`;
	manFile.writefln(manFooter, config.date.year, seeAlso);
}

void writeMainManFile(CommandArgs args, CommandGroup[] commands,
					  string fileName, const Config config)
{
	auto manFile = File(config.cwd.buildPath(fileName), "w");
	manFile.writeHeader("DUB", config);
	auto seeAlso = ["dmd(1)".br, "rdmd(1)"].joiner("\n").to!string;
	scope(exit) manFile.writeFooter(seeAlso, config);

	alias writeln = (m) => manFile.writeln(m);
	writeln(`dub \- Package and build management system for D`);
	writeln("SYNOPSIS".header);
	writeln(`.B dub
[\-\-version]
[\fICOMMAND\fR]
[\fIOPTIONS\&.\&.\&.\fR]
[\-\- [\fIAPPLICATION ARGUMENTS\&.\&.\&.\fR]]`);

	writeln("DESCRIPTION".header);
	writeln(`Manages the DUB project in the current directory\&. DUB can serve as a build
system and a package manager, automatically keeping track of project's
dependencies \- both downloading them and linking them into the application.`);

	writeln(".SH COMMANDS");
	foreach (grp; commands) {
		foreach (cmd; grp.commands) {
			writeln(".TP");
			writeln(cmd.name.bold);
			writeln(cmd.helpText.joiner("\n"));
		}
	}

	writeln("COMMON OPTIONS".header);
	args.writeArgs(manFile);
}

string highlightArguments(string args)
{
	import std.regex : regex, replaceAll;
	static immutable re = regex("<([^>]*)>");
	static immutable reReplacement = "<%s>".format(`$1`.italic);
	return args.replaceAll(re, reReplacement);
}

void writeArgs(CommandArgs args, ref File manFile)
{
	alias write = (m) => manFile.write(m);
	foreach (arg; args.recognizedArgs)
	{
		auto names = arg.names.split("|");
		assert(names.length == 1 || names.length == 2);
		string sarg = names[0].length == 1 ? names[0] : null;
		string larg = names[0].length > 1 ? names[0] : names.length > 1 ? names[1] : null;
		write(".IP ");
		if (sarg !is null) {
			write("-%s".format(sarg));
			if (larg !is null)
				write(", ");
		}
		if (larg !is null) {
			write("--%s".format(larg));
			if (!arg.defaultValue.peek!bool)
				write("=VALUE");
		}
		manFile.writeln;
		manFile.writeln(arg.helpText.join("\n"));
	}
}

void writeManFile(Command command, const Config config)
{
	import std.uni : toUpper;

	auto args = new CommandArgs(null);
	command.prepare(args);
	string fileName = format("dub-%s.1", command.name);
	auto manFile = File(config.cwd.buildPath(fileName), "w");
	auto manName = format("DUB-%s", command.name).toUpper;
	manFile.writeHeader(manName, config);
	static immutable seeAlso = ["dmd(1)".br, "dub(1)"].joiner("\n").to!string;
	scope(exit) manFile.writeFooter(seeAlso, config);

	alias writeln = (m) => manFile.writeln(m);
	writeln(`dub \- Package and build management system for D`);

	writeln("SYNOPSIS".header);
	writeln("dub %s".format(command.name).bold);
	writeln(command.argumentsPattern.highlightArguments);
	writeln(`OPTIONS\&.\&.\&.`.italic);
	if (command.acceptsAppArgs)
	{
		writeln("[-- <%s>]".format("application arguments...".italic));
	}

	writeln("DESCRIPTION".header);
	writeln(command.helpText.joiner("\n\n"));
	writeln("OPTIONS".header);
	args.writeArgs(manFile);
}

void main()
{
	Config config = Config.init;
	auto commands = getCommands();

	// main dub.1
	{
		CommonOptions options;
		auto args = new CommandArgs(null);
		options.prepare(args);
		args.writeMainManFile(commands, "dub.1", config);
	}

	// options for each specific command
	foreach (cmd; commands.map!(a => a.commands).joiner) {
		cmd.writeManFile(config);
	}
}
