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
	string[] relatedSubCommands;

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
http://code.dlang.org/docs/commandline
.UE
.SH "SEE ALSO"
%s`;
	manFile.writefln(manFooter, config.date.year, seeAlso);
}

void writeMainManFile(CommandArgs args, CommandGroup[] commands,
					  string fileName, const Config config)
{
	auto manFile = File(config.cwd.buildPath(fileName), "w");
	manFile.writeHeader("DUB", config);
	auto seeAlso = ["dmd(1)", "rdmd(1)"]
        .chain(commands.map!(a => a.commands).joiner
               .map!(cmd => format("dub-%s(1)", cmd.name)))
        .joiner(", ").to!string.bold;
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
	static auto re = regex("<([^>]*)>");
	static const reReplacement = "<%s>".format(`$1`.italic);
	return args.replaceAll(re, reReplacement);
}

void writeArgs(CommandArgs args, ref File manFile)
{
	alias write = (m) => manFile.write(m.replace(`-`, `\-`));
	foreach (arg; args.recognizedArgs)
	{
		auto names = arg.names.split("|");
		assert(names.length == 1 || names.length == 2);
		string sarg = names[0].length == 1 ? names[0] : null;
		string larg = names[0].length > 1 ? names[0] : names.length > 1 ? names[1] : null;
		manFile.writeln(".PP");
		if (sarg !is null) {
			write("-%s".format(sarg).bold);
			if (larg !is null)
				write(", ");
		}
		if (larg !is null) {
			write("--%s".format(larg).bold);
			if (!arg.defaultValue.peek!bool)
				write("=VALUE");
		}
		manFile.writeln;
		manFile.writeln(".RS 4");
		manFile.writeln(arg.helpText.join("\n"));
		manFile.writeln(".RE");
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

	string[] extraRelated;
	foreach (arg; args.recognizedArgs) {
		if (arg.names.canFind("rdmd"))
			extraRelated ~= "rdmd(1)";
	}
	if (command.name == "dustmite")
		extraRelated ~= "dustmite(1)";

	const seeAlso = ["dub(1)"]
		.chain(config.relatedSubCommands.map!(s => s.format!"dub-%s(1)"))
		.chain(extraRelated)
		.map!bold
		.joiner(", ")
		.to!string;
	scope(exit) manFile.writeFooter(seeAlso, config);

	alias writeln = (m) => manFile.writeln(m);
	manFile.writefln(`dub-%s \- %s`, command.name, command.description);

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

	static immutable exitStatus =
`.SH EXIT STATUS
.TP
.BR 0
DUB succeeded
.TP
.BR 1
usage errors, unknown command line flags
.TP
.BR 2
package not found, package failed to load, miscellaneous error`;
	static immutable exitStatusDustmite =
`.SH EXIT STATUS
Forwards the exit code from ` ~ `dustmite(1)`.bold;
	if (command.name == "dustmite")
		manFile.writeln(exitStatusDustmite);
	else
		manFile.writeln(exitStatus);
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

	string[][] relatedSubCommands = [
		["run", "build", "test"],
		["test", "dustmite", "lint"],
		["describe", "gemerate"],
		["add", "fetch"],
		["init", "add", "convert"],
		["add-path", "remove-path"],
		["add-local", "remove-local"],
		["list", "search"],
		["add-override", "remove-override", "list-overrides"],
		["clean-caches", "clean", "remove"],
	];

	// options for each specific command
	foreach (cmd; commands.map!(a => a.commands).joiner) {
		string[] related;
		foreach (relatedList; relatedSubCommands) {
			if (relatedList.canFind(cmd.name))
				related ~= relatedList;
		}
		related = related.sort!"a<b".uniq.array;
		related = related.remove!(c => c == cmd.name);
		config.relatedSubCommands = related;

		cmd.writeManFile(config);
	}
}
