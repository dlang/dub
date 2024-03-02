/**
	Defines the behavior of the DUB command line client.

	Copyright: © 2012-2013 Matthias Dondorff, Copyright © 2012-2016 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff, Sönke Ludwig
*/
module dub.commandline;

import dub.compilers.compiler;
import dub.dependency;
import dub.dub;
import dub.generators.generator;
import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.data.json;
import dub.internal.vibecompat.inet.path;
import dub.internal.logging;
import dub.package_;
import dub.packagemanager;
import dub.packagesuppliers;
import dub.project;
import dub.internal.utils : getDUBVersion, getClosestMatch, getTempFile;

import dub.internal.dyaml.stdsumtype;

import std.algorithm;
import std.array;
import std.conv;
import std.encoding;
import std.exception;
import std.file;
import std.getopt;
import std.path : absolutePath, buildNormalizedPath, expandTilde, setExtension;
import std.process : environment, spawnProcess, wait;
import std.stdio;
import std.string;
import std.typecons : Tuple, tuple;

/** Retrieves a list of all available commands.

	Commands are grouped by category.
*/
CommandGroup[] getCommands() @safe pure nothrow
{
	return [
		CommandGroup("Package creation",
			new InitCommand
		),
		CommandGroup("Build, test and run",
			new RunCommand,
			new BuildCommand,
			new TestCommand,
			new LintCommand,
			new GenerateCommand,
			new DescribeCommand,
			new CleanCommand,
			new DustmiteCommand
		),
		CommandGroup("Package management",
			new FetchCommand,
			new AddCommand,
			new RemoveCommand,
			new UpgradeCommand,
			new AddPathCommand,
			new RemovePathCommand,
			new AddLocalCommand,
			new RemoveLocalCommand,
			new ListCommand,
			new SearchCommand,
			new AddOverrideCommand,
			new RemoveOverrideCommand,
			new ListOverridesCommand,
			new CleanCachesCommand,
			new ConvertCommand,
		)
	];
}

/** Extract the command name from the argument list

	Params:
		args = a list of string arguments that will be processed

	Returns:
		The command name that was found (may be null).
*/
string commandNameArgument(ref string[] args)
{
	if (args.length >= 1 && !args[0].startsWith("-") && !args[0].canFind(":")) {
		const result = args[0];
		args = args[1 .. $];
		return result;
	}
	return null;
}

/// test extractCommandNameArgument usage
unittest {
    {
        string[] args;
        /// It returns an empty string on when there are no args
        assert(commandNameArgument(args) is null);
        assert(!args.length);
    }

    {
        string[] args = [ "test" ];
        /// It returns the first argument when it does not start with `-`
        assert(commandNameArgument(args) == "test");
        /// There is nothing to extract when the arguments only contain the `test` cmd
        assert(!args.length);
    }

    {
        string[] args = [ "-a", "-b" ];
        /// It extracts two arguments when they are not a command
        assert(commandNameArgument(args) is null);
        assert(args == ["-a", "-b"]);
    }

    {
        string[] args = [ "-test" ];
        /// It returns the an empty string when it starts with `-`
        assert(commandNameArgument(args) is null);
        assert(args.length == 1);
    }

    {
        string[] args = [ "foo:bar" ];
        // Sub package names are ignored as command names
        assert(commandNameArgument(args) is null);
        assert(args.length == 1);
        args[0] = ":foo";
        assert(commandNameArgument(args) is null);
        assert(args.length == 1);
    }
}

/** Handles the Command Line options and commands.
*/
struct CommandLineHandler
{
	/// The list of commands that can be handled
	CommandGroup[] commandGroups;

	/// General options parser
	CommonOptions options;

	/** Create the list of all supported commands

	Returns:
		Returns the list of the supported command names
	*/
	string[] commandNames()
	{
		return commandGroups.map!(g => g.commands).joiner.map!(c => c.name).array;
	}

	/** Parses the general options and sets up the log level
		and the root_path
	*/
	string[] prepareOptions(CommandArgs args) {
		LogLevel loglevel = LogLevel.info;

		options.prepare(args);

		if (options.vverbose) loglevel = LogLevel.debug_;
		else if (options.verbose) loglevel = LogLevel.diagnostic;
		else if (options.vquiet) loglevel = LogLevel.none;
		else if (options.quiet) loglevel = LogLevel.warn;
		else if (options.verror) loglevel = LogLevel.error;
		setLogLevel(loglevel);

		if (options.root_path.empty)
		{
			options.root_path = getcwd();
		}
		else
		{
			options.root_path = options.root_path.expandTilde.absolutePath.buildNormalizedPath;
		}

		final switch (options.colorMode) with (options.Color)
		{
			case automatic:
				// Use default determined in internal.logging.initLogging().
				break;
			case on:
				foreach (ref grp; commandGroups)
					foreach (ref cmd; grp.commands)
						if (auto pc = cast(PackageBuildCommand)cmd)
							pc.baseSettings.buildSettings.options |= BuildOption.color;
				setLoggingColorsEnabled(true);  // enable colors, no matter what
				break;
			case off:
				foreach (ref grp; commandGroups)
					foreach (ref cmd; grp.commands)
						if (auto pc = cast(PackageBuildCommand)cmd)
							pc.baseSettings.buildSettings.options &= ~BuildOption.color;
				setLoggingColorsEnabled(false); // disable colors, no matter what
				break;
		}
		return args.extractAllRemainingArgs();
	}

	/** Get an instance of the requested command.

	If there is no command in the argument list, the `run` command is returned
	by default.

	If the `--help` argument previously handled by `prepareOptions`,
	`this.options.help` is already `true`, with this returning the requested
	command. If no command was requested (just dub --help) this returns the
	help command.

	Params:
		name = the command name

	Returns:
		Returns the command instance if it exists, null otherwise
	*/
	Command getCommand(string name) {
		if (name == "help" || (name == "" && options.help))
		{
			return new HelpCommand();
		}

		if (name == "")
		{
			name = "run";
		}

		foreach (grp; commandGroups)
			foreach (c; grp.commands)
				if (c.name == name) {
					return c;
				}

		return null;
	}

	/** Get an instance of the requested command after the args are sent.

	It uses getCommand to get the command instance and then calls prepare.

	Params:
		name = the command name
		args = the command arguments

	Returns:
		Returns the command instance if it exists, null otherwise
	*/
	Command prepareCommand(string name, CommandArgs args) {
		auto cmd = getCommand(name);

		if (cmd !is null && !(cast(HelpCommand)cmd))
		{
			// process command line options for the selected command
			cmd.prepare(args);
			enforceUsage(cmd.acceptsAppArgs || !args.hasAppArgs, name ~ " doesn't accept application arguments.");
		}

		return cmd;
	}
}

/// Can get the command names
unittest {
	CommandLineHandler handler;
	handler.commandGroups = getCommands();

	assert(handler.commandNames == ["init", "run", "build", "test", "lint", "generate",
		"describe", "clean", "dustmite", "fetch", "add", "remove",
		"upgrade", "add-path", "remove-path", "add-local", "remove-local", "list", "search",
		"add-override", "remove-override", "list-overrides", "clean-caches", "convert"]);
}

/// It sets the cwd as root_path by default
unittest {
	CommandLineHandler handler;

	auto args = new CommandArgs([]);
	handler.prepareOptions(args);
	assert(handler.options.root_path == getcwd());
}

/// It can set a custom root_path
unittest {
	CommandLineHandler handler;

	auto args = new CommandArgs(["--root=/tmp/test"]);
	handler.prepareOptions(args);
	assert(handler.options.root_path == "/tmp/test".absolutePath.buildNormalizedPath);

	args = new CommandArgs(["--root=./test"]);
	handler.prepareOptions(args);
	assert(handler.options.root_path == "./test".absolutePath.buildNormalizedPath);
}

/// It sets the info log level by default
unittest {
	scope(exit) setLogLevel(LogLevel.info);
	CommandLineHandler handler;

	auto args = new CommandArgs([]);
	handler.prepareOptions(args);
	assert(getLogLevel() == LogLevel.info);
}

/// It can set a custom error level
unittest {
	scope(exit) setLogLevel(LogLevel.info);
	CommandLineHandler handler;

	auto args = new CommandArgs(["--vverbose"]);
	handler.prepareOptions(args);
	assert(getLogLevel() == LogLevel.debug_);

	handler = CommandLineHandler();
	args = new CommandArgs(["--verbose"]);
	handler.prepareOptions(args);
	assert(getLogLevel() == LogLevel.diagnostic);

	handler = CommandLineHandler();
	args = new CommandArgs(["--vquiet"]);
	handler.prepareOptions(args);
	assert(getLogLevel() == LogLevel.none);

	handler = CommandLineHandler();
	args = new CommandArgs(["--quiet"]);
	handler.prepareOptions(args);
	assert(getLogLevel() == LogLevel.warn);

	handler = CommandLineHandler();
	args = new CommandArgs(["--verror"]);
	handler.prepareOptions(args);
	assert(getLogLevel() == LogLevel.error);
}

/// It returns the `run` command by default
unittest {
	CommandLineHandler handler;
	handler.commandGroups = getCommands();
	assert(handler.getCommand("").name == "run");
}

/// It returns the `help` command when there is none set and the --help arg
/// was set
unittest {
	CommandLineHandler handler;
	auto args = new CommandArgs(["--help"]);
	handler.prepareOptions(args);
	handler.commandGroups = getCommands();
	assert(cast(HelpCommand)handler.getCommand("") !is null);
}

/// It returns the `help` command when the `help` command is sent
unittest {
	CommandLineHandler handler;
	handler.commandGroups = getCommands();
	assert(cast(HelpCommand) handler.getCommand("help") !is null);
}

/// It returns the `init` command when the `init` command is sent
unittest {
	CommandLineHandler handler;
	handler.commandGroups = getCommands();
	assert(handler.getCommand("init").name == "init");
}

/// It returns null when a missing command is sent
unittest {
	CommandLineHandler handler;
	handler.commandGroups = getCommands();
	assert(handler.getCommand("missing") is null);
}

/** Processes the given command line and executes the appropriate actions.

	Params:
		args = This command line argument array as received in `main`. The first
			entry is considered to be the name of the binary invoked.

	Returns:
		Returns the exit code that is supposed to be returned to the system.
*/
int runDubCommandLine(string[] args)
{
	import std.file : tempDir;

	static string[] toSinglePackageArgs (string args0, string file, string[] trailing)
	{
		return [args0, "run", "-q", "--temp-build", "--single", file, "--"] ~ trailing;
	}

	// Initialize the logging module, ensure that whether stdout/stderr are a TTY
	// or not is detected in order to disable colors if the output isn't a console
	initLogging();

	logDiagnostic("DUB version %s", getDUBVersion());

	{
		version(Windows) {
			// Guarantee that this environment variable is set
			//  this is specifically needed because of the Windows fix that follows this statement.
			// While it probably isn't needed for all targets, it does simplify things a bit.
			// Question is can it be more generic? Probably not due to $TMP
			if ("TEMP" !in environment)
				environment["TEMP"] = tempDir();

			// rdmd uses $TEMP to compute a temporary path. since cygwin substitutes backslashes
			// with slashes, this causes OPTLINK to fail (it thinks path segments are options)
			// we substitute the other way around here to fix this.

			// In case the environment variable TEMP is empty (it should never be), we'll swap out
			//  opIndex in favor of get with the fallback.

			environment["TEMP"] = environment.get("TEMP", null).replace("/", "\\");
		}
	}

	auto handler = CommandLineHandler(getCommands());

	// Special syntaxes need to be handled before regular argument parsing
	if (args.length >= 2)
	{
		// Read input source code from stdin
		if (args[1] == "-")
		{
			auto path = getTempFile("app", ".d");
			stdin.byChunk(4096).joiner.toFile(path.toNativeString());
			args = toSinglePackageArgs(args[0], path.toNativeString(), args[2 .. $]);
		}

		// Dub has a shebang syntax to be able to use it as script, e.g.
		// #/usr/bin/env dub
		// With this approach, we need to support the file having
		// both the `.d` extension, or having none at all.
		// We also need to make sure arguments passed to the script
		// are passed to the program, not `dub`, e.g.:
		// ./my_dub_script foo bar
		// Gives us `args = [ "dub", "./my_dub_script" "foo", "bar" ]`,
		// which we need to interpret as:
		// `args = [ "dub", "./my_dub_script", "--", "foo", "bar" ]`
		else if (args[1].endsWith(".d"))
			args = toSinglePackageArgs(args[0], args[1], args[2 .. $]);

		// Here we have a problem: What if the script name is a command name ?
		// We have to assume it isn't, and to reduce the risk of false positive
		// we only consider the case where the file name is the first argument,
		// as the shell invocation cannot be controlled.
		else if (handler.getCommand(args[1]) is null && !args[1].startsWith("-")) {
			if (exists(args[1])) {
				auto path = getTempFile("app", ".d");
				copy(args[1], path.toNativeString());
				args = toSinglePackageArgs(args[0], path.toNativeString(), args[2 .. $]);
			} else if (exists(args[1].setExtension(".d"))) {
				args = toSinglePackageArgs(args[0], args[1].setExtension(".d"), args[2 .. $]);
			}
		}
	}

	auto common_args = new CommandArgs(args[1..$]);

	try
		args = handler.prepareOptions(common_args);
	catch (Exception e) {
		logError("Error processing arguments: %s", e.msg);
		logDiagnostic("Full exception: %s", e.toString().sanitize);
		logInfo("Run 'dub help' for usage information.");
		return 1;
	}

	if (handler.options.version_)
	{
		showVersion();
		return 0;
	}

	const command_name = commandNameArgument(args);
	auto command_args = new CommandArgs(args);
	Command cmd;

	try {
		cmd = handler.prepareCommand(command_name, command_args);
	} catch (Exception e) {
		logError("Error processing arguments: %s", e.msg);
		logDiagnostic("Full exception: %s", e.toString().sanitize);
		logInfo("Run 'dub help' for usage information.");
		return 1;
	}

	if (cmd is null) {
		logInfoNoTag("USAGE: dub [--version] [<command>] [<options...>] [-- [<application arguments...>]]");
		logInfoNoTag("");
		logError("Unknown command: %s", command_name);
		import std.algorithm.iteration : filter;
		import std.uni : toUpper;
		foreach (CommandGroup key; handler.commandGroups)
		{
			foreach (Command command; key.commands)
			{
				if (levenshteinDistance(command_name, command.name) < 4) {
					logInfo("Did you mean '%s'?", command.name);
				}
			}
		}

		logInfoNoTag("");
		return 1;
	}

	if (cast(HelpCommand)cmd !is null) {
		showHelp(handler.commandGroups, common_args);
		return 0;
	}

	if (handler.options.help) {
		showCommandHelp(cmd, command_args, common_args);
		return 0;
	}

	auto remaining_args = command_args.extractRemainingArgs();
	if (remaining_args.any!(a => a.startsWith("-"))) {
		logError("Unknown command line flags: %s", remaining_args.filter!(a => a.startsWith("-")).array.join(" ").color(Mode.bold));
		logInfo(`Type "%s" to get a list of all supported flags.`, text("dub ", cmd.name, " -h").color(Mode.bold));
		return 1;
	}

	try {
		// initialize the root package
		Dub dub = cmd.prepareDub(handler.options);

		// execute the command
		return cmd.execute(dub, remaining_args, command_args.appArgs);
	}
	catch (UsageException e) {
		// usage exceptions get thrown before any logging, so we are
		// making the errors more narrow to better fit on small screens.
		tagWidth.push(5);
		logError("%s", e.msg);
		logDebug("Full exception: %s", e.toString().sanitize);
		logInfo(`Run "%s" for more information about the "%s" command.`,
			text("dub ", cmd.name, " -h").color(Mode.bold), cmd.name.color(Mode.bold));
		return 1;
	}
	catch (Exception e) {
		// most exceptions get thrown before logging, so same thing here as
		// above. However this might be subject to change if it results in
		// weird behavior anywhere.
		tagWidth.push(5);
		logError("%s", e.msg);
		logDebug("Full exception: %s", e.toString().sanitize);
		return 2;
	}
}


/** Contains and parses options common to all commands.
*/
struct CommonOptions {
	bool verbose, vverbose, quiet, vquiet, verror, version_;
	bool help, annotate, bare;
	string[] registry_urls;
	string root_path, recipeFile;
	enum Color { automatic, on, off }
	Color colorMode = Color.automatic;
	SkipPackageSuppliers skipRegistry = SkipPackageSuppliers.none;
	PlacementLocation placementLocation = PlacementLocation.user;

	deprecated("Use `Color` instead, the previous naming was a limitation of error message formatting")
	alias color = Color;
	deprecated("Use `colorMode` instead")
	alias color_mode = colorMode;

	private void parseColor(string option, string value) @safe
	{
		// `automatic`, `on`, `off` are there for backwards compatibility
		// `auto`, `always`, `never` is being used for compatibility with most
		// other development and linux tools, after evaluating what other tools
		// are doing, to help users intuitively pick correct values.
		// See https://github.com/dlang/dub/issues/2410 for discussion
		if (!value.length || value == "auto" || value == "automatic")
			colorMode = Color.automatic;
		else if (value == "always" || value == "on")
			colorMode = Color.on;
		else if (value == "never" || value == "off")
			colorMode = Color.off;
		else
			throw new ConvException("Unable to parse argument '--" ~ option ~ "=" ~ value
				~ "', supported values: --color[=auto], --color=always, --color=never");
	}

	/// Parses all common options and stores the result in the struct instance.
	void prepare(CommandArgs args)
	{
		args.getopt("h|help", &help, ["Display general or command specific help"]);
		args.getopt("root", &root_path, ["Path to operate in instead of the current working dir"]);
		args.getopt("recipe", &recipeFile, ["Loads a custom recipe path instead of dub.json/dub.sdl"]);
		args.getopt("registry", &registry_urls, [
			"Search the given registry URL first when resolving dependencies. Can be specified multiple times. Available registry types:",
			"  DUB: URL to DUB registry (default)",
			"  Maven: URL to Maven repository + group id containing dub packages as artifacts. E.g. mvn+http://localhost:8040/maven/libs-release/dubpackages",
			]);
		args.getopt("skip-registry", &skipRegistry, [
			"Sets a mode for skipping the search on certain package registry types:",
			"  none: Search all configured or default registries (default)",
			"  standard: Don't search the main registry (e.g. "~defaultRegistryURLs[0]~")",
			"  configured: Skip all default and user configured registries",
			"  all: Only search registries specified with --registry",
			]);
		args.getopt("annotate", &annotate, ["Do not perform any action, just print what would be done"]);
		args.getopt("bare", &bare, ["Read only packages contained in the current directory"]);
		args.getopt("v|verbose", &verbose, ["Print diagnostic output"]);
		args.getopt("vverbose", &vverbose, ["Print debug output"]);
		args.getopt("q|quiet", &quiet, ["Only print warnings and errors"]);
		args.getopt("verror", &verror, ["Only print errors"]);
		args.getopt("vquiet", &vquiet, ["Print no messages"]);
		args.getopt("color", &colorMode, &parseColor, [
			"Configure colored output. Accepted values:",
			"       auto: Colored output on console/terminal,",
			"             unless NO_COLOR is set and non-empty (default)",
			"     always: Force colors enabled",
			"      never: Force colors disabled"
			]);
		args.getopt("cache", &placementLocation, ["Puts any fetched packages in the specified location [local|system|user]."]);

		version_ = args.hasAppVersion;
	}
}

/** Encapsulates a set of application arguments.

	This class serves two purposes. The first is to provide an API for parsing
	command line arguments (`getopt`). At the same time it records all calls
	to `getopt` and provides a list of all possible options using the
	`recognizedArgs` property.
*/
class CommandArgs {
	struct Arg {
		alias Value = SumType!(string[], string, bool, int, uint);

		Value defaultValue;
		Value value;
		string names;
		string[] helpText;
		bool hidden;
	}
	private {
		string[] m_args;
		Arg[] m_recognizedArgs;
		string[] m_appArgs;
	}

	/** Initializes the list of source arguments.

		Note that all array entries are considered application arguments (i.e.
		no application name entry is present as the first entry)
	*/
	this(string[] args) @safe pure nothrow
	{
		auto app_args_idx = args.countUntil("--");

		m_appArgs = app_args_idx >= 0 ? args[app_args_idx+1 .. $] : [];
		m_args = "dummy" ~ (app_args_idx >= 0 ? args[0..app_args_idx] : args);
	}

	/** Checks if the app arguments are present.

	Returns:
		true if an -- argument is given with arguments after it, otherwise false
	*/
	@property bool hasAppArgs() { return m_appArgs.length > 0; }


	/** Checks if the `--version` argument is present on the first position in
	the list.

	Returns:
		true if the application version argument was found on the first position
	*/
	@property bool hasAppVersion() { return m_args.length > 1 && m_args[1] == "--version"; }

	/** Returns the list of app args.

		The app args are provided after the `--` argument.
	*/
	@property string[] appArgs() { return m_appArgs; }

	/** Returns the list of all options recognized.

		This list is created by recording all calls to `getopt`.
	*/
	@property const(Arg)[] recognizedArgs() { return m_recognizedArgs; }

	void getopt(T)(string names, T* var, string[] help_text = null, bool hidden=false)
	{
		getopt!T(names, var, null, help_text, hidden);
	}

	void getopt(T)(string names, T* var, void delegate(string, string) @safe parseValue, string[] help_text = null, bool hidden=false)
	{
		import std.traits : OriginalType;

		foreach (ref arg; m_recognizedArgs)
			if (names == arg.names) {
				assert(help_text is null, format!("Duplicated argument '%s' must not change helptext, consider to remove the duplication")(names));
				*var = arg.value.match!(
					(OriginalType!T v) => cast(T)v,
					(_) {
						if (false)
							return T.init;
						assert(false, "value from previous getopt has different type than the current getopt call");
					}
				);
				return;
			}
		assert(help_text.length > 0);
		Arg arg;
		arg.defaultValue = cast(OriginalType!T)*var;
		arg.names = names;
		arg.helpText = help_text;
		arg.hidden = hidden;
		if (parseValue is null)
			m_args.getopt(config.passThrough, names, var);
		else
			m_args.getopt(config.passThrough, names, parseValue);
		arg.value = cast(OriginalType!T)*var;
		m_recognizedArgs ~= arg;
	}

	/** Resets the list of available source arguments.
	*/
	void dropAllArgs()
	{
		m_args = null;
	}

	/** Returns the list of unprocessed arguments, ignoring the app arguments,
	and resets the list of available source arguments.
	*/
	string[] extractRemainingArgs()
	{
		assert(m_args !is null, "extractRemainingArgs must be called only once.");

		auto ret = m_args[1 .. $];
		m_args = null;
		return ret;
	}

	/** Returns the list of unprocessed arguments, including the app arguments
		and resets the list of available source arguments.
	*/
	string[] extractAllRemainingArgs()
	{
		auto ret = extractRemainingArgs();

		if (this.hasAppArgs)
		{
			ret ~= "--" ~ m_appArgs;
		}

		return ret;
	}
}

/// Using CommandArgs
unittest {
	/// It should not find the app version for an empty arg list
	assert(new CommandArgs([]).hasAppVersion == false);

	/// It should find the app version when `--version` is the first arg
	assert(new CommandArgs(["--version"]).hasAppVersion == true);

	/// It should not find the app version when `--version` is the second arg
	assert(new CommandArgs(["a", "--version"]).hasAppVersion == false);

	/// It returns an empty app arg list when `--` arg is missing
	assert(new CommandArgs(["1", "2"]).appArgs == []);

	/// It returns an empty app arg list when `--` arg is missing
	assert(new CommandArgs(["1", "2"]).appArgs == []);

	/// It returns app args set after "--"
	assert(new CommandArgs(["1", "2", "--", "a"]).appArgs == ["a"]);
	assert(new CommandArgs(["1", "2", "--"]).appArgs == []);
	assert(new CommandArgs(["--"]).appArgs == []);
	assert(new CommandArgs(["--", "a"]).appArgs == ["a"]);

	/// It returns the list of all args when no args are processed
	assert(new CommandArgs(["1", "2", "--", "a"]).extractAllRemainingArgs == ["1", "2", "--", "a"]);
}

/// It removes the extracted args
unittest {
	auto args = new CommandArgs(["-a", "-b", "--", "-c"]);
	bool value;
	args.getopt("b", &value, [""]);

	assert(args.extractAllRemainingArgs == ["-a", "--", "-c"]);
}

/// It should not be able to remove app args
unittest {
	auto args = new CommandArgs(["-a", "-b", "--", "-c"]);
	bool value;
	args.getopt("-c", &value, [""]);

	assert(!value);
	assert(args.extractAllRemainingArgs == ["-a", "-b", "--", "-c"]);
}

/** Base class for all commands.

	This cass contains a high-level description of the command, including brief
	and full descriptions and a human readable command line pattern. On top of
	that it defines the two main entry functions for command execution.
*/
class Command {
	string name;
	string argumentsPattern;
	string description;
	string[] helpText;
	bool acceptsAppArgs;
	bool hidden = false; // used for deprecated commands

	/** Parses all known command line options without executing any actions.

		This function will be called prior to execute, or may be called as
		the only method when collecting the list of recognized command line
		options.

		Only `args.getopt` should be called within this method.
	*/
	abstract void prepare(scope CommandArgs args);

	/**
	 * Initialize the dub instance used by `execute`
	 */
	public Dub prepareDub(CommonOptions options) {
		Dub dub;

		if (options.bare) {
			dub = new Dub(NativePath(options.root_path), getWorkingDirectory());
			dub.defaultPlacementLocation = options.placementLocation;

			return dub;
		}

		// initialize DUB
		auto package_suppliers = options.registry_urls
			.map!((url) {
				// Allow to specify fallback mirrors as space separated urls. Undocumented as we
				// should simply retry over all registries instead of using a special
				// FallbackPackageSupplier.
				auto urls = url.splitter(' ');
				PackageSupplier ps = getRegistryPackageSupplier(urls.front);
				urls.popFront;
				if (!urls.empty)
					ps = new FallbackPackageSupplier(ps ~ urls.map!getRegistryPackageSupplier.array);
				return ps;
			})
			.array;

		dub = new Dub(options.root_path, package_suppliers, options.skipRegistry);
		dub.dryRun = options.annotate;
		dub.defaultPlacementLocation = options.placementLocation;
		dub.mainRecipePath = options.recipeFile;
		// make the CWD package available so that for example sub packages can reference their
		// parent package.
		try dub.packageManager.getOrLoadPackage(NativePath(options.root_path), NativePath(options.recipeFile), false, StrictMode.Warn);
		catch (Exception e) {
			// by default we ignore CWD package load fails in prepareDUB, since
			// they will fail again later when they are actually requested. This
			// is done to provide custom options to the loading logic and should
			// ideally be moved elsewhere. (This catch has been around since 10
			// years when it was first introduced in _app.d_)
			logDiagnostic("No valid package found in current working directory: %s", e.msg);

			// for now, we work around not knowing if the package is needed or
			// not, simply by trusting the user to only use `--recipe` when the
			// recipe file actually exists, otherwise we throw the error.
			bool loadMustSucceed = options.recipeFile.length > 0;
			if (loadMustSucceed)
				throw e;
		}

		return dub;
	}

	/** Executes the actual action.

		Note that `prepare` will be called before any call to `execute`.
	*/
	abstract int execute(Dub dub, string[] free_args, string[] app_args);

	private bool loadCwdPackage(Dub dub, bool warn_missing_package)
	{
		auto filePath = dub.packageManager.findPackageFile(dub.rootPath);

		if (filePath.empty) {
			if (warn_missing_package) {
				logInfoNoTag("");
				logInfoNoTag("No package manifest (dub.json or dub.sdl) was found in");
				logInfoNoTag(dub.rootPath.toNativeString());
				logInfoNoTag("Please run DUB from the root directory of an existing package, or run");
				logInfoNoTag("\"%s\" to get information on creating a new package.", "dub init --help".color(Mode.bold));
				logInfoNoTag("");
			}
			return false;
		}

		dub.loadPackage();

		return true;
	}
}


/** Encapsulates a group of commands that fit into a common category.
*/
struct CommandGroup {
	/// Caption of the command category
	string caption;

	/// List of commands contained in this group
	Command[] commands;

	this(string caption, Command[] commands...) @safe pure nothrow
	{
		this.caption = caption;
		this.commands = commands.dup;
	}
}

/******************************************************************************/
/* HELP                                                                       */
/******************************************************************************/

class HelpCommand : Command {

	this() @safe pure nothrow
	{
		this.name = "help";
		this.description = "Shows the help message";
		this.helpText = [
			"Shows the help message and the supported command options."
		];
	}

	/// HelpCommand.prepare is not supposed to be called, use
	/// cast(HelpCommand)this to check if help was requested before execution.
	override void prepare(scope CommandArgs args)
	{
		assert(false, "HelpCommand.prepare is not supposed to be called, use cast(HelpCommand)this to check if help was requested before execution.");
	}

	/// HelpCommand.execute is not supposed to be called, use
	/// cast(HelpCommand)this to check if help was requested before execution.
	override int execute(Dub dub, string[] free_args, string[] app_args) {
		assert(false, "HelpCommand.execute is not supposed to be called, use cast(HelpCommand)this to check if help was requested before execution.");
	}
}

/******************************************************************************/
/* INIT                                                                       */
/******************************************************************************/

class InitCommand : Command {
	private{
		string m_templateType = "minimal";
		PackageFormat m_format = PackageFormat.json;
		bool m_nonInteractive;
	}
	this() @safe pure nothrow
	{
		this.name = "init";
		this.argumentsPattern = "[<directory> [<dependency>...]]";
		this.description = "Initializes an empty package skeleton";
		this.helpText = [
			"Initializes an empty package of the specified type in the given directory.",
			"By default, the current working directory is used.",
			"",
			"Custom templates can be defined by packages by providing a sub-package called \"init-exec\". No default source files are added in this case.",
			"The \"init-exec\" sub-package is compiled and executed inside the destination folder after the base project directory has been created.",
			"Free arguments \"dub init -t custom -- free args\" are passed into the \"init-exec\" sub-package as app arguments."
		];
		this.acceptsAppArgs = true;
	}

	override void prepare(scope CommandArgs args)
	{
		args.getopt("t|type", &m_templateType, [
			"Set the type of project to generate. Available types:",
			"",
			"minimal - simple \"hello world\" project (default)",
			"vibe.d  - minimal HTTP server based on vibe.d",
			"deimos  - skeleton for C header bindings",
			"custom  - custom project provided by dub package",
		]);
		args.getopt("f|format", &m_format, [
			"Sets the format to use for the package description file. Possible values:",
			"  " ~ [__traits(allMembers, PackageFormat)].map!(f => f == m_format.init.to!string ? f ~ " (default)" : f).join(", ")
		]);
		args.getopt("n|non-interactive", &m_nonInteractive, ["Don't enter interactive mode."]);
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		string dir;
		if (free_args.length)
		{
			dir = free_args[0];
			free_args = free_args[1 .. $];
		}

		static string input(string caption, string default_value)
		{
			import dub.internal.colorize;
			cwritef("%s [%s]: ", caption.color(Mode.bold), default_value);
			auto inp = readln();
			return inp.length > 1 ? inp[0 .. $-1] : default_value;
		}

		static string select(string caption, bool free_choice, string default_value, const string[] options...)
		{
			import dub.internal.colorize.cwrite;
			assert(options.length);
			import std.math : floor, log10;
			auto ndigits = (size_t val) => log10(cast(double) val).floor.to!uint + 1;

			immutable default_idx = options.countUntil(default_value);
			immutable max_width = options.map!(s => s.length).reduce!max + ndigits(options.length) + "  ".length;
			immutable num_columns = max(1, 82 / max_width);
			immutable num_rows = (options.length + num_columns - 1) / num_columns;

			string[] options_matrix;
			options_matrix.length = num_rows * num_columns;
			foreach (i, option; options)
			{
				size_t y = i % num_rows;
				size_t x = i / num_rows;
				options_matrix[x + y * num_columns] = option;
			}

			auto idx_to_user = (string option) => cast(uint)options.countUntil(option) + 1;
			auto user_to_idx = (size_t i) => cast(uint)i - 1;

			assert(default_idx >= 0);
			cwriteln((free_choice ? "Select or enter " : "Select ").color(Mode.bold), caption.color(Mode.bold), ":".color(Mode.bold));
			foreach (i, option; options_matrix)
			{
				if (i != 0 && (i % num_columns) == 0) cwriteln();
				if (!option.length)
					continue;
				auto user_id = idx_to_user(option);
				cwritef("%*u)".color(Color.cyan, Mode.bold) ~ " %s", ndigits(options.length), user_id,
					leftJustifier(option, max_width));
			}
			cwriteln();
			immutable default_choice = (default_idx + 1).to!string;
			while (true)
			{
				auto choice = input(free_choice ? "?" : "#?", default_choice);
				if (choice is default_choice)
					return default_value;
				choice = choice.strip;
				uint option_idx = uint.max;
				try
					option_idx = cast(uint)user_to_idx(to!uint(choice));
				catch (ConvException)
				{}
				if (option_idx != uint.max)
				{
					if (option_idx < options.length)
						return options[option_idx];
				}
				else if (free_choice || options.canFind(choice))
					return choice;
				logError("Select an option between 1 and %u%s.", options.length,
						 free_choice ? " or enter a custom value" : null);
			}
		}

		static string license_select(string def)
		{
			static immutable licenses = [
				"BSL-1.0 (Boost)",
				"MIT",
				"Unlicense (public domain)",
				"Apache-",
				"-1.0",
				"-1.1",
				"-2.0",
				"AGPL-",
				"-1.0-only",
				"-1.0-or-later",
				"-3.0-only",
				"-3.0-or-later",
				"GPL-",
				"-2.0-only",
				"-2.0-or-later",
				"-3.0-only",
				"-3.0-or-later",
				"LGPL-",
				"-2.0-only",
				"-2.0-or-later",
				"-2.1-only",
				"-2.1-or-later",
				"-3.0-only",
				"-3.0-or-later",
				"BSD-",
				"-1-Clause",
				"-2-Clause",
				"-3-Clause",
				"-4-Clause",
				"MPL- (Mozilla)",
				"-1.0",
				"-1.1",
				"-2.0",
				"-2.0-no-copyleft-exception",
				"EUPL-",
				"-1.0",
				"-1.1",
				"-2.0",
				"CC- (Creative Commons)",
				"-BY-4.0 (Attribution 4.0 International)",
				"-BY-SA-4.0 (Attribution Share Alike 4.0 International)",
				"Zlib",
				"ISC",
				"proprietary",
			];

			static string sanitize(string license)
			{
				auto desc = license.countUntil(" (");
				if (desc != -1)
					license = license[0 .. desc];
				return license;
			}

			string[] root;
			foreach (l; licenses)
				if (!l.startsWith("-"))
					root ~= l;

			string result;
			while (true)
			{
				string picked;
				if (result.length)
				{
					auto start = licenses.countUntil!(a => a == result || a.startsWith(result ~ " (")) + 1;
					auto end = start;
					while (end < licenses.length && licenses[end].startsWith("-"))
						end++;
					picked = select(
						"variant of " ~ result[0 .. $ - 1],
						false,
						"(back)",
						// https://dub.pm/package-format-json.html#licenses
						licenses[start .. end].map!"a[1..$]".array ~ "(back)"
					);
					if (picked == "(back)")
					{
						result = null;
						continue;
					}
					picked = sanitize(picked);
				}
				else
				{
					picked = select(
						"an SPDX license-identifier ("
							~ "https://spdx.org/licenses/".color(Color.light_blue, Mode.underline)
							~ ")".color(Mode.bold),
						true,
						def,
						// https://dub.pm/package-format-json.html#licenses
						root
					);
					picked = sanitize(picked);
				}
				if (picked == def)
					return def;

				if (result.length)
					result ~= picked;
				else
					result = picked;

				if (!result.endsWith("-"))
					return result;
			}
		}

		void depCallback(ref PackageRecipe p, ref PackageFormat fmt) {
			import std.datetime: Clock;

			if (m_nonInteractive) return;

			enum free_choice = true;
			fmt = select("a package recipe format", !free_choice, fmt.to!string, "sdl", "json").to!PackageFormat;
			auto author = p.authors.join(", ");
			while (true) {
				// Tries getting the name until a valid one is given.
				import std.regex;
				auto nameRegex = regex(`^[a-z0-9\-_]+$`);
				string triedName = input("Name", p.name);
				if (triedName.matchFirst(nameRegex).empty) {
					logError(`Invalid name '%s', names should consist only of lowercase alphanumeric characters, dashes ('-') and underscores ('_').`, triedName);
				} else {
					p.name = triedName;
					break;
				}
			}
			p.description = input("Description", p.description);
			p.authors = input("Author name", author).split(",").map!(a => a.strip).array;
			p.license = license_select(p.license);
			string copyrightString = .format("Copyright © %s, %-(%s, %)", Clock.currTime().year, p.authors);
			p.copyright = input("Copyright string", copyrightString);

			while (true) {
				auto depspec = input("Add dependency (leave empty to skip)", null);
				if (!depspec.length) break;
				addDependency(dub, p, depspec);
			}
		}

		if (!["vibe.d", "deimos", "minimal"].canFind(m_templateType))
		{
			free_args ~= m_templateType;
		}
		dub.createEmptyPackage(NativePath(dir), free_args, m_templateType, m_format, &depCallback, app_args);

		logInfo("Package successfully created in %s", dir.length ? dir : ".");
		return 0;
	}
}


/******************************************************************************/
/* GENERATE / BUILD / RUN / TEST / DESCRIBE                                   */
/******************************************************************************/

abstract class PackageBuildCommand : Command {
	protected {
		string m_compilerName;
		string m_arch;
		string[] m_debugVersions;
		string[] m_dVersions;
		string[] m_overrideConfigs;
		GeneratorSettings baseSettings;
		string m_defaultConfig;
		bool m_nodeps;
		bool m_forceRemove = false;
	}

	override void prepare(scope CommandArgs args)
	{
		args.getopt("b|build", &this.baseSettings.buildType, [
			"Specifies the type of build to perform. Note that setting the DFLAGS environment variable will override the build type with custom flags.",
			"Possible names:",
			"  "~builtinBuildTypes.join(", ")~" and custom types"
		]);
		args.getopt("c|config", &this.baseSettings.config, [
			"Builds the specified configuration. Configurations can be defined in dub.json"
		]);
		args.getopt("override-config", &m_overrideConfigs, [
			"Uses the specified configuration for a certain dependency. Can be specified multiple times.",
			"Format: --override-config=<dependency>/<config>"
		]);
		args.getopt("compiler", &m_compilerName, [
			"Specifies the compiler binary to use (can be a path).",
			"Arbitrary pre- and suffixes to the identifiers below are recognized (e.g. ldc2 or dmd-2.063) and matched to the proper compiler type:",
			"  "~["dmd", "gdc", "ldc", "gdmd", "ldmd"].join(", ")
		]);
		args.getopt("a|arch", &m_arch, [
			"Force a different architecture (e.g. x86 or x86_64)"
		]);
		args.getopt("d|debug", &m_debugVersions, [
			"Define the specified `debug` version identifier when building - can be used multiple times"
		]);
		args.getopt("d-version", &m_dVersions, [
			"Define the specified `version` identifier when building - can be used multiple times.",
			"Use sparingly, with great power comes great responsibility! For commonly used or combined versions "
				~ "and versions that dependees should be able to use, create configurations in your package."
		]);
		args.getopt("nodeps", &m_nodeps, [
			"Do not resolve missing dependencies before building"
		]);
		args.getopt("build-mode", &this.baseSettings.buildMode, [
			"Specifies the way the compiler and linker are invoked. Valid values:",
			"  separate (default), allAtOnce, singleFile"
		]);
		args.getopt("single", &this.baseSettings.single, [
			"Treats the package name as a filename. The file must contain a package recipe comment."
		]);
		args.getopt("force-remove", &m_forceRemove, [
			"Deprecated option that does nothing."
		]);
		args.getopt("filter-versions", &this.baseSettings.filterVersions, [
			"[Experimental] Filter version identifiers and debug version identifiers to improve build cache efficiency."
		]);
	}

	protected void setupVersionPackage(Dub dub, string str_package_info, string default_build_type = "debug")
	{
		UserPackageDesc udesc = UserPackageDesc.fromString(str_package_info);
		setupPackage(dub, udesc, default_build_type);
	}

	protected void setupPackage(Dub dub, UserPackageDesc udesc, string default_build_type = "debug")
	{
		if (!m_compilerName.length) m_compilerName = dub.defaultCompiler;
		if (!m_arch.length) m_arch = dub.defaultArchitecture;
		if (dub.defaultLowMemory) this.baseSettings.buildSettings.options |= BuildOption.lowmem;
		if (dub.defaultEnvironments) this.baseSettings.buildSettings.addEnvironments(dub.defaultEnvironments);
		if (dub.defaultBuildEnvironments) this.baseSettings.buildSettings.addBuildEnvironments(dub.defaultBuildEnvironments);
		if (dub.defaultRunEnvironments) this.baseSettings.buildSettings.addRunEnvironments(dub.defaultRunEnvironments);
		if (dub.defaultPreGenerateEnvironments) this.baseSettings.buildSettings.addPreGenerateEnvironments(dub.defaultPreGenerateEnvironments);
		if (dub.defaultPostGenerateEnvironments) this.baseSettings.buildSettings.addPostGenerateEnvironments(dub.defaultPostGenerateEnvironments);
		if (dub.defaultPreBuildEnvironments) this.baseSettings.buildSettings.addPreBuildEnvironments(dub.defaultPreBuildEnvironments);
		if (dub.defaultPostBuildEnvironments) this.baseSettings.buildSettings.addPostBuildEnvironments(dub.defaultPostBuildEnvironments);
		if (dub.defaultPreRunEnvironments) this.baseSettings.buildSettings.addPreRunEnvironments(dub.defaultPreRunEnvironments);
		if (dub.defaultPostRunEnvironments) this.baseSettings.buildSettings.addPostRunEnvironments(dub.defaultPostRunEnvironments);
		this.baseSettings.compiler = getCompiler(m_compilerName);
		this.baseSettings.platform = this.baseSettings.compiler.determinePlatform(this.baseSettings.buildSettings, m_compilerName, m_arch);
		this.baseSettings.buildSettings.addDebugVersions(m_debugVersions);
		this.baseSettings.buildSettings.addVersions(m_dVersions);

		m_defaultConfig = null;
		enforce(loadSpecificPackage(dub, udesc), "Failed to load package.");

		if (this.baseSettings.config.length != 0 &&
			!dub.configurations.canFind(this.baseSettings.config) &&
			this.baseSettings.config != "unittest")
		{
			string msg = "Unknown build configuration: " ~ this.baseSettings.config;
			enum distance = 3;
			auto match = dub.configurations.getClosestMatch(this.baseSettings.config, distance);
			if (match !is null) msg ~= ". Did you mean '" ~ match ~ "'?";
			enforce(0, msg);
		}

		if (this.baseSettings.buildType.length == 0) {
			if (environment.get("DFLAGS") !is null) this.baseSettings.buildType = "$DFLAGS";
			else this.baseSettings.buildType = default_build_type;
		}

		if (!m_nodeps) {
			// retrieve missing packages
			if (!dub.project.hasAllDependencies) {
				logDiagnostic("Checking for missing dependencies.");
				if (this.baseSettings.single)
					dub.upgrade(UpgradeOptions.select | UpgradeOptions.noSaveSelections);
				else dub.upgrade(UpgradeOptions.select);
			}
		}

		dub.project.validate();

		foreach (sc; m_overrideConfigs) {
			auto idx = sc.indexOf('/');
			enforceUsage(idx >= 0, "Expected \"<package>/<configuration>\" as argument to --override-config.");
			dub.project.overrideConfiguration(sc[0 .. idx], sc[idx+1 .. $]);
		}
	}

	private bool loadSpecificPackage(Dub dub, UserPackageDesc udesc)
	{
		if (this.baseSettings.single) {
			enforce(udesc.name.length, "Missing file name of single-file package.");
			dub.loadSingleFilePackage(udesc.name);
			return true;
		}


		bool from_cwd = udesc.name.length == 0 || udesc.name.startsWith(":");
		// load package in root_path to enable searching for sub packages
		if (loadCwdPackage(dub, from_cwd)) {
			if (udesc.name.startsWith(":"))
			{
				auto pack = dub.packageManager.getSubPackage(
					dub.project.rootPackage, udesc.name[1 .. $], false);
				dub.loadPackage(pack);
				return true;
			}
			if (from_cwd) return true;
		}

		enforce(udesc.name.length, "No valid root package found - aborting.");

		auto pack = dub.packageManager.getBestPackage(
			PackageName(udesc.name), udesc.range);

		enforce(pack, format!"Failed to find package '%s' locally."(udesc));
		logInfo("Building package %s in %s", pack.name, pack.path.toNativeString());
		dub.loadPackage(pack);
		return true;
	}
}

class GenerateCommand : PackageBuildCommand {
	protected {
		string m_generator;
		bool m_printPlatform, m_printBuilds, m_printConfigs;
		bool m_deep; // only set in BuildCommand
	}

	this() @safe pure nothrow
	{
		this.name = "generate";
		this.argumentsPattern = "<generator> [<package>[@<version-spec>]]";
		this.description = "Generates project files using the specified generator";
		this.helpText = [
			"Generates project files using one of the supported generators:",
			"",
			"visuald - VisualD project files",
			"sublimetext - SublimeText project file",
			"cmake - CMake build scripts",
			"build - Builds the package directly",
			"",
			"An optional package name can be given to generate a different package than the root/CWD package."
		];
	}

	override void prepare(scope CommandArgs args)
	{
		super.prepare(args);

		args.getopt("combined", &this.baseSettings.combined, [
			"Tries to build the whole project in a single compiler run."
		]);

		args.getopt("print-builds", &m_printBuilds, [
			"Prints the list of available build types"
		]);
		args.getopt("print-configs", &m_printConfigs, [
			"Prints the list of available configurations"
		]);
		args.getopt("print-platform", &m_printPlatform, [
			"Prints the identifiers for the current build platform as used for the build fields in dub.json"
		]);
		args.getopt("parallel", &this.baseSettings.parallelBuild, [
			"Runs multiple compiler instances in parallel, if possible."
		]);
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		string str_package_info;
		if (!m_generator.length) {
			enforceUsage(free_args.length >= 1 && free_args.length <= 2, "Expected one or two arguments.");
			m_generator = free_args[0];
			if (free_args.length >= 2) str_package_info = free_args[1];
		} else {
			enforceUsage(free_args.length <= 1, "Expected one or zero arguments.");
			if (free_args.length >= 1) str_package_info = free_args[0];
		}

		setupVersionPackage(dub, str_package_info, "debug");

		if (m_printBuilds) {
			logInfo("Available build types:");
			foreach (i, tp; dub.project.builds)
				logInfo("  %s%s", tp, i == 0 ? " [default]" : null);
			logInfo("");
		}

		m_defaultConfig = dub.project.getDefaultConfiguration(this.baseSettings.platform);
		if (m_printConfigs) {
			logInfo("Available configurations:");
			foreach (tp; dub.configurations)
				logInfo("  %s%s", tp, tp == m_defaultConfig ? " [default]" : null);
			logInfo("");
		}

		GeneratorSettings gensettings = this.baseSettings;
		if (!gensettings.config.length)
			gensettings.config = m_defaultConfig;
		gensettings.runArgs = app_args;
		gensettings.recipeName = dub.mainRecipePath;
		// legacy compatibility, default working directory is always CWD
		gensettings.overrideToolWorkingDirectory = getWorkingDirectory();
		gensettings.buildDeep = m_deep;

		logDiagnostic("Generating using %s", m_generator);
		dub.generateProject(m_generator, gensettings);
		if (this.baseSettings.buildType == "ddox") dub.runDdox(gensettings.run, app_args);
		return 0;
	}
}

class BuildCommand : GenerateCommand {
	protected {
		bool m_yes; // automatic yes to prompts;
		bool m_nonInteractive;
	}
	this() @safe pure nothrow
	{
		this.name = "build";
		this.argumentsPattern = "[<package>[@<version-spec>]]";
		this.description = "Builds a package (uses the main package in the current working directory by default)";
		this.helpText = [
			"Builds a package (uses the main package in the current working directory by default)"
		];
	}

	override void prepare(scope CommandArgs args)
	{
		args.getopt("temp-build", &this.baseSettings.tempBuild, [
			"Builds the project in the temp folder if possible."
		]);

		args.getopt("rdmd", &this.baseSettings.rdmd, [
			"Use rdmd instead of directly invoking the compiler"
		]);

		args.getopt("f|force", &this.baseSettings.force, [
			"Forces a recompilation even if the target is up to date"
		]);
		args.getopt("y|yes", &m_yes, [
			`Automatic yes to prompts. Assume "yes" as answer to all interactive prompts.`
		]);
		args.getopt("n|non-interactive", &m_nonInteractive, [
			"Don't enter interactive mode."
		]);
		args.getopt("d|deep", &m_deep, [
			"Build all dependencies, even when main target is a static library."
		]);
		super.prepare(args);
		m_generator = "build";
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		// single package files don't need to be downloaded, they are on the disk.
		if (free_args.length < 1 || this.baseSettings.single)
			return super.execute(dub, free_args, app_args);

		if (!m_nonInteractive)
		{
			const packageParts = UserPackageDesc.fromString(free_args[0]);
			if (auto rc = fetchMissingPackages(dub, packageParts))
				return rc;
		}
		return super.execute(dub, free_args, app_args);
	}

	private int fetchMissingPackages(Dub dub, in UserPackageDesc packageParts)
	{
		static bool input(string caption, bool default_value = true) {
			writef("%s [%s]: ", caption, default_value ? "Y/n" : "y/N");
			auto inp = readln();
			string userInput = "y";
			if (inp.length > 1)
				userInput = inp[0 .. $ - 1].toLower;

			switch (userInput) {
				case "no", "n", "0":
					return false;
				case "yes", "y", "1":
				default:
					return true;
			}
		}

		// Local subpackages are always assumed to be present
		if (packageParts.name.startsWith(":"))
			return 0;

		const baseName = PackageName(packageParts.name).main;
		// Found locally
		if (dub.packageManager.getBestPackage(baseName, packageParts.range))
			return 0;

		// Non-interactive, either via flag, or because a version was provided
		if (m_yes || !packageParts.range.matchesAny()) {
			dub.fetch(baseName, packageParts.range);
			return 0;
		}
		// Otherwise we go the long way of asking the user.
		// search for the package and filter versions for exact matches
		auto search = dub.searchPackages(baseName.toString())
			.map!(tup => tup[1].find!(p => p.name == baseName.toString()))
			.filter!(ps => !ps.empty);
		if (search.empty) {
			logWarn("Package '%s' was neither found locally nor online.", packageParts);
			return 2;
		}

		const p = search.front.front;
		logInfo("Package '%s' was not found locally but is available online:", packageParts);
		logInfo("---");
		logInfo("Description: %s", p.description);
		logInfo("Version: %s", p.version_);
		logInfo("---");

		if (input("Do you want to fetch '%s@%s' now?".format(packageParts, p.version_)))
			dub.fetch(baseName, VersionRange.fromString(p.version_));
		return 0;
	}
}

class RunCommand : BuildCommand {
	this() @safe pure nothrow
	{
		this.name = "run";
		this.argumentsPattern = "[<package>[@<version-spec>]]";
		this.description = "Builds and runs a package (default command)";
		this.helpText = [
			"Builds and runs a package (uses the main package in the current working directory by default)"
		];
		this.acceptsAppArgs = true;
	}

	override void prepare(scope CommandArgs args)
	{
		super.prepare(args);
		this.baseSettings.run = true;
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		return super.execute(dub, free_args, app_args);
	}
}

class TestCommand : PackageBuildCommand {
	private {
		string m_mainFile;
	}

	this() @safe pure nothrow
	{
		this.name = "test";
		this.argumentsPattern = "[<package>[@<version-spec>]]";
		this.description = "Executes the tests of the selected package";
		this.helpText = [
			`Builds the package and executes all contained unit tests.`,
			``,
			`If no explicit configuration is given, an existing "unittest" ` ~
			`configuration will be preferred for testing. If none exists, the ` ~
			`first library type configuration will be used, and if that doesn't ` ~
			`exist either, the first executable configuration is chosen.`,
			``,
			`When a custom main file (--main-file) is specified, only library ` ~
			`configurations can be used. Otherwise, depending on the type of ` ~
			`the selected configuration, either an existing main file will be ` ~
			`used (and needs to be properly adjusted to just run the unit ` ~
			`tests for 'version(unittest)'), or DUB will generate one for ` ~
			`library type configurations.`,
			``,
			`Finally, if the package contains a dependency to the "tested" ` ~
			`package, the automatically generated main file will use it to ` ~
			`run the unit tests.`
		];
		this.acceptsAppArgs = true;
	}

	override void prepare(scope CommandArgs args)
	{
		args.getopt("temp-build", &this.baseSettings.tempBuild, [
			"Builds the project in the temp folder if possible."
		]);

		args.getopt("main-file", &m_mainFile, [
			"Specifies a custom file containing the main() function to use for running the tests."
		]);
		args.getopt("combined", &this.baseSettings.combined, [
			"Tries to build the whole project in a single compiler run."
		]);
		args.getopt("parallel", &this.baseSettings.parallelBuild, [
			"Runs multiple compiler instances in parallel, if possible."
		]);
		args.getopt("f|force", &this.baseSettings.force, [
			"Forces a recompilation even if the target is up to date"
		]);

		bool coverage = false;
		args.getopt("coverage", &coverage, [
			"Enables code coverage statistics to be generated."
		]);
		if (coverage) this.baseSettings.buildType = "unittest-cov";

		bool coverageCTFE = false;
		args.getopt("coverage-ctfe", &coverageCTFE, [
			"Enables code coverage (including CTFE) statistics to be generated."
		]);
		if (coverageCTFE) this.baseSettings.buildType = "unittest-cov-ctfe";

		super.prepare(args);
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		string str_package_info;
		enforceUsage(free_args.length <= 1, "Expected one or zero arguments.");
		if (free_args.length >= 1) str_package_info = free_args[0];

		setupVersionPackage(dub, str_package_info, "unittest");

		GeneratorSettings settings = this.baseSettings;
		settings.compiler = getCompiler(this.baseSettings.platform.compilerBinary);
		settings.run = true;
		settings.runArgs = app_args;

		dub.testProject(settings, this.baseSettings.config, NativePath(m_mainFile));
		return 0;
	}
}

class LintCommand : PackageBuildCommand {
	private {
		bool m_syntaxCheck = false;
		bool m_styleCheck = false;
		string m_errorFormat;
		bool m_report = false;
		string m_reportFormat;
		string m_reportFile;
		string[] m_importPaths;
		string m_config;
	}

	this() @safe pure nothrow
	{
		this.name = "lint";
		this.argumentsPattern = "[<package>[@<version-spec>]]";
		this.description = "Executes the linter tests of the selected package";
		this.helpText = [
			`Builds the package and executes D-Scanner linter tests.`
		];
		this.acceptsAppArgs = true;
	}

	override void prepare(scope CommandArgs args)
	{
		args.getopt("syntax-check", &m_syntaxCheck, [
			"Lexes and parses sourceFile, printing the line and column number of " ~
			"any syntax errors to stdout."
		]);

		args.getopt("style-check", &m_styleCheck, [
			"Lexes and parses sourceFiles, printing the line and column number of " ~
			"any static analysis check failures stdout."
		]);

		args.getopt("error-format", &m_errorFormat, [
			"Format errors produced by the style/syntax checkers."
		]);

		args.getopt("report", &m_report, [
			"Generate a static analysis report in JSON format."
		]);

		args.getopt("report-format", &m_reportFormat, [
			"Specifies the format of the generated report."
		]);

		args.getopt("report-file", &m_reportFile, [
			"Write report to file."
		]);

		if (m_reportFormat || m_reportFile) m_report = true;

		args.getopt("import-paths", &m_importPaths, [
			"Import paths"
		]);

		args.getopt("dscanner-config", &m_config, [
			"Use the given d-scanner configuration file."
		]);

		super.prepare(args);
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		string str_package_info;
		enforceUsage(free_args.length <= 1, "Expected one or zero arguments.");
		if (free_args.length >= 1) str_package_info = free_args[0];

		string[] args;
		if (!m_syntaxCheck && !m_styleCheck && !m_report && app_args.length == 0) { m_styleCheck = true; }

		if (m_syntaxCheck) args ~= "--syntaxCheck";
		if (m_styleCheck) args ~= "--styleCheck";
		if (m_errorFormat) args ~= ["--errorFormat", m_errorFormat];
		if (m_report) args ~= "--report";
		if (m_reportFormat) args ~= ["--reportFormat", m_reportFormat];
		if (m_reportFile) args ~= ["--reportFile", m_reportFile];
		foreach (import_path; m_importPaths) args ~= ["-I", import_path];
		if (m_config) args ~= ["--config", m_config];

		setupVersionPackage(dub, str_package_info);
		dub.lintProject(args ~ app_args);
		return 0;
	}
}

class DescribeCommand : PackageBuildCommand {
	private {
		bool m_importPaths = false;
		bool m_stringImportPaths = false;
		bool m_dataList = false;
		bool m_dataNullDelim = false;
		string[] m_data;
	}

	this() @safe pure nothrow
	{
		this.name = "describe";
		this.argumentsPattern = "[<package>[@<version-spec>]]";
		this.description = "Prints a JSON description of the project and its dependencies";
		this.helpText = [
			"Prints a JSON build description for the root package an all of " ~
			"their dependencies in a format similar to a JSON package " ~
			"description file. This is useful mostly for IDEs.",
			"",
			"All usual options that are also used for build/run/generate apply.",
			"",
			"When --data=VALUE is supplied, specific build settings for a project " ~
			"will be printed instead (by default, formatted for the current compiler).",
			"",
			"The --data=VALUE option can be specified multiple times to retrieve " ~
			"several pieces of information at once. A comma-separated list is " ~
			"also acceptable (ex: --data=dflags,libs). The data will be output in " ~
			"the same order requested on the command line.",
			"",
			"The accepted values for --data=VALUE are:",
			"",
			"main-source-file, dflags, lflags, libs, linker-files, " ~
			"source-files, versions, debug-versions, import-paths, " ~
			"string-import-paths, import-files, options",
			"",
			"The following are also accepted by --data if --data-list is used:",
			"",
			"target-type, target-path, target-name, working-directory, " ~
			"copy-files, string-import-files, pre-generate-commands, " ~
			"post-generate-commands, pre-build-commands, post-build-commands, " ~
			"pre-run-commands, post-run-commands, requirements",
		];
	}

	override void prepare(scope CommandArgs args)
	{
		super.prepare(args);

		args.getopt("import-paths", &m_importPaths, [
			"Shortcut for --data=import-paths --data-list"
		]);

		args.getopt("string-import-paths", &m_stringImportPaths, [
			"Shortcut for --data=string-import-paths --data-list"
		]);

		args.getopt("data", &m_data, [
			"Just list the values of a particular build setting, either for this "~
			"package alone or recursively including all dependencies. Accepts a "~
			"comma-separated list. See above for more details and accepted "~
			"possibilities for VALUE."
		]);

		args.getopt("data-list", &m_dataList, [
			"Output --data information in list format (line-by-line), instead "~
			"of formatting for a compiler command line.",
		]);

		args.getopt("data-0", &m_dataNullDelim, [
			"Output --data information using null-delimiters, rather than "~
			"spaces or newlines. Result is usable with, ex., xargs -0.",
		]);
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		enforceUsage(
			!(m_importPaths && m_stringImportPaths),
			"--import-paths and --string-import-paths may not be used together."
		);

		enforceUsage(
			!(m_data && (m_importPaths || m_stringImportPaths)),
			"--data may not be used together with --import-paths or --string-import-paths."
		);

		// disable all log output to stdout and use "writeln" to output the JSON description
		auto ll = getLogLevel();
		setLogLevel(max(ll, LogLevel.warn));
		scope (exit) setLogLevel(ll);

		string str_package_info;
		enforceUsage(free_args.length <= 1, "Expected one or zero arguments.");
		if (free_args.length >= 1) str_package_info = free_args[0];
		setupVersionPackage(dub, str_package_info);

		m_defaultConfig = dub.project.getDefaultConfiguration(this.baseSettings.platform);

		GeneratorSettings settings = this.baseSettings;
		if (!settings.config.length)
			settings.config = m_defaultConfig;
		settings.cache = dub.cachePathDontUse(); // See function's description
		// Ignore other options
		settings.buildSettings.options = this.baseSettings.buildSettings.options & BuildOption.lowmem;

		// With a requested `unittest` config, switch to the special test runner
		// config (which doesn't require an existing `unittest` configuration).
		if (this.baseSettings.config == "unittest") {
			const test_config = dub.project.addTestRunnerConfiguration(settings, !dub.dryRun);
			if (test_config) settings.config = test_config;
		}

		if (m_importPaths) { m_data = ["import-paths"]; m_dataList = true; }
		else if (m_stringImportPaths) { m_data = ["string-import-paths"]; m_dataList = true; }

		if (m_data.length) {
			ListBuildSettingsFormat lt;
			with (ListBuildSettingsFormat)
				lt = m_dataList ? (m_dataNullDelim ? listNul : list) : (m_dataNullDelim ? commandLineNul : commandLine);
			dub.listProjectData(settings, m_data, lt);
		} else {
			auto desc = dub.project.describe(settings);
			writeln(desc.serializeToPrettyJson());
		}

		return 0;
	}
}

class CleanCommand : Command {
	private {
		bool m_allPackages;
	}

	this() @safe pure nothrow
	{
		this.name = "clean";
		this.argumentsPattern = "[<package>]";
		this.description = "Removes intermediate build files and cached build results";
		this.helpText = [
			"This command removes any cached build files of the given package(s). The final target file, as well as any copyFiles are currently not removed.",
			"Without arguments, the package in the current working directory will be cleaned."
		];
	}

	override void prepare(scope CommandArgs args)
	{
		args.getopt("all-packages", &m_allPackages, [
			"Cleans up *all* known packages (dub list)"
		]);
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		enforceUsage(free_args.length <= 1, "Expected one or zero arguments.");
		enforceUsage(app_args.length == 0, "Application arguments are not supported for the clean command.");
		enforceUsage(!m_allPackages || !free_args.length, "The --all-packages flag may not be used together with an explicit package name.");

		enforce(free_args.length == 0, "Cleaning a specific package isn't possible right now.");

		if (m_allPackages) {
			dub.clean();
		} else {
			dub.loadPackage();
			dub.clean(dub.project.rootPackage);
		}

		return 0;
	}
}


/******************************************************************************/
/* FETCH / ADD / REMOVE / UPGRADE                                             */
/******************************************************************************/

class AddCommand : Command {
	this() @safe pure nothrow
	{
		this.name = "add";
		this.argumentsPattern = "<package>[@<version-spec>] [<packages...>]";
		this.description = "Adds dependencies to the package file.";
		this.helpText = [
			"Adds <packages> as dependencies.",
			"",
			"Running \"dub add <package>\" is the same as adding <package> to the \"dependencies\" section in dub.json/dub.sdl.",
			"If no version is specified for one of the packages, dub will query the registry for the latest version."
		];
	}

	override void prepare(scope CommandArgs args) {}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		import dub.recipe.io : readPackageRecipe, writePackageRecipe;
		enforceUsage(free_args.length != 0, "Expected one or more arguments.");
		enforceUsage(app_args.length == 0, "Unexpected application arguments.");

		if (!loadCwdPackage(dub, true)) return 2;
		auto recipe = dub.project.rootPackage.rawRecipe.clone;

		foreach (depspec; free_args) {
			if (!addDependency(dub, recipe, depspec))
				return 2;
		}
		writePackageRecipe(dub.project.rootPackage.recipePath, recipe);

		return 0;
	}
}

class UpgradeCommand : Command {
	private {
		bool m_prerelease = false;
		bool m_includeSubPackages = false;
		bool m_forceRemove = false;
		bool m_missingOnly = false;
		bool m_verify = false;
		bool m_dryRun = false;
	}

	this() @safe pure nothrow
	{
		this.name = "upgrade";
		this.argumentsPattern = "[<packages...>]";
		this.description = "Forces an upgrade of the dependencies";
		this.helpText = [
			"Upgrades all dependencies of the package by querying the package registry(ies) for new versions.",
			"",
			"This will update the versions stored in the selections file ("~SelectedVersions.defaultFile~") accordingly.",
			"",
			"If one or more package names are specified, only those dependencies will be upgraded. Otherwise all direct and indirect dependencies of the root package will get upgraded."
		];
	}

	override void prepare(scope CommandArgs args)
	{
		args.getopt("prerelease", &m_prerelease, [
			"Uses the latest pre-release version, even if release versions are available"
		]);
		args.getopt("s|sub-packages", &m_includeSubPackages, [
			"Also upgrades dependencies of all directory based sub packages"
		]);
		args.getopt("verify", &m_verify, [
			"Updates the project and performs a build. If successful, rewrites the selected versions file <to be implemented>."
		]);
		args.getopt("dry-run", &m_dryRun, [
			"Only print what would be upgraded, but don't actually upgrade anything."
		]);
		args.getopt("missing-only", &m_missingOnly, [
			"Performs an upgrade only for dependencies that don't yet have a version selected. This is also done automatically before each build."
		]);
		args.getopt("force-remove", &m_forceRemove, [
			"Deprecated option that does nothing."
		]);
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		enforceUsage(free_args.length <= 1, "Unexpected arguments.");
		enforceUsage(app_args.length == 0, "Unexpected application arguments.");
		enforceUsage(!m_verify, "--verify is not yet implemented.");
		enforce(loadCwdPackage(dub, true), "Failed to load package.");
		logInfo("Upgrading", Color.cyan, "project in %s", dub.projectPath.toNativeString().color(Mode.bold));
		auto options = UpgradeOptions.upgrade|UpgradeOptions.select;
		if (m_missingOnly) options &= ~UpgradeOptions.upgrade;
		if (m_prerelease) options |= UpgradeOptions.preRelease;
		if (m_dryRun) options |= UpgradeOptions.dryRun;
		dub.upgrade(options, free_args);

		auto spacks = dub.project.rootPackage
			.subPackages
			.filter!(sp => sp.path.length);

		if (m_includeSubPackages) {
			bool any_error = false;

			// Go through each path based sub package, load it as a new instance
			// and perform an upgrade as if the upgrade had been run from within
			// the sub package folder. Note that we have to use separate Dub
			// instances, because the upgrade always works on the root package
			// of a project, which in this case are the individual sub packages.
			foreach (sp; spacks) {
				try {
					auto fullpath = (dub.projectPath ~ sp.path).toNativeString();
					logInfo("Upgrading", Color.cyan, "sub package in %s", fullpath);
					auto sdub = new Dub(fullpath, dub.packageSuppliers, SkipPackageSuppliers.all);
					sdub.defaultPlacementLocation = dub.defaultPlacementLocation;
					sdub.loadPackage();
					sdub.upgrade(options, free_args);
				} catch (Exception e) {
					logError("Failed to update sub package at %s: %s",
						sp.path, e.msg);
					any_error = true;
				}
			}

			if (any_error) return 1;
		} else if (!spacks.empty) {
			foreach (sp; spacks)
				logInfo("Not upgrading sub package in %s", sp.path);
			logInfo("\nNote: specify -s to also upgrade sub packages.");
		}

		return 0;
	}
}

class FetchRemoveCommand : Command {
	protected {
		string m_version;
		bool m_forceRemove = false;
	}

	override void prepare(scope CommandArgs args)
	{
		args.getopt("version", &m_version, [
			"Use the specified version/branch instead of the latest available match",
			"The remove command also accepts \"*\" here as a wildcard to remove all versions of the package from the specified location"
		], true); // hide --version from help

		args.getopt("force-remove", &m_forceRemove, [
			"Deprecated option that does nothing"
		]);
	}

	abstract override int execute(Dub dub, string[] free_args, string[] app_args);
}

class FetchCommand : FetchRemoveCommand {
	private enum FetchStatus
	{
		/// Package is already present and on the right version
		Present = 0,
		/// Package was fetched from the registry
		Fetched = 1,
		/// Attempts at fetching the package failed
		Failed = 2,
	}

	protected bool recursive;
	protected size_t[FetchStatus.max + 1] result;

	this() @safe pure nothrow
	{
		this.name = "fetch";
		this.argumentsPattern = "<package>[@<version-spec>]";
		this.description = "Explicitly retrieves and caches packages";
		this.helpText = [
			"When run with one or more arguments, regardless of the location it is run in,",
			"it will fetch the packages matching the argument(s).",
			"Examples:",
			"$ dub fetch vibe-d",
			"$ dub fetch vibe-d@v0.9.0 --cache=local --recursive",
			"",
			"When run in a project with no arguments, it will fetch all dependencies for that project.",
			"If the project doesn't have set dependencies (no 'dub.selections.json'), it will also perform dependency resolution.",
			"Example:",
			"$ cd myProject && dub fetch",
			"",
			"Note that the 'build', 'run', and any other command that need packages will automatically perform fetch,",
			"hence it is not generally necessary to run this command before any other."
		];
	}

	override void prepare(scope CommandArgs args)
	{
		args.getopt("r|recursive", &this.recursive, [
			"Also fetches dependencies of specified packages",
		]);
		super.prepare(args);
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		enforceUsage(app_args.length == 0, "Unexpected application arguments.");

		// remove then --version removed
		if (m_version.length) {
			enforceUsage(free_args.length == 1, "Expecting exactly one argument when using --version.");
			const name = free_args[0];
			logWarn("The '--version' parameter was deprecated, use %s@%s. Please update your scripts.", name, m_version);
			enforceUsage(!name.canFindVersionSplitter, "Double version spec not allowed.");
			this.fetchPackage(dub, UserPackageDesc(name, VersionRange.fromString(m_version)));
			return this.result[FetchStatus.Failed] ? 1 : 0;
		}

		// Fetches dependencies of the project
		// This is obviously mutually exclusive with the below foreach
		if (!free_args.length) {
			if (!this.loadCwdPackage(dub, true))
				return 1;
			// retrieve missing packages
			if (!dub.project.hasAllDependencies) {
				logInfo("Resolving", Color.green, "missing dependencies for project");
				dub.upgrade(UpgradeOptions.select);
			}
			else
				logInfo("All %s dependencies are already present locally",
						dub.project.dependencies.length);
			return 0;
		}

        // Fetches packages named explicitly
		foreach (name; free_args) {
			const udesc = UserPackageDesc.fromString(name);
			this.fetchPackage(dub, udesc);
		}
        // Note that this does not include packages indirectly fetched.
        // Hence it is not currently displayed in the no-argument version,
        // and will only include directly mentioned packages in the arg version.
		logInfoNoTag("%s packages fetched, %s already present, %s failed",
				this.result[FetchStatus.Fetched], this.result[FetchStatus.Present],
				this.result[FetchStatus.Failed]);
		return this.result[FetchStatus.Failed] ? 1 : 0;
	}

    /// Shell around `fetchSinglePackage` with logs and recursion support
    private void fetchPackage(Dub dub, UserPackageDesc udesc)
    {
        auto r = this.fetchSinglePackage(dub, udesc);
        this.result[r] += 1;
        final switch (r) {
        case FetchStatus.Failed:
            // Error displayed in `fetchPackage` as it has more information
            // However we need to return here as we can't recurse.
            return;
        case FetchStatus.Present:
            logInfo("Existing", Color.green, "package %s found locally", udesc);
            break;
        case FetchStatus.Fetched:
            logInfo("Fetched", Color.green, "package %s successfully", udesc);
            break;
        }
        if (this.recursive) {
            auto pack = dub.packageManager.getBestPackage(
				PackageName(udesc.name), udesc.range);
            auto proj = new Project(dub.packageManager, pack);
            if (!proj.hasAllDependencies) {
				logInfo("Resolving", Color.green, "missing dependencies for project");
				dub.loadPackage(pack);
				dub.upgrade(UpgradeOptions.select);
			}
        }
    }

	/// Implementation for argument version
	private FetchStatus fetchSinglePackage(Dub dub, UserPackageDesc udesc)
	{
		auto fspkg = dub.packageManager.getBestPackage(
			PackageName(udesc.name), udesc.range);
		// Avoid dub fetch if the package is present on the filesystem.
		if (fspkg !is null && udesc.range.isExactVersion())
			return FetchStatus.Present;

		try {
			auto pkg = dub.fetch(PackageName(udesc.name), udesc.range,
				FetchOptions.forceBranchUpgrade);
			assert(pkg !is null, "dub.fetch returned a null Package");
			return pkg is fspkg ? FetchStatus.Present : FetchStatus.Fetched;
		} catch (Exception e) {
			logError("Fetching %s failed: %s", udesc, e.msg);
			return FetchStatus.Failed;
		}
	}
}

class RemoveCommand : FetchRemoveCommand {
	private {
		bool m_nonInteractive;
	}

	this() @safe pure nothrow
	{
		this.name = "remove";
		this.argumentsPattern = "<package>[@<version-spec>]";
		this.description = "Removes a cached package";
		this.helpText = [
			"Removes a package that is cached on the local system."
		];
	}

	override void prepare(scope CommandArgs args)
	{
		super.prepare(args);
		args.getopt("n|non-interactive", &m_nonInteractive, ["Don't enter interactive mode."]);
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		enforceUsage(free_args.length == 1, "Expecting exactly one argument.");
		enforceUsage(app_args.length == 0, "Unexpected application arguments.");

		auto package_id = free_args[0];
		auto location = dub.defaultPlacementLocation;

		size_t resolveVersion(in Package[] packages) {
			// just remove only package version
			if (packages.length == 1)
				return 0;

			writeln("Select version of '", package_id, "' to remove from location '", location, "':");
			foreach (i, pack; packages)
				writefln("%s) %s", i + 1, pack.version_);
			writeln(packages.length + 1, ") ", "all versions");
			while (true) {
				writef("> ");
				auto inp = readln();
				if (!inp.length) // Ctrl+D
					return size_t.max;
				inp = inp.stripRight;
				if (!inp.length) // newline or space
					continue;
				try {
					immutable selection = inp.to!size_t - 1;
					if (selection <= packages.length)
						return selection;
				} catch (ConvException e) {
				}
				logError("Please enter a number between 1 and %s.", packages.length + 1);
			}
		}

		if (!m_version.empty) { // remove then --version removed
			enforceUsage(!package_id.canFindVersionSplitter, "Double version spec not allowed.");
			logWarn("The '--version' parameter was deprecated, use %s@%s. Please update your scripts.", package_id, m_version);
			dub.remove(PackageName(package_id), m_version, location);
		} else {
			const parts = UserPackageDesc.fromString(package_id);
            const explicit = package_id.canFindVersionSplitter;
			if (m_nonInteractive || explicit || parts.range != VersionRange.Any) {
                const str = parts.range.matchesAny() ? "*" : parts.range.toString();
				dub.remove(PackageName(parts.name), str, location);
			} else {
				dub.remove(PackageName(package_id), location, &resolveVersion);
			}
		}
		return 0;
	}
}

/******************************************************************************/
/* ADD/REMOVE PATH/LOCAL                                                      */
/******************************************************************************/

abstract class RegistrationCommand : Command {
	private {
		bool m_system;
	}

	override void prepare(scope CommandArgs args)
	{
		args.getopt("system", &m_system, [
			"DEPRECATED: Use --cache=system instead"
		], true);
	}

	abstract override int execute(Dub dub, string[] free_args, string[] app_args);
}

class AddPathCommand : RegistrationCommand {
	this() @safe pure nothrow
	{
		this.name = "add-path";
		this.argumentsPattern = "<path>";
		this.description = "Adds a default package search path";
		this.helpText = [
			"Adds a default package search path. All direct sub folders of this path will be searched for package descriptions and will be made available as packages. Using this command has the equivalent effect as calling 'dub add-local' on each of the sub folders manually.",
			"",
			"Any packages registered using add-path will be preferred over packages downloaded from the package registry when searching for dependencies during a build operation.",
			"",
			"The version of the packages will be determined by one of the following:",
			"  - For GIT working copies, the last tag (git describe) is used to determine the version",
			"  - If the package contains a \"version\" field in the package description, this is used",
			"  - If neither of those apply, \"~master\" is assumed"
		];
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		enforceUsage(free_args.length == 1, "Missing search path.");
		enforceUsage(!this.m_system || dub.defaultPlacementLocation == PlacementLocation.user,
			"Cannot use both --system and --cache, prefer --cache");
		if (this.m_system)
			dub.addSearchPath(free_args[0], PlacementLocation.system);
		else
			dub.addSearchPath(free_args[0], dub.defaultPlacementLocation);
		return 0;
	}
}

class RemovePathCommand : RegistrationCommand {
	this() @safe pure nothrow
	{
		this.name = "remove-path";
		this.argumentsPattern = "<path>";
		this.description = "Removes a package search path";
		this.helpText = ["Removes a package search path previously added with add-path."];
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		enforceUsage(free_args.length == 1, "Expected one argument.");
		enforceUsage(!this.m_system || dub.defaultPlacementLocation == PlacementLocation.user,
			"Cannot use both --system and --cache, prefer --cache");
		if (this.m_system)
			dub.removeSearchPath(free_args[0], PlacementLocation.system);
		else
			dub.removeSearchPath(free_args[0], dub.defaultPlacementLocation);
		return 0;
	}
}

class AddLocalCommand : RegistrationCommand {
	this() @safe pure nothrow
	{
		this.name = "add-local";
		this.argumentsPattern = "<path> [<version>]";
		this.description = "Adds a local package directory (e.g. a git repository)";
		this.helpText = [
			"Adds a local package directory to be used during dependency resolution. This command is useful for registering local packages, such as GIT working copies, that are either not available in the package registry, or are supposed to be overwritten.",
			"",
			"The version of the package is either determined automatically (see the \"add-path\" command, or can be explicitly overwritten by passing a version on the command line.",
			"",
			"See 'dub add-path -h' for a way to register multiple local packages at once."
		];
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		enforceUsage(free_args.length == 1 || free_args.length == 2,
			"Expecting one or two arguments.");
		enforceUsage(!this.m_system || dub.defaultPlacementLocation == PlacementLocation.user,
			"Cannot use both --system and --cache, prefer --cache");

		string ver = free_args.length == 2 ? free_args[1] : null;
		if (this.m_system)
			dub.addLocalPackage(free_args[0], ver, PlacementLocation.system);
		else
			dub.addLocalPackage(free_args[0], ver, dub.defaultPlacementLocation);
		return 0;
	}
}

class RemoveLocalCommand : RegistrationCommand {
	this() @safe pure nothrow
	{
		this.name = "remove-local";
		this.argumentsPattern = "<path>";
		this.description = "Removes a local package directory";
		this.helpText = ["Removes a local package directory"];
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		enforceUsage(free_args.length >= 1, "Missing package path argument.");
		enforceUsage(free_args.length <= 1,
			"Expected the package path to be the only argument.");
		enforceUsage(!this.m_system || dub.defaultPlacementLocation == PlacementLocation.user,
			"Cannot use both --system and --cache, prefer --cache");

		if (this.m_system)
			dub.removeLocalPackage(free_args[0], PlacementLocation.system);
		else
			dub.removeLocalPackage(free_args[0], dub.defaultPlacementLocation);
		return 0;
	}
}

class ListCommand : Command {
	this() @safe pure nothrow
	{
		this.name = "list";
		this.argumentsPattern = "[<package>[@<version-spec>]]";
		this.description = "Prints a list of all or selected local packages dub is aware of";
		this.helpText = [
			"Prints a list of all or selected local packages. This includes all cached "~
			"packages (user or system wide), all packages in the package search paths "~
			"(\"dub add-path\") and all manually registered packages (\"dub add-local\"). "~
			"If a package (and optionally a version spec) is specified, only matching packages are shown."
		];
	}
	override void prepare(scope CommandArgs args) {}
	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		enforceUsage(free_args.length <= 1, "Expecting zero or one extra arguments.");
		const pinfo = free_args.length ? UserPackageDesc.fromString(free_args[0]) : UserPackageDesc("",VersionRange.Any);
		const pname = pinfo.name;
		enforceUsage(app_args.length == 0, "The list command supports no application arguments.");
		logInfoNoTag("Packages present in the system and known to dub:");
		foreach (p; dub.packageManager.getPackageIterator()) {
			if ((pname == "" || pname == p.name) && pinfo.range.matches(p.version_))
				logInfoNoTag("  %s %s: %s", p.name.color(Mode.bold), p.version_, p.path.toNativeString());
		}
		logInfo("");
		return 0;
	}
}

class SearchCommand : Command {
	this() @safe pure nothrow
	{
		this.name = "search";
		this.argumentsPattern = "<package-name>";
		this.description = "Search for available packages.";
		this.helpText = [
			"Search all specified providers for matching packages."
		];
	}
	override void prepare(scope CommandArgs args) {}
	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		enforce(free_args.length == 1, "Expected one argument.");
		auto res = dub.searchPackages(free_args[0]);
		if (res.empty)
		{
			logError("No matches found.");
			return 2;
		}
		auto justify = res
			.map!((descNmatches) => descNmatches[1])
			.joiner
			.map!(m => m.name.length + m.version_.length)
			.reduce!max + " ()".length;
		justify += (~justify & 3) + 1; // round to next multiple of 4
		int colorDifference = cast(int)"a".color(Mode.bold).length - 1;
		justify += colorDifference;
		foreach (desc, matches; res)
		{
			logInfoNoTag("==== %s ====", desc);
			foreach (m; matches)
				logInfoNoTag("  %s%s", leftJustify(m.name.color(Mode.bold)
					~ " (" ~ m.version_ ~ ")", justify), m.description);
		}
		return 0;
	}
}


/******************************************************************************/
/* OVERRIDES                                                                  */
/******************************************************************************/

class AddOverrideCommand : Command {
	private {
		bool m_system = false;
	}

	static immutable string DeprecationMessage =
		"This command is deprecated. Use path based dependency, custom cache path, " ~
		"or edit `dub.selections.json` to achieve the same results.";


	this() @safe pure nothrow
	{
		this.name = "add-override";
		this.argumentsPattern = "<package> <version-spec> <target-path/target-version>";
		this.description = "Adds a new package override.";

		this.hidden = true;
		this.helpText = [ DeprecationMessage ];
	}

	override void prepare(scope CommandArgs args)
	{
		args.getopt("system", &m_system, [
			"Register system-wide instead of user-wide"
		]);
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		logWarn(DeprecationMessage);
		enforceUsage(app_args.length == 0, "Unexpected application arguments.");
		enforceUsage(free_args.length == 3, "Expected three arguments, not "~free_args.length.to!string);
		auto scope_ = m_system ? PlacementLocation.system : PlacementLocation.user;
		auto pack = free_args[0];
		auto source = VersionRange.fromString(free_args[1]);
		if (existsFile(NativePath(free_args[2]))) {
			auto target = NativePath(free_args[2]);
			if (!target.absolute) target = getWorkingDirectory() ~ target;
			dub.packageManager.addOverride_(scope_, pack, source, target);
			logInfo("Added override %s %s => %s", pack, source, target);
		} else {
			auto target = Version(free_args[2]);
			dub.packageManager.addOverride_(scope_, pack, source, target);
			logInfo("Added override %s %s => %s", pack, source, target);
		}
		return 0;
	}
}

class RemoveOverrideCommand : Command {
	private {
		bool m_system = false;
	}

	this() @safe pure nothrow
	{
		this.name = "remove-override";
		this.argumentsPattern = "<package> <version-spec>";
		this.description = "Removes an existing package override.";

		this.hidden = true;
		this.helpText = [ AddOverrideCommand.DeprecationMessage ];
	}

	override void prepare(scope CommandArgs args)
	{
		args.getopt("system", &m_system, [
			"Register system-wide instead of user-wide"
		]);
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		logWarn(AddOverrideCommand.DeprecationMessage);
		enforceUsage(app_args.length == 0, "Unexpected application arguments.");
		enforceUsage(free_args.length == 2, "Expected two arguments, not "~free_args.length.to!string);
		auto scope_ = m_system ? PlacementLocation.system : PlacementLocation.user;
		auto source = VersionRange.fromString(free_args[1]);
		dub.packageManager.removeOverride_(scope_, free_args[0], source);
		return 0;
	}
}

class ListOverridesCommand : Command {
	this() @safe pure nothrow
	{
		this.name = "list-overrides";
		this.argumentsPattern = "";
		this.description = "Prints a list of all local package overrides";

		this.hidden = true;
		this.helpText = [ AddOverrideCommand.DeprecationMessage ];
	}
	override void prepare(scope CommandArgs args) {}
	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		logWarn(AddOverrideCommand.DeprecationMessage);

		void printList(in PackageOverride_[] overrides, string caption)
		{
			if (overrides.length == 0) return;
			logInfoNoTag("# %s", caption);
			foreach (ovr; overrides)
				ovr.target.match!(
					t => logInfoNoTag("%s %s => %s", ovr.package_.color(Mode.bold), ovr.source, t));
		}
		printList(dub.packageManager.getOverrides_(PlacementLocation.user), "User wide overrides");
		printList(dub.packageManager.getOverrides_(PlacementLocation.system), "System wide overrides");
		return 0;
	}
}

/******************************************************************************/
/* Cache cleanup                                                              */
/******************************************************************************/

class CleanCachesCommand : Command {
	this() @safe pure nothrow
	{
		this.name = "clean-caches";
		this.argumentsPattern = "";
		this.description = "Removes cached metadata";
		this.helpText = [
			"This command removes any cached metadata like the list of available packages and their latest version."
		];
	}

	override void prepare(scope CommandArgs args) {}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		return 0;
	}
}

/******************************************************************************/
/* DUSTMITE                                                                   */
/******************************************************************************/

class DustmiteCommand : PackageBuildCommand {
	private {
		int m_compilerStatusCode = int.min;
		int m_linkerStatusCode = int.min;
		int m_programStatusCode = int.min;
		string m_compilerRegex;
		string m_linkerRegex;
		string m_programRegex;
		string m_testPackage;
		bool m_noRedirect;
		string m_strategy;
		uint m_jobCount;		// zero means not specified
		bool m_trace;
	}

	this() @safe pure nothrow
	{
		this.name = "dustmite";
		this.argumentsPattern = "<destination-path>";
		this.acceptsAppArgs = true;
		this.description = "Create reduced test cases for build errors";
		this.helpText = [
			"This command uses the Dustmite utility to isolate the cause of build errors in a DUB project.",
			"",
			"It will create a copy of all involved packages and run dustmite on this copy, leaving a reduced test case.",
			"",
			"Determining the desired error condition is done by checking the compiler/linker status code, as well as their output (stdout and stderr combined). If --program-status or --program-regex is given and the generated binary is an executable, it will be executed and its output will also be incorporated into the final decision."
		];
	}

	override void prepare(scope CommandArgs args)
	{
		args.getopt("compiler-status", &m_compilerStatusCode, ["The expected status code of the compiler run"]);
		args.getopt("compiler-regex", &m_compilerRegex, ["A regular expression used to match against the compiler output"]);
		args.getopt("linker-status", &m_linkerStatusCode, ["The expected status code of the linker run"]);
		args.getopt("linker-regex", &m_linkerRegex, ["A regular expression used to match against the linker output"]);
		args.getopt("program-status", &m_programStatusCode, ["The expected status code of the built executable"]);
		args.getopt("program-regex", &m_programRegex, ["A regular expression used to match against the program output"]);
		args.getopt("test-package", &m_testPackage, ["Perform a test run - usually only used internally"]);
		args.getopt("combined", &this.baseSettings.combined, ["Builds multiple packages with one compiler run"]);
		args.getopt("no-redirect", &m_noRedirect, ["Don't redirect stdout/stderr streams of the test command"]);
		args.getopt("strategy", &m_strategy, ["Set strategy (careful/lookback/pingpong/indepth/inbreadth)"]);
		args.getopt("j", &m_jobCount, ["Set number of look-ahead processes"]);
		args.getopt("trace", &m_trace, ["Save all attempted reductions to DIR.trace"]);
		super.prepare(args);

		// speed up loading when in test mode
		if (m_testPackage.length) {
			m_nodeps = true;
		}
	}

	/// Returns: A minimally-initialized dub instance in test mode
	override Dub prepareDub(CommonOptions options)
	{
		if (!m_testPackage.length)
			return super.prepareDub(options);
		return new Dub(NativePath(options.root_path), getWorkingDirectory());
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		import std.format : formattedWrite;

		if (m_testPackage.length) {
			setupPackage(dub, UserPackageDesc(m_testPackage));
			m_defaultConfig = dub.project.getDefaultConfiguration(this.baseSettings.platform);

			GeneratorSettings gensettings = this.baseSettings;
			if (!gensettings.config.length)
				gensettings.config = m_defaultConfig;
			gensettings.run = m_programStatusCode != int.min || m_programRegex.length;
			gensettings.runArgs = app_args;
			gensettings.force = true;
			gensettings.compileCallback = check(m_compilerStatusCode, m_compilerRegex);
			gensettings.linkCallback = check(m_linkerStatusCode, m_linkerRegex);
			gensettings.runCallback = check(m_programStatusCode, m_programRegex);
			try dub.generateProject("build", gensettings);
			catch (DustmiteMismatchException) {
				logInfoNoTag("Dustmite test doesn't match.");
				return 3;
			}
			catch (DustmiteMatchException) {
				logInfoNoTag("Dustmite test matches.");
				return 0;
			}
		} else {
			enforceUsage(free_args.length == 1, "Expected destination path.");
			auto path = NativePath(free_args[0]);
			path.normalize();
			enforceUsage(!path.empty, "Destination path must not be empty.");
			if (!path.absolute) path = getWorkingDirectory() ~ path;
			enforceUsage(!path.startsWith(dub.rootPath), "Destination path must not be a sub directory of the tested package!");

			setupPackage(dub, UserPackageDesc.init);
			auto prj = dub.project;
			if (this.baseSettings.config.empty)
				this.baseSettings.config = prj.getDefaultConfiguration(this.baseSettings.platform);

			void copyFolderRec(NativePath folder, NativePath dstfolder)
			{
				ensureDirectory(dstfolder);
				foreach (de; iterateDirectory(folder)) {
					if (de.name.startsWith(".")) continue;
					if (de.isDirectory) {
						copyFolderRec(folder ~ de.name, dstfolder ~ de.name);
					} else {
						if (de.name.endsWith(".o") || de.name.endsWith(".obj")) continue;
						if (de.name.endsWith(".exe")) continue;
						try copyFile(folder ~ de.name, dstfolder ~ de.name);
						catch (Exception e) {
							logWarn("Failed to copy file %s: %s", (folder ~ de.name).toNativeString(), e.msg);
						}
					}
				}
			}

			static void fixPathDependency(in PackageName name, ref Dependency dep) {
				dep.visit!(
					(NativePath path) {
						dep = Dependency(NativePath("../") ~ name.main.toString());
					},
					(any) { /* Nothing to do */ },
				);
			}

			void fixPathDependencies(ref PackageRecipe recipe, NativePath base_path)
			{
				foreach (name, ref dep; recipe.buildSettings.dependencies)
					fixPathDependency(PackageName(name), dep);

				foreach (ref cfg; recipe.configurations)
					foreach (name, ref dep; cfg.buildSettings.dependencies)
						fixPathDependency(PackageName(name), dep);

				foreach (ref subp; recipe.subPackages)
					if (subp.path.length) {
						auto sub_path = base_path ~ NativePath(subp.path);
						auto pack = dub.packageManager.getOrLoadPackage(sub_path);
						fixPathDependencies(pack.recipe, sub_path);
						pack.storeInfo(sub_path);
					} else fixPathDependencies(subp.recipe, base_path);
			}

			bool[string] visited;
			foreach (pack_; prj.getTopologicalPackageList()) {
				auto pack = pack_.basePackage;
				if (pack.name in visited) continue;
				visited[pack.name] = true;
				auto dst_path = path ~ pack.name;
				logInfo("Prepare", Color.light_blue, "Copy package %s to destination folder...", pack.name.color(Mode.bold));
				copyFolderRec(pack.path, dst_path);

				// adjust all path based dependencies
				fixPathDependencies(pack.recipe, dst_path);

				// overwrite package description file with additional version information
				pack.storeInfo(dst_path);
			}

			logInfo("Starting", Color.light_green, "Executing dustmite...");
			auto testcmd = appender!string();
			testcmd.formattedWrite("%s dustmite --test-package=%s --build=%s --config=%s",
				thisExePath, prj.name, this.baseSettings.buildType, this.baseSettings.config);

			if (m_compilerName.length) testcmd.formattedWrite(" \"--compiler=%s\"", m_compilerName);
			if (m_arch.length) testcmd.formattedWrite(" --arch=%s", m_arch);
			if (m_compilerStatusCode != int.min) testcmd.formattedWrite(" --compiler-status=%s", m_compilerStatusCode);
			if (m_compilerRegex.length) testcmd.formattedWrite(" \"--compiler-regex=%s\"", m_compilerRegex);
			if (m_linkerStatusCode != int.min) testcmd.formattedWrite(" --linker-status=%s", m_linkerStatusCode);
			if (m_linkerRegex.length) testcmd.formattedWrite(" \"--linker-regex=%s\"", m_linkerRegex);
			if (m_programStatusCode != int.min) testcmd.formattedWrite(" --program-status=%s", m_programStatusCode);
			if (m_programRegex.length) testcmd.formattedWrite(" \"--program-regex=%s\"", m_programRegex);
			if (this.baseSettings.combined) testcmd ~= " --combined";

			// --vquiet swallows dustmite's output ...
			if (!m_noRedirect) testcmd ~= " --vquiet";

			// TODO: pass *all* original parameters
			logDiagnostic("Running dustmite: %s", testcmd);

			string[] extraArgs;
			if (m_noRedirect) extraArgs ~= "--no-redirect";
			if (m_strategy.length) extraArgs ~= "--strategy=" ~ m_strategy;
			if (m_jobCount) extraArgs ~= "-j" ~ m_jobCount.to!string;
			if (m_trace) extraArgs ~= "--trace";

			const cmd = "dustmite" ~ extraArgs ~ [path.toNativeString(), testcmd.data];
			auto dmpid = spawnProcess(cmd);
			return dmpid.wait();
		}
		return 0;
	}

	void delegate(int, string) check(int code_match, string regex_match)
	{
		return (code, output) {
			import std.encoding;
			import std.regex;

			logInfo("%s", output);

			if (code_match != int.min && code != code_match) {
				logInfo("Exit code %s doesn't match expected value %s", code, code_match);
				throw new DustmiteMismatchException;
			}

			if (regex_match.length > 0 && !match(output.sanitize, regex_match)) {
				logInfo("Output doesn't match regex:");
				logInfo("%s", output);
				throw new DustmiteMismatchException;
			}

			if (code != 0 && code_match != int.min || regex_match.length > 0) {
				logInfo("Tool failed, but matched either exit code or output - counting as match.");
				throw new DustmiteMatchException;
			}
		};
	}

	static class DustmiteMismatchException : Exception {
		this(string message = "", string file = __FILE__, int line = __LINE__, Throwable next = null)
		{
			super(message, file, line, next);
		}
	}

	static class DustmiteMatchException : Exception {
		this(string message = "", string file = __FILE__, int line = __LINE__, Throwable next = null)
		{
			super(message, file, line, next);
		}
	}
}


/******************************************************************************/
/* CONVERT command                                                               */
/******************************************************************************/

class ConvertCommand : Command {
	private {
		string m_format;
		bool m_stdout;
	}

	this() @safe pure nothrow
	{
		this.name = "convert";
		this.argumentsPattern = "";
		this.description = "Converts the file format of the package recipe.";
		this.helpText = [
			"This command will convert between JSON and SDLang formatted package recipe files.",
			"",
			"Warning: Beware that any formatting and comments within the package recipe will get lost in the conversion process."
		];
	}

	override void prepare(scope CommandArgs args)
	{
		args.getopt("f|format", &m_format, ["Specifies the target package recipe format. Possible values:", "  json, sdl"]);
		args.getopt("s|stdout", &m_stdout, ["Outputs the converted package recipe to stdout instead of writing to disk."]);
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		enforceUsage(app_args.length == 0, "Unexpected application arguments.");
		enforceUsage(free_args.length == 0, "Unexpected arguments: "~free_args.join(" "));
		enforceUsage(m_format.length > 0, "Missing target format file extension (--format=...).");
		if (!loadCwdPackage(dub, true)) return 2;
		dub.convertRecipe(m_format, m_stdout);
		return 0;
	}
}


/******************************************************************************/
/* HELP                                                                       */
/******************************************************************************/

private {
	enum shortArgColumn = 2;
	enum longArgColumn = 6;
	enum descColumn = 24;
	enum lineWidth = 80 - 1;
}

private void showHelp(in CommandGroup[] commands, CommandArgs common_args)
{
	writeln(
`USAGE: dub [--version] [<command>] [<options...>] [-- [<application arguments...>]]

Manages the DUB project in the current directory. If the command is omitted,
DUB will default to "run". When running an application, "--" can be used to
separate DUB options from options passed to the application.

Run "dub <command> --help" to get help for a specific command.

You can use the "http_proxy" environment variable to configure a proxy server
to be used for fetching packages.


Available commands
==================`);

	foreach (grp; commands) {
		writeln();
		writeWS(shortArgColumn);
		writeln(grp.caption);
		writeWS(shortArgColumn);
		writerep!'-'(grp.caption.length);
		writeln();
		foreach (cmd; grp.commands) {
			if (cmd.hidden) continue;
			writeWS(shortArgColumn);
			writef("%s %s", cmd.name, cmd.argumentsPattern);
			auto chars_output = cmd.name.length + cmd.argumentsPattern.length + shortArgColumn + 1;
			if (chars_output < descColumn) {
				writeWS(descColumn - chars_output);
			} else {
				writeln();
				writeWS(descColumn);
			}
			writeWrapped(cmd.description, descColumn, descColumn);
		}
	}
	writeln();
	writeln();
	writeln(`Common options`);
	writeln(`==============`);
	writeln();
	writeOptions(common_args);
	writeln();
	showVersion();
}

private void showVersion()
{
	writefln("DUB version %s, built on %s", getDUBVersion(), __DATE__);
}

private void showCommandHelp(Command cmd, CommandArgs args, CommandArgs common_args)
{
	writefln(`USAGE: dub %s %s [<options...>]%s`, cmd.name, cmd.argumentsPattern, cmd.acceptsAppArgs ? " [-- <application arguments...>]": null);
	writeln();
	foreach (ln; cmd.helpText)
		ln.writeWrapped();

	if (args.recognizedArgs.length) {
		writeln();
		writeln();
		writeln("Command specific options");
		writeln("========================");
		writeln();
		writeOptions(args);
	}

	writeln();
	writeln();
	writeln("Common options");
	writeln("==============");
	writeln();
	writeOptions(common_args);
	writeln();
	writefln("DUB version %s, built on %s", getDUBVersion(), __DATE__);
}

private void writeOptions(CommandArgs args)
{
	foreach (arg; args.recognizedArgs) {
		if (arg.hidden) continue;
		auto names = arg.names.split("|");
		assert(names.length == 1 || names.length == 2);
		string sarg = names[0].length == 1 ? names[0] : null;
		string larg = names[0].length > 1 ? names[0] : names.length > 1 ? names[1] : null;
		if (sarg !is null) {
			writeWS(shortArgColumn);
			writef("-%s", sarg);
			writeWS(longArgColumn - shortArgColumn - 2);
		} else writeWS(longArgColumn);
		size_t col = longArgColumn;
		if (larg !is null) {
			arg.defaultValue.match!(
				(bool b) {
					writef("--%s", larg);
					col += larg.length + 2;
				},
				(_) {
					writef("--%s=VALUE", larg);
					col += larg.length + 8;
				}
			);
		}
		if (col < descColumn) {
			writeWS(descColumn - col);
		} else {
			writeln();
			writeWS(descColumn);
		}
		foreach (i, ln; arg.helpText) {
			if (i > 0) writeWS(descColumn);
			ln.writeWrapped(descColumn, descColumn);
		}
	}
}

private void writeWrapped(string string, size_t indent = 0, size_t first_line_pos = 0)
{
	// handle pre-indented strings and bullet lists
	size_t first_line_indent = 0;
	while (string.startsWith(" ")) {
		string = string[1 .. $];
		indent++;
		first_line_indent++;
	}
	if (string.startsWith("- ")) indent += 2;

	auto wrapped = string.wrap(lineWidth, getRepString!' '(first_line_pos+first_line_indent), getRepString!' '(indent));
	wrapped = wrapped[first_line_pos .. $];
	foreach (ln; wrapped.splitLines())
		writeln(ln);
}

private void writeWS(size_t num) { writerep!' '(num); }
private void writerep(char ch)(size_t num) { write(getRepString!ch(num)); }

private string getRepString(char ch)(size_t len)
{
	static string buf;
	if (len > buf.length) buf ~= [ch].replicate(len-buf.length);
	return buf[0 .. len];
}

/***
*/


private void enforceUsage(bool cond, string text)
{
	if (!cond) throw new UsageException(text);
}

private class UsageException : Exception {
	this(string message, string file = __FILE__, int line = __LINE__, Throwable next = null)
	{
		super(message, file, line, next);
	}
}

private bool addDependency(Dub dub, ref PackageRecipe recipe, string depspec)
{
	Dependency dep;
	const parts = UserPackageDesc.fromString(depspec);
	const depname = PackageName(parts.name);
	if (parts.range == VersionRange.Any)
	{
		try {
			const ver = dub.getLatestVersion(depname);
			dep = ver.isBranch ? Dependency(ver) : Dependency("~>" ~ ver.toString());
		} catch (Exception e) {
			logError("Could not find package '%s'.", depname);
			logDebug("Full error: %s", e.toString().sanitize);
			return false;
		}
	}
	else
		dep = Dependency(parts.range);
	recipe.buildSettings.dependencies[depname.toString()] = dep;
	logInfo("Adding dependency %s %s", depname, dep.toString());
	return true;
}

/**
 * A user-provided package description
 *
 * User provided package description currently only covers packages
 * referenced by their name with an associated version.
 * Hence there is an implicit assumption that they are in the registry.
 * Future improvements could support `Dependency` instead of `VersionRange`.
 */
private struct UserPackageDesc
{
	string name;
	VersionRange range = VersionRange.Any;

	/// Provides a string representation for the user
	public string toString() const
	{
		if (this.range.matchesAny())
			return this.name;
		return format("%s@%s", this.name, range);
	}

	/**
	 * Breaks down a user-provided string into its name and version range
	 *
	 * User-provided strings (via the command line) are either in the form
	 * `<package>=<version-specifier>` or `<package>@<version-specifier>`.
	 * As it is more explicit, we recommend the latter (the `@` version
	 * is not used by names or `VersionRange`, but `=` is).
	 *
	 * If no version range is provided, the returned struct has its `range`
	 * property set to `VersionRange.Any` as this is the most usual usage
	 * in the command line. Some cakkers may want to distinguish between
	 * user-provided version and implicit version, but this is discouraged.
	 *
	 * Params:
	 *   str = User-provided string
	 *
	 * Returns:
	 *   A populated struct.
	 */
	static UserPackageDesc fromString(string packageName)
	{
		// split <package>@<version-specifier>
		auto parts = packageName.findSplit("@");
		if (parts[1].empty) {
			// split <package>=<version-specifier>
			parts = packageName.findSplit("=");
		}

		UserPackageDesc p;
		p.name = parts[0];
		p.range = !parts[1].empty
			? VersionRange.fromString(parts[2])
			: VersionRange.Any;
		return p;
	}
}

unittest
{
	// https://github.com/dlang/dub/issues/1681
	assert(UserPackageDesc.fromString("") == UserPackageDesc("", VersionRange.Any));

	assert(UserPackageDesc.fromString("foo") == UserPackageDesc("foo", VersionRange.Any));
	assert(UserPackageDesc.fromString("foo=1.0.1") == UserPackageDesc("foo", VersionRange.fromString("1.0.1")));
	assert(UserPackageDesc.fromString("foo@1.0.1") == UserPackageDesc("foo", VersionRange.fromString("1.0.1")));
	assert(UserPackageDesc.fromString("foo@==1.0.1") == UserPackageDesc("foo", VersionRange.fromString("==1.0.1")));
	assert(UserPackageDesc.fromString("foo@>=1.0.1") == UserPackageDesc("foo", VersionRange.fromString(">=1.0.1")));
	assert(UserPackageDesc.fromString("foo@~>1.0.1") == UserPackageDesc("foo", VersionRange.fromString("~>1.0.1")));
	assert(UserPackageDesc.fromString("foo@<1.0.1") == UserPackageDesc("foo", VersionRange.fromString("<1.0.1")));
}

private ulong canFindVersionSplitter(string packageName)
{
	// see UserPackageDesc.fromString
	return packageName.canFind("@", "=");
}

unittest
{
	assert(!canFindVersionSplitter("foo"));
	assert(canFindVersionSplitter("foo=1.0.1"));
	assert(canFindVersionSplitter("foo@1.0.1"));
	assert(canFindVersionSplitter("foo@==1.0.1"));
	assert(canFindVersionSplitter("foo@>=1.0.1"));
	assert(canFindVersionSplitter("foo@~>1.0.1"));
	assert(canFindVersionSplitter("foo@<1.0.1"));
}
