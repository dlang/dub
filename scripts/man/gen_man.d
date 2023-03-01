#!/usr/bin/env dub
/+dub.sdl:
dependency "dub" path="../.."
+/

import std.algorithm, std.conv, std.format, std.path, std.range;
import std.stdio : File;
import dub.internal.dyaml.stdsumtype;
import dub.commandline;

static struct Config
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

struct ManWriter
{
	enum Mode
	{
		man, markdown
	}

	File output;
	Mode mode;

	string escapeWord(string s)
	{
		final switch (mode) {
			case Mode.man: return s.replace(`\`, `\\`).replace(`-`, `\-`).replace(`.`, `\&.`);
			case Mode.markdown: return s.replace(`<`, `&lt;`).replace(`>`, `&gt;`);
		}
	}

	string escapeFulltext(string s)
	{
		final switch (mode) {
			case Mode.man: return s;
			case Mode.markdown: return s.replace(`<`, `&lt;`).replace(`>`, `&gt;`);
		}
	}

	string italic(string w)
	{
		final switch (mode) {
			case Mode.man: return `\fI` ~ w ~ `\fR`;
			case Mode.markdown: return `<i>` ~ w ~ `</i>`;
		}
	}

	string bold(string w)
	{
		final switch (mode) {
			case Mode.man: return `\fB` ~ w ~ `\fR`;
			case Mode.markdown: return `<b>` ~ w ~ `</b>`;
		}
	}

	string header(string heading)
	{
		final switch (mode) {
			case Mode.man: return ".SH " ~ heading;
			case Mode.markdown: return "## " ~ heading;
		}
	}

	string subheader(string heading)
	{
		final switch (mode) {
			case Mode.man: return ".SS " ~ heading;
			case Mode.markdown: return "### " ~ heading;
		}
	}

	string url(string urlAndText)
	{
		return url(urlAndText, urlAndText);
	}

	string url(string url, string text)
	{
		final switch (mode) {
			case Mode.man: return ".UR" ~ url ~ "\n" ~ text ~ "\n.UE";
			case Mode.markdown: return format!"[%s](%s)"(text, url);
		}
	}

	string autolink(string s)
	{
		final switch (mode) {
			case Mode.man: return s;
			case Mode.markdown:
				auto sanitized = s
					.replace("<b>", "")
					.replace("</b>", "")
					.replace("<i>", "")
					.replace("</i>", "")
					.replace("*", "");
				if (sanitized.startsWith("dub") && sanitized.endsWith("(1)")) {
					sanitized = sanitized[0 .. $ - 3];
					return url(sanitized ~ ".md", s);
				}
				return s;
		}
	}

	/// Links subcommands in the main dub.md file (converts the subcommand name
	/// like `init` into a link to `dub-init.md`)
	string specialLinkMainCmd(string s)
	{
		final switch (mode) {
			case Mode.man: return s;
			case Mode.markdown: return url("dub-" ~ s ~ ".md", s);
		}
	}

	void write(T...)(T args)
	{
		output.write(args);
	}

	void writeln(T...)(T args)
	{
		output.writeln(args);
	}

	void writefln(T...)(T args)
	{
		output.writefln(args);
	}

	void writeHeader(string manName, const Config config)
	{
		import std.uni : toLower;

		final switch (mode)
		{
			case Mode.man:
				static immutable manHeader =
`.TH %s 1 "%s" "The D Language Foundation" "The D Language Foundation"
.SH NAME`;
				writefln(manHeader, manName, config.date.toISOExtString.take(10));
				break;
			case Mode.markdown:
				writefln("# %s(1)", manName.toLower);
				break;
		}
	}

	void writeFooter(string seeAlso, const Config config)
	{
		const manFooter =
			header("FILES") ~ '\n'
			~ italic(escapeWord("dub.sdl")) ~ ", " ~ italic(escapeWord("dub.json")) ~ '\n'
			~ header("AUTHOR") ~ '\n'
			~ `Copyright (c) 1999-%s by The D Language Foundation` ~ '\n'
			~ header("ONLINE DOCUMENTATION") ~ '\n'
			~ url(`http://code.dlang.org/docs/commandline`) ~ '\n'
			~ header("SEE ALSO");
		writefln(manFooter, config.date.year);
		writeln(seeAlso);
	}

	string highlightArguments(string args)
	{
		import std.regex : regex, replaceAll;
		static auto re = regex("<([^>]*)>");
		const reReplacement = escapeWord("<%s>").format(italic(escapeWord(`$1`)));
		auto ret = args.replaceAll(re, reReplacement);
		if (ret.length) ret ~= ' ';
		return ret;
	}

	void beginArgs(string cmd)
	{
		if (mode == Mode.markdown)
			writeln("\n<dl>\n");
	}

	void endArgs()
	{
		if (mode == Mode.markdown)
			writeln("\n</dl>\n");
	}

	void writeArgName(string cmd, string name)
	{
		import std.regex : regex, replaceAll;
		final switch ( mode )
		{
			case Mode.man:
				writeln(".PP");
				writeln(name);
				break;
			case Mode.markdown:
				string nameEscape = name.replaceAll(regex("[^a-zA-Z0-9_-]+"), "-");
				writeln();
				writefln(`<dt id="option-%s--%s" class="option-argname">`, cmd, nameEscape);
				writefln(`<a class="anchor" href="#option-%s--%s"></a>`, cmd, nameEscape);
				writeln();
				writeln(name);
				writeln();
				writeln(`</dt>`);
				writeln();
				break;
		}
	}

	void beginArgDescription()
	{
		final switch ( mode )
		{
			case Mode.man:
				writeln(".RS 4");
				break;
			case Mode.markdown:
				writeln();
				writefln(`<dd markdown="1" class="option-desc">`);
				writeln();
				break;
		}
	}

	void endArgDescription()
	{
		final switch ( mode )
		{
			case Mode.man:
				writeln(".RE");
				break;
			case Mode.markdown:
				writeln();
				writefln(`</dd>`);
				writeln();
				break;
		}
	}

	void writeArgs(string cmdName, CommandArgs args)
	{
		beginArgs(cmdName);
		foreach (arg; args.recognizedArgs)
		{
			auto names = arg.names.split("|");
			assert(names.length == 1 || names.length == 2);
			string sarg = names[0].length == 1 ? names[0] : null;
			string larg = names[0].length > 1 ? names[0] : names.length > 1 ? names[1] : null;
			string name;
			if (sarg !is null) {
				name ~= bold(escapeWord("-%s".format(sarg)));
				if (larg !is null)
					name ~= ", ";
			}
			if (larg !is null) {
				name ~= bold(escapeWord("--%s".format(larg)));
				if (arg.defaultValue.match!((bool b) => false, _ => true))
					name ~= escapeWord("=") ~ italic("VALUE");
			}
			writeArgName(cmdName, name);
			beginArgDescription();
			writeln(arg.helpText.join(mode == Mode.man ? "\n" : "\n\n"));
			endArgDescription();
		}
		endArgs();
	}

	void writeDefinition(string key, string definition)
	{
		final switch (mode)
		{
		case Mode.man:
			writeln(".TP");
			writeln(bold(key));
			writeln(definition);
			break;
		case Mode.markdown:
			writeln(`<dt markdown="1">`);
			writeln();
			writeln(bold(key));
			writeln();
			writeln("</dt>");
			writeln(`<dd markdown="1">`);
			writeln();
			writeln(definition);
			writeln();
			writeln("</dd>");
			break;
		}
	}

	void beginDefinitionList()
	{
		final switch (mode)
		{
		case Mode.man:
			break;
		case Mode.markdown:
			writeln();
			writeln(`<dl markdown="1">`);
			writeln();
			break;
		}
	}

	void endDefinitionList()
	{
		final switch (mode)
		{
		case Mode.man:
			break;
		case Mode.markdown:
			writeln("\n</dl>\n");
			break;
		}
	}

	void writeDefaultExitCodes()
	{
		string[2][] exitCodes = [
			["0", "DUB succeeded"],
			["1", "usage errors, unknown command line flags"],
			["2", "package not found, package failed to load, miscellaneous error"]
		];

		final switch (mode)
		{
		case Mode.man:
			foreach (cm; exitCodes) {
				writeln(".TP");
				writeln(".BR ", cm[0]);
				writeln(cm[1]);
			}
			break;
		case Mode.markdown:
			beginDefinitionList();
			foreach (cm; exitCodes) {
				writeDefinition(cm[0], cm[1]);
			}
			endDefinitionList();
			break;
		}
	}
}

void writeMainManFile(CommandArgs args, CommandGroup[] commands,
                      string fileName, const Config config)
{
	auto manFile = ManWriter(
		File(config.cwd.buildPath(fileName), "w"),
		fileName.endsWith(".md") ? ManWriter.Mode.markdown : ManWriter.Mode.man
	);
	manFile.writeHeader("DUB", config);
	auto seeAlso = [
			manFile.autolink(manFile.bold("dmd") ~ "(1)"),
			manFile.autolink(manFile.bold("rdmd") ~ "(1)")
		]
		.chain(commands
			.map!(a => a.commands)
			.joiner
			.map!(cmd => manFile.autolink(manFile.bold("dub-" ~ cmd.name) ~ "(1)")))
		.joiner(", ")
		.to!string;
	scope(exit) manFile.writeFooter(seeAlso, config);

	alias writeln = (m) => manFile.writeln(m);
	writeln(`dub \- Package and build management system for D`);
	writeln(manFile.header("SYNOPSIS"));
	writeln(manFile.bold("dub") ~ text(
		" [",
		manFile.escapeWord("--version"),
		"] [",
		manFile.italic("COMMAND"),
		"] [",
		manFile.italic(manFile.escapeWord("OPTIONS...")),
		"] ", manFile.escapeWord("--"), " [",
		manFile.italic(manFile.escapeWord("APPLICATION ARGUMENTS...")),
		"]"
	));

	writeln(manFile.header("DESCRIPTION"));
	writeln(`Manages the DUB project in the current directory. DUB can serve as a build
system and a package manager, automatically keeping track of project's
dependencies \- both downloading them and linking them into the application.`);

	writeln(manFile.header("COMMANDS"));
	manFile.beginDefinitionList();
	foreach (grp; commands) {
		foreach (cmd; grp.commands) {
			manFile.writeDefinition(manFile.specialLinkMainCmd(cmd.name), cmd.helpText.join(
				manFile.mode == ManWriter.Mode.markdown ? "\n\n" : "\n"
			));
		}
	}  
  
  

	writeln(manFile.header("COMMON OPTIONS"));
	manFile.writeArgs("-", args);
}

void writeManFile(Command command, const Config config, ManWriter.Mode mode)
{
	import std.uni : toUpper;

	auto args = new CommandArgs(null);
	command.prepare(args);
	string fileName = format(mode == ManWriter.Mode.markdown ? "dub-%s.md" : "dub-%s.1", command.name);
	auto manFile = ManWriter(File(config.cwd.buildPath(fileName), "w"), mode);
	auto manName = format("DUB-%s", command.name).toUpper;
	manFile.writeHeader(manName, config);

	string[] extraRelated;
	foreach (arg; args.recognizedArgs) {
		if (arg.names.canFind("rdmd"))
			extraRelated ~= manFile.autolink(manFile.bold("rdmd") ~ "(1)");
	}
	if (command.name == "dustmite")
		extraRelated ~= manFile.autolink(manFile.bold("dustmite") ~ "(1)");

	const seeAlso = [manFile.autolink(manFile.bold("dub") ~ "(1)")]
		.chain(config.relatedSubCommands.map!(s => manFile.autolink(manFile.bold("dub-" ~ s) ~ "(1)")))
		.chain(extraRelated)
		.joiner(", ")
		.to!string;
	scope(exit) manFile.writeFooter(seeAlso, config);

	alias writeln = (m) => manFile.writeln(m);

	manFile.writefln(`dub-%s \- %s`, command.name, manFile.escapeFulltext(command.description));

	writeln(manFile.header("SYNOPSIS"));
	manFile.write(manFile.bold("dub %s ".format(command.name)));
	manFile.write(manFile.highlightArguments(command.argumentsPattern));
	writeln(manFile.italic(manFile.escapeWord(`OPTIONS...`)));
	if (command.acceptsAppArgs)
	{
		writeln("[-- <%s>]".format(manFile.italic(manFile.escapeWord("application arguments..."))));
	}

	writeln(manFile.header("DESCRIPTION"));
	writeln(manFile.escapeFulltext(command.helpText.join("\n\n")));
	writeln(manFile.header("OPTIONS"));
	manFile.writeArgs(command.name, args);

	writeln(manFile.subheader("COMMON OPTIONS"));
	manFile.writeln("See ", manFile.autolink(manFile.bold("dub") ~ "(1)"));

	manFile.writeln(manFile.header("EXIT STATUS"));
	if (command.name == "dustmite") {
		manFile.writeln("Forwards the exit code from " ~ manFile.autolink(manFile.bold(`dustmite`) ~ `(1)`));
	} else {
		manFile.writeDefaultExitCodes();
	}
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
		args.writeMainManFile(commands, "dub.md", config);
	}

	string[][] relatedSubCommands = [
		["run", "build", "test"],
		["test", "dustmite", "lint"],
		["describe", "generate"],
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

		cmd.writeManFile(config, ManWriter.Mode.man);
		cmd.writeManFile(config, ManWriter.Mode.markdown);
	}
}
