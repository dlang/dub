/**
	Defines the behavior of the DUB command line client.

	Copyright: © 2012-2013 Matthias Dondorff, Copyright © 2012-2014 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff, Sönke Ludwig
*/
module dub.commandline;

import dub.compilers.compiler;
import dub.dependency;
import dub.dub;
import dub.generators.generator;
import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.data.json;
import dub.internal.vibecompat.inet.url;
import dub.package_;
import dub.packagemanager;
import dub.packagesupplier;
import dub.platform : determineCompiler;
import dub.project;
import dub.internal.utils : getDUBVersion, getClosestMatch;

import std.algorithm;
import std.array;
import std.conv;
import std.encoding;
import std.exception;
import std.file;
import std.getopt;
import std.process;
import std.stdio;
import std.string;
import std.typecons : Tuple, tuple;
import std.variant;


int runDubCommandLine(string[] args)
{
	logDiagnostic("DUB version %s", getDUBVersion());

	version(Windows){
		// rdmd uses $TEMP to compute a temporary path. since cygwin substitutes backslashes
		// with slashes, this causes OPTLINK to fail (it thinks path segments are options)
		// we substitute the other way around here to fix this.
		environment["TEMP"] = environment["TEMP"].replace("/", "\\");
	}

	// split application arguments from DUB arguments
	string[] app_args;
	auto app_args_idx = args.countUntil("--");
	if (app_args_idx >= 0) {
		app_args = args[app_args_idx+1 .. $];
		args = args[0 .. app_args_idx];
	}
	args = args[1 .. $]; // strip the application name

	// handle direct dub options
	if (args.length) switch (args[0])
	{
	case "--version":
		showVersion();
		return 0;

	default:
		break;
	}

	// parse general options
	bool verbose, vverbose, quiet, vquiet;
	bool help, annotate, bare;
	LogLevel loglevel = LogLevel.info;
	string[] registry_urls;
	string root_path = getcwd();

	auto common_args = new CommandArgs(args);
	try {
		common_args.getopt("h|help", &help, ["Display general or command specific help"]);
		common_args.getopt("root", &root_path, ["Path to operate in instead of the current working dir"]);
		common_args.getopt("registry", &registry_urls, ["Search the given DUB registry URL first when resolving dependencies. Can be specified multiple times."]);
		common_args.getopt("annotate", &annotate, ["Do not perform any action, just print what would be done"]);
		common_args.getopt("bare", &bare, ["Read only packages contained in the current directory"]);
		common_args.getopt("v|verbose", &verbose, ["Print diagnostic output"]);
		common_args.getopt("vverbose", &vverbose, ["Print debug output"]);
		common_args.getopt("q|quiet", &quiet, ["Only print warnings and errors"]);
		common_args.getopt("vquiet", &vquiet, ["Print no messages"]);
		common_args.getopt("cache", &defaultPlacementLocation, ["Puts any fetched packages in the specified location [local|system|user]."]);

		if( vverbose ) loglevel = LogLevel.debug_;
		else if( verbose ) loglevel = LogLevel.diagnostic;
		else if( vquiet ) loglevel = LogLevel.none;
		else if( quiet ) loglevel = LogLevel.warn;
		setLogLevel(loglevel);
	} catch (Throwable e) {
		logError("Error processing arguments: %s", e.msg);
		logDiagnostic("Full exception: %s", e.toString().sanitize);
		logInfo("Run 'dub help' for usage information.");
		return 1;
	}

	// create the list of all supported commands

	CommandGroup[] commands = [
		CommandGroup("Package creation",
			new InitCommand
		),
		CommandGroup("Build, test and run",
			new RunCommand,
			new BuildCommand,
			new TestCommand,
			new GenerateCommand,
			new DescribeCommand,
			new CleanCommand,
			new DustmiteCommand
		),
		CommandGroup("Package management",
			new FetchCommand,
			new InstallCommand,
			new RemoveCommand,
			new UninstallCommand,
			new UpgradeCommand,
			new AddPathCommand,
			new RemovePathCommand,
			new AddLocalCommand,
			new RemoveLocalCommand,
			new ListCommand,
			new ListInstalledCommand,
			new AddOverrideCommand,
			new RemoveOverrideCommand,
			new ListOverridesCommand,
			new CleanCachesCommand,
		)
	];

	// extract the command
	string cmdname;
	args = common_args.extractRemainingArgs();
	if (args.length >= 1 && !args[0].startsWith("-")) {
		cmdname = args[0];
		args = args[1 .. $];
	} else {
		if (help) {
			showHelp(commands, common_args);
			return 0;
		}
		cmdname = "run";
	}
	auto command_args = new CommandArgs(args);

	if (cmdname == "help") {
		showHelp(commands, common_args);
		return 0;
	}

	// find the selected command
	Command cmd;
	foreach (grp; commands)
		foreach (c; grp.commands)
			if (c.name == cmdname) {
				cmd = c;
				break;
			}

	if (!cmd) {
		logError("Unknown command: %s", cmdname);
		writeln();
		showHelp(commands, common_args);
		return 1;
	}

	// process command line options for the selected command
	try {
		cmd.prepare(command_args);
		enforceUsage(cmd.acceptsAppArgs || app_args.length == 0, cmd.name ~ " doesn't accept application arguments.");
	} catch (Throwable e) {
		logError("Error processing arguments: %s", e.msg);
		logDiagnostic("Full exception: %s", e.toString().sanitize);
		logInfo("Run 'dub help' for usage information.");
		return 1;
	}

	if (help) {
		showCommandHelp(cmd, command_args, common_args);
		return 0;
	}

	auto remaining_args = command_args.extractRemainingArgs();
	if (remaining_args.any!(a => a.startsWith("-"))) {
		logError("Unknown command line flags: %s", remaining_args.filter!(a => a.startsWith("-")).array.join(" "));
		logError(`Type "dub %s -h" to get a list of all supported flags.`, cmdname);
		return 1;
	}

	Dub dub;

	// initialize the root package
	if (!cmd.skipDubInitialization) {
		if (bare) {
			dub = new Dub(Path(getcwd()));
		} else {
			// initialize DUB
			auto package_suppliers = registry_urls.map!(url => cast(PackageSupplier)new RegistryPackageSupplier(URL(url))).array;
			dub = new Dub(package_suppliers, root_path);
			dub.dryRun = annotate;

			// make the CWD package available so that for example sub packages can reference their
			// parent package.
			try dub.packageManager.getOrLoadPackage(Path(root_path));
			catch (Exception e) { logDiagnostic("No package found in current working directory."); }
		}
	}

	// execute the command
	int rc;
	try {
		rc = cmd.execute(dub, remaining_args, app_args);
	}
	catch (UsageException e) {
		logError("%s", e.msg);
		logDebug("Full exception: %s", e.toString().sanitize);
		logInfo(`Run "dub %s -h" for more information about the "%s" command.`, cmdname, cmdname);
		return 1;
	}
	catch (Throwable e) {
		logError("Error executing command %s:", cmd.name);
		logError("%s", e.msg);
		logDebug("Full exception: %s", e.toString().sanitize);
		return 2;
	}

	if (!cmd.skipDubInitialization)
		dub.shutdown();
	return rc;
}

class CommandArgs {
	struct Arg {
		Variant defaultValue;
		Variant value;
		string names;
		string[] helpText;
	}
	private {
		string[] m_args;
		Arg[] m_recognizedArgs;
	}

	this(string[] args)
	{
		m_args = "dummy" ~ args;
	}

	@property const(Arg)[] recognizedArgs() { return m_recognizedArgs; }

	void getopt(T)(string names, T* var, string[] help_text = null)
	{
		foreach (ref arg; m_recognizedArgs)
			if (names == arg.names) {
				assert(help_text is null);
				*var = arg.value.get!T;
				return;
			}
		assert(help_text.length > 0);
		Arg arg;
		arg.defaultValue = *var;
		arg.names = names;
		arg.helpText = help_text;
		m_args.getopt(config.passThrough, names, var);
		arg.value = *var;
		m_recognizedArgs ~= arg;
	}

	void dropAllArgs()
	{
		m_args = null;
	}

	string[] extractRemainingArgs()
	{
		auto ret = m_args[1 .. $];
		m_args = null;
		return ret;
	}
}

class Command {
	string name;
	string argumentsPattern;
	string description;
	string[] helpText;
	bool acceptsAppArgs;
	bool hidden = false; // used for deprecated commands
	bool skipDubInitialization = false;

	abstract void prepare(scope CommandArgs args);
	abstract int execute(Dub dub, string[] free_args, string[] app_args);
}

struct CommandGroup {
	string caption;
	Command[] commands;

	this(string caption, Command[] commands...)
	{
		this.caption = caption;
		this.commands = commands.dup;
	}
}


/******************************************************************************/
/* INIT                                                                       */
/******************************************************************************/

class InitCommand : Command {
	private{
		string m_buildType = "minimal";
	}
	this()
	{
		this.name = "init";
		this.argumentsPattern = "[<directory> [<dependency>...]]";
		this.description = "Initializes an empty package skeleton";
		this.helpText = [
			"Initializes an empty package of the specified type in the given directory. By default, the current working dirctory is used."
		];
	}

	override void prepare(scope CommandArgs args)
	{
		args.getopt("t|type", &m_buildType, [
			"Set the type of project to generate. Available types:",
			"",
			"minimal - simple \"hello world\" project (default)",
			"vibe.d  - minimal HTTP server based on vibe.d",
			"deimos  - skeleton for C header bindings",
		]);
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		string dir;
		enforceUsage(app_args.empty, "Unexpected application arguments.");
		if (free_args.length)
		{
			dir = free_args[0];
			free_args = free_args[1 .. $];
		}
		//TODO: Remove this block in next version
		// Checks if argument uses current method of specifying project type.
		if (free_args.length)
		{
			if (["vibe.d", "deimos", "minimal"].canFind(free_args[0]))
			{
				m_buildType = free_args[0];
				free_args = free_args[1 .. $];
				logInfo("Deprecated use of init type. Use --type=[vibe.d | deimos | minimal] in future.");
			}
		}
		dub.createEmptyPackage(Path(dir), free_args, m_buildType);
		return 0;
	}
}


/******************************************************************************/
/* GENERATE / BUILD / RUN / TEST / DESCRIBE                                   */
/******************************************************************************/

abstract class PackageBuildCommand : Command {
	protected {
		string m_buildType;
		BuildMode m_buildMode;
		string m_buildConfig;
		string m_compilerName;
		string m_arch;
		string[] m_debugVersions;
		Compiler m_compiler;
		BuildPlatform m_buildPlatform;
		BuildSettings m_buildSettings;
		string m_defaultConfig;
		bool m_nodeps;
		bool m_forceRemove = false;
	}

	this()
	{
		m_compilerName = defaultCompiler();
	}

	override void prepare(scope CommandArgs args)
	{
		args.getopt("b|build", &m_buildType, [
			"Specifies the type of build to perform. Note that setting the DFLAGS environment variable will override the build type with custom flags.",
			"Possible names:",
			"  debug (default), plain, release, release-nobounds, unittest, profile, docs, ddox, cov, unittest-cov and custom types"
		]);
		args.getopt("c|config", &m_buildConfig, [
			"Builds the specified configuration. Configurations can be defined in dub.json"
		]);
		args.getopt("compiler", &m_compilerName, [
			"Specifies the compiler binary to use (can be a path).",
			"Arbitrary pre- and suffixes to the identifiers below are recognized (e.g. ldc2 or dmd-2.063) and matched to the proper compiler type:",
			"  "~["dmd", "gdc", "ldc", "gdmd", "ldmd"].join(", "),
			"Default value: "~m_compilerName,
		]);
		args.getopt("a|arch", &m_arch, [
			"Force a different architecture (e.g. x86 or x86_64)"
		]);
		args.getopt("d|debug", &m_debugVersions, [
			"Define the specified debug version identifier when building - can be used multiple times"
		]);
		args.getopt("nodeps", &m_nodeps, [
			"Do not check/update dependencies before building"
		]);
		args.getopt("force-remove", &m_forceRemove, [
			"Force deletion of fetched packages with untracked files when upgrading"
		]);
		args.getopt("build-mode", &m_buildMode, [
			"Specifies the way the compiler and linker are invoked. Valid values:",
			"  separate (default), allAtOnce, singleFile"
		]);
	}

	protected void setupPackage(Dub dub, string package_name)
	{
		m_compiler = getCompiler(m_compilerName);
		m_buildPlatform = m_compiler.determinePlatform(m_buildSettings, m_compilerName, m_arch);
		m_buildSettings.addDebugVersions(m_debugVersions);

		m_defaultConfig = null;
		enforce (loadSpecificPackage(dub, package_name), "Failed to load package.");

		if (m_buildConfig.length != 0 && !dub.configurations.canFind(m_buildConfig))
		{
			string msg = "Unknown build configuration: "~m_buildConfig;
			enum distance = 3;
			auto match = dub.configurations.getClosestMatch(m_buildConfig, distance);
			if (match !is null) msg ~= ". Did you mean '" ~ match ~ "'?";
			enforce(0, msg);
		}

		if (m_buildType.length == 0) {
			if (environment.get("DFLAGS") !is null) m_buildType = "$DFLAGS";
			else m_buildType = "debug";
		}

		if (!m_nodeps) {
			// TODO: only upgrade(select) if necessary, only upgrade(upgrade) every now and then

			// retrieve missing packages
			logDiagnostic("Checking for missing dependencies.");
			dub.upgrade(UpgradeOptions.select);
			// check for updates
			logDiagnostic("Checking for upgrades.");
			dub.upgrade(UpgradeOptions.upgrade|UpgradeOptions.printUpgradesOnly|UpgradeOptions.useCachedResult);
		}

		dub.project.validate();
	}

	private bool loadSpecificPackage(Dub dub, string package_name)
	{
		// load package in root_path to enable searching for sub packages
		if (loadCwdPackage(dub, package_name.length == 0)) {
			if (package_name.startsWith(":"))
				package_name = dub.projectName ~ package_name;
			if (!package_name.length) return true;
		}

		auto pack = dub.packageManager.getFirstPackage(package_name);
		enforce(pack, "Failed to find a package named '"~package_name~"'.");
		logInfo("Building package %s in %s", pack.name, pack.path.toNativeString());
		dub.rootPath = pack.path;
		dub.loadPackage(pack);
		return true;
	}

	private bool loadCwdPackage(Dub dub, bool warn_missing_package)
	{
		bool found = existsFile(dub.rootPath ~ "source/app.d");
		if (!found)
			foreach (f; packageInfoFiles)
				if (existsFile(dub.rootPath ~ f.filename)) {
					found = true;
					break;
				}

		if (!found) {
			if (warn_missing_package) {
				logInfo("");
				logInfo("Neither a package description file, nor source/app.d was found in");
				logInfo(dub.rootPath.toNativeString());
				logInfo("Please run DUB from the root directory of an existing package, or run");
				logInfo("\"dub init --help\" to get information on creating a new package.");
				logInfo("");
			}
			return false;
		}

		dub.loadPackageFromCwd();

		return true;
	}
}

class GenerateCommand : PackageBuildCommand {
	protected {
		string m_generator;
		bool m_rdmd = false;
		bool m_tempBuild = false;
		bool m_run = false;
		bool m_force = false;
		bool m_combined = false;
		bool m_parallel = false;
		bool m_printPlatform, m_printBuilds, m_printConfigs;
	}

	this()
	{
		this.name = "generate";
		this.argumentsPattern = "<generator> [<package>]";
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

		args.getopt("combined", &m_combined, [
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
		args.getopt("parallel", &m_parallel, [
			"Runs multiple compiler instances in parallel, if possible."
		]);
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		string package_name;
		if (!m_generator.length) {
			enforceUsage(free_args.length >= 1 && free_args.length <= 2, "Expected one or two arguments.");
			m_generator = free_args[0];
			if (free_args.length >= 2) package_name = free_args[1];
		} else {
			enforceUsage(free_args.length <= 1, "Expected one or zero arguments.");
			if (free_args.length >= 1) package_name = free_args[0];
		}

		setupPackage(dub, package_name);

		if (m_printBuilds) { // FIXME: use actual package data
			logInfo("Available build types:");
			foreach (tp; ["debug", "release", "unittest", "profile"])
				logInfo("  %s", tp);
			logInfo("");
		}

		m_defaultConfig = dub.project.getDefaultConfiguration(m_buildPlatform);
		if (m_printConfigs) {
			logInfo("Available configurations:");
			foreach (tp; dub.configurations)
				logInfo("  %s%s", tp, tp == m_defaultConfig ? " [default]" : null);
			logInfo("");
		}

		GeneratorSettings gensettings;
		gensettings.platform = m_buildPlatform;
		gensettings.config = m_buildConfig.length ? m_buildConfig : m_defaultConfig;
		gensettings.buildType = m_buildType;
		gensettings.buildMode = m_buildMode;
		gensettings.compiler = m_compiler;
		gensettings.buildSettings = m_buildSettings;
		gensettings.combined = m_combined;
		gensettings.run = m_run;
		gensettings.runArgs = app_args;
		gensettings.force = m_force;
		gensettings.rdmd = m_rdmd;
		gensettings.tempBuild = m_tempBuild;
		gensettings.parallelBuild = m_parallel;

		logDiagnostic("Generating using %s", m_generator);
		dub.generateProject(m_generator, gensettings);
		if (m_buildType == "ddox") dub.runDdox(gensettings.run);
		return 0;
	}
}

class BuildCommand : GenerateCommand {
	this()
	{
		this.name = "build";
		this.argumentsPattern = "[<package>]";
		this.description = "Builds a package (uses the main package in the current working directory by default)";
		this.helpText = [
			"Builds a package (uses the main package in the current working directory by default)"
		];
	}

	override void prepare(scope CommandArgs args)
	{
		args.getopt("rdmd", &m_rdmd, [
			"Use rdmd instead of directly invoking the compiler"
		]);

		args.getopt("f|force", &m_force, [
			"Forces a recompilation even if the target is up to date"
		]);
		super.prepare(args);
		m_generator = "build";
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		return super.execute(dub, free_args, app_args);
	}
}

class RunCommand : BuildCommand {
	this()
	{
		this.name = "run";
		this.argumentsPattern = "[<package>]";
		this.description = "Builds and runs a package (default command)";
		this.helpText = [
			"Builds and runs a package (uses the main package in the current working directory by default)"
		];
		this.acceptsAppArgs = true;
	}

	override void prepare(scope CommandArgs args)
	{
		args.getopt("temp-build", &m_tempBuild, [
			"Builds the project in the temp folder if possible."
		]);

		super.prepare(args);
		m_run = true;
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		return super.execute(dub, free_args, app_args);
	}
}

class TestCommand : PackageBuildCommand {
	private {
		string m_mainFile;
		bool m_combined = false;
		bool m_force = false;
	}

	this()
	{
		this.name = "test";
		this.argumentsPattern = "[<package>]";
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

		m_buildType = "unittest";
	}

	override void prepare(scope CommandArgs args)
	{
		args.getopt("main-file", &m_mainFile, [
			"Specifies a custom file containing the main() function to use for running the tests."
		]);
		args.getopt("combined", &m_combined, [
			"Tries to build the whole project in a single compiler run."
		]);
		args.getopt("f|force", &m_force, [
			"Forces a recompilation even if the target is up to date"
		]);
		bool coverage = false;
		args.getopt("coverage", &coverage, [
			"Enables code coverage statistics to be generated."
		]);
		if (coverage) m_buildType = "unittest-cov";

		super.prepare(args);
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		string package_name;
		enforceUsage(free_args.length <= 1, "Expected one or zero arguments.");
		if (free_args.length >= 1) package_name = free_args[0];

		setupPackage(dub, package_name);

		GeneratorSettings settings;
		settings.platform = m_buildPlatform;
		settings.compiler = getCompiler(m_buildPlatform.compilerBinary);
		settings.buildType = m_buildType;
		settings.buildMode = m_buildMode;
		settings.buildSettings = m_buildSettings;
		settings.combined = m_combined;
		settings.force = m_force;
		settings.run = true;
		settings.runArgs = app_args;

		dub.testProject(settings, m_buildConfig, Path(m_mainFile));
		return 0;
	}
}

class DescribeCommand : PackageBuildCommand {
	private {
		bool m_importPaths = false;
		bool m_stringImportPaths = false;
		string[] m_data;
	}

	this()
	{
		this.name = "describe";
		this.argumentsPattern = "[<package>]";
		this.description = "Prints a JSON description of the project and its dependencies";
		this.helpText = [
			"Prints a JSON build description for the root package an all of "
			"their dependencies in a format similar to a JSON package "
			"description file. This is useful mostly for IDEs.",
			"",
			"All usual options that are also used for build/run/generate apply.",
			"",
			"When --data=VALUE is supplied, specific build settings for a project ",
			"will be printed instead (by default, line-by-line).",
			"",
			"The --data=VALUE option can be specified multiple times to retrieve "
			"several pieces of information at once. The data will be output in "
			"the same order requested on the command line.",
			"",
			"The accepted values for --data=VALUE are:",
			"",
			"target-type, target-path, target-name, working-directory, "
			"main-source-file, dflags, lflags, libs, source-files, "
			"copy-files, versions, debug-versions, import-paths, "
			"string-import-paths, import-files, string-import-files, "
			"pre-generate-commands, post-generate-commands, "
			"pre-build-commands, post-build-commands, "
			"requirements, options",
		];
	}

	override void prepare(scope CommandArgs args)
	{
		super.prepare(args);

		args.getopt("import-paths", &m_importPaths, [
			"Shortcut for --data=import-paths"
		]);

		args.getopt("string-import-paths", &m_stringImportPaths, [
			"Shortcut for --data=string-import-paths"
		]);

		args.getopt("data", &m_data, [
			"Just list the values of a particular build setting, either for this "~
			"package alone or recursively including all dependencies. See "~
			"above for more details and accepted possibilities for VALUE."
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

		// disable all log output and use "writeln" to output the JSON description
		auto ll = getLogLevel();
		setLogLevel(LogLevel.none);
		scope (exit) setLogLevel(ll);

		string package_name;
		enforceUsage(free_args.length <= 1, "Expected one or zero arguments.");
		if (free_args.length >= 1) package_name = free_args[0];
		setupPackage(dub, package_name);

		m_defaultConfig = dub.project.getDefaultConfiguration(m_buildPlatform);

		auto config = m_buildConfig.length ? m_buildConfig : m_defaultConfig;

		if (m_importPaths) {
			dub.listImportPaths(m_buildPlatform, config, m_buildType);
		} else if (m_stringImportPaths) {
			dub.listStringImportPaths(m_buildPlatform, config, m_buildType);
		} else if (m_data) {
			dub.listProjectData(m_buildPlatform, config, m_buildType, m_data);
		} else {
			auto desc = dub.project.describe(m_buildPlatform, config, m_buildType);
			writeln(desc.serializeToPrettyJson());
		}

		return 0;
	}
}

class CleanCommand : Command {
	private {
		bool m_allPackages;
	}

	this()
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
			foreach (p; dub.packageManager.getPackageIterator())
				dub.cleanPackage(p.path);
		} else {
			dub.cleanPackage(dub.rootPath);
		}

		return 0;
	}
}


/******************************************************************************/
/* FETCH / REMOVE / UPGRADE                                                   */
/******************************************************************************/

class UpgradeCommand : Command {
	private {
		bool m_prerelease = false;
		bool m_forceRemove = false;
		bool m_missingOnly = false;
		bool m_verify = false;
	}

	this()
	{
		this.name = "upgrade";
		this.argumentsPattern = "[<package>]";
		this.description = "Forces an upgrade of all dependencies";
		this.helpText = [
			"Upgrades all dependencies of the package by querying the package registry(ies) for new versions.",
			"",
			"This will also update the versions stored in the selections file ("~SelectedVersions.defaultFile~") accordingly.",
			"",
			"If a package specified, (only) that package will be upgraded. Otherwise all direct and indirect dependencies of the current package will get upgraded."
		];
	}

	override void prepare(scope CommandArgs args)
	{
		args.getopt("prerelease", &m_prerelease, [
			"Uses the latest pre-release version, even if release versions are available"
		]);
		args.getopt("force-remove", &m_forceRemove, [
			"Force deletion of fetched packages with untracked files"
		]);
		args.getopt("verify", &m_verify, [
			"Updates the project and performs a build. If successfull, rewrites the selected versions file <to be implemeted>."
		]);
		args.getopt("missing-only", &m_missingOnly, [
			"Performs an upgrade only for dependencies that don't yet have a version selected. This is also done automatically before each build."
		]);
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		enforceUsage(free_args.length <= 1, "Unexpected arguments.");
		enforceUsage(app_args.length == 0, "Unexpected application arguments.");
		enforceUsage(!m_verify, "--verify is not yet implemented.");
		dub.loadPackageFromCwd();
		logInfo("Upgrading project in %s", dub.projectPath.toNativeString());
		auto options = UpgradeOptions.upgrade|UpgradeOptions.select;
		if (m_missingOnly) options &= ~UpgradeOptions.upgrade;
		if (m_prerelease) options |= UpgradeOptions.preRelease;
		if (m_forceRemove) options |= UpgradeOptions.forceRemove;
		enforceUsage(app_args.length == 0, "Upgrading a specific package is not yet implemented.");
		dub.upgrade(options);
		return 0;
	}
}

class FetchRemoveCommand : Command {
	protected {
		string m_version;
		bool m_forceRemove = false;
		bool m_system = false;
		bool m_local = false;
	}

	override void prepare(scope CommandArgs args)
	{
		args.getopt("version", &m_version, [
			"Use the specified version/branch instead of the latest available match",
			"The remove command also accepts \"*\" here as a wildcard to remove all versions of the package from the specified location"
		]);

		args.getopt("system", &m_system, ["Deprecated: Puts the package into the system wide package cache instead of the user local one."]);
		args.getopt("local", &m_local, ["Deprecated: Puts the package into a sub folder of the current working directory. Cannot be mixed with --system."]);
		args.getopt("force-remove", &m_forceRemove, [
			"Force deletion of fetched packages with untracked files"
		]);
	}

	abstract override int execute(Dub dub, string[] free_args, string[] app_args);
}

class FetchCommand : FetchRemoveCommand {
	this()
	{
		this.name = "fetch";
		this.argumentsPattern = "<name>";
		this.description = "Manually retrieves and caches a package";
		this.helpText = [
			"Note: Use the \"dependencies\" field in the package description file (e.g. dub.json) if you just want to use a certain package as a dependency, you don't have to explicitly fetch packages.",
			"",
			"Explicit retrieval/removal of packages is only needed when you want to put packages to a place where several applications can share these. If you just have an dependency to a package, just add it to your dub.json, dub will do the rest for you.",
			"",
			"Without specified options, placement/removal will default to a user wide shared location.",
			"",
			"Complete applications can be retrieved and run easily by e.g.",
			"$ dub fetch vibelog --local",
			"$ cd vibelog",
			"$ dub",
			"",
			"This will grab all needed dependencies and compile and run the application.",
			"",
			"Note: DUB does not do a system installation of packages. Packages are instead only registered within DUB's internal ecosystem. Generation of native system packages/installers may be added later as a separate feature."
		];
	}

	override void prepare(scope CommandArgs args)
	{
		super.prepare(args);
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		enforceUsage(!m_local || !m_system, "--local and --system are exclusive to each other.");
		enforceUsage(free_args.length == 1, "Expecting exactly one argument.");
		enforceUsage(app_args.length == 0, "Unexpected application arguments.");

		auto location = defaultPlacementLocation;
		if (m_local)
		{
			logWarn("--local is deprecated. Use --cache=local instead.");
			location = PlacementLocation.local;
		}
		else if (m_system)
		{
			logWarn("--system is deprecated. Use --cache=system instead.");
			location = PlacementLocation.system;
		}

		auto name = free_args[0];

		FetchOptions fetchOpts;
		fetchOpts |= FetchOptions.forceBranchUpgrade;
		fetchOpts |= m_forceRemove ? FetchOptions.forceRemove : FetchOptions.none;
		if (m_version.length) dub.fetch(name, Dependency(m_version), location, fetchOpts);
		else {
			try {
				dub.fetch(name, Dependency(">=0.0.0"), location, fetchOpts);
				logInfo(
					"Please note that you need to use `dub run <pkgname>` " ~
					"or add it to dependencies of your package to actually use/run it. " ~
					"dub does not do actual installation of packages outside of its own ecosystem.");
			}
			catch(Exception e){
				logInfo("Getting a release version failed: %s", e.msg);
				logInfo("Retry with ~master...");
				dub.fetch(name, Dependency("~master"), location, fetchOpts);
			}
		}
		return 0;
	}
}

class InstallCommand : FetchCommand {
	this() { this.name = "install"; hidden = true; }
	override void prepare(scope CommandArgs args) { super.prepare(args); }
	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		warnRenamed("install", "fetch");
		return super.execute(dub, free_args, app_args);
	}
}

class RemoveCommand : FetchRemoveCommand {
	this()
	{
		this.name = "remove";
		this.argumentsPattern = "<name>";
		this.description = "Removes a cached package";
		this.helpText = [
			"Removes a package that is cached on the local system."
		];
	}

	override void prepare(scope CommandArgs args)
	{
		super.prepare(args);
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		enforceUsage(free_args.length == 1, "Expecting exactly one argument.");
		enforceUsage(app_args.length == 0, "Unexpected application arguments.");

		auto package_id = free_args[0];
		auto location = defaultPlacementLocation;
		if (m_local)
		{
			logWarn("--local is deprecated. Use --cache=local instead.");
			location = PlacementLocation.local;
		}
		else if (m_system)
		{
			logWarn("--system is deprecated. Use --cache=system instead.");
			location = PlacementLocation.system;
		}

		dub.remove(package_id, m_version, location, m_forceRemove);
		return 0;
	}
}

class UninstallCommand : RemoveCommand {
	this() { this.name = "uninstall"; hidden = true; }
	override void prepare(scope CommandArgs args) { super.prepare(args); }
	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		warnRenamed("uninstall", "remove");
		return super.execute(dub, free_args, app_args);
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
			"Register system-wide instead of user-wide"
		]);
	}

	abstract override int execute(Dub dub, string[] free_args, string[] app_args);
}

class AddPathCommand : RegistrationCommand {
	this()
	{
		this.name = "add-path";
		this.argumentsPattern = "<path>";
		this.description = "Adds a default package search path";
		this.helpText = ["Adds a default package search path"];
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		enforceUsage(free_args.length == 1, "Missing search path.");
		dub.addSearchPath(free_args[0], m_system);
		return 0;
	}
}

class RemovePathCommand : RegistrationCommand {
	this()
	{
		this.name = "remove-path";
		this.argumentsPattern = "<path>";
		this.description = "Removes a package search path";
		this.helpText = ["Removes a package search path"];
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		enforceUsage(free_args.length == 1, "Expected one argument.");
		dub.removeSearchPath(free_args[0], m_system);
		return 0;
	}
}

class AddLocalCommand : RegistrationCommand {
	this()
	{
		this.name = "add-local";
		this.argumentsPattern = "<path> [<version>]";
		this.description = "Adds a local package directory (e.g. a git repository)";
		this.helpText = ["Adds a local package directory (e.g. a git repository)"];
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		enforceUsage(free_args.length == 1 || free_args.length == 2, "Expecting one or two arguments.");
		string ver = free_args.length == 2 ? free_args[1] : null;
		dub.addLocalPackage(free_args[0], ver, m_system);
		return 0;
	}
}

class RemoveLocalCommand : RegistrationCommand {
	this()
	{
		this.name = "remove-local";
		this.argumentsPattern = "<path>";
		this.description = "Removes a local package directory";
		this.helpText = ["Removes a local package directory"];
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		enforceUsage(free_args.length == 1, "Missing path to package.");
		dub.removeLocalPackage(free_args[0], m_system);
		return 0;
	}
}

class ListCommand : Command {
	this()
	{
		this.name = "list";
		this.argumentsPattern = "";
		this.description = "Prints a list of all local packages dub is aware of";
		this.helpText = [
			"Prints a list of all local packages. This includes all cached packages (user or system wide), all packages in the package search paths (\"dub add-path\") and all manually registered packages (\"dub add-local\")."
		];
	}
	override void prepare(scope CommandArgs args) {}
	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		logInfo("Packages present in the system and known to dub:");
		foreach (p; dub.packageManager.getPackageIterator())
			logInfo("  %s %s: %s", p.name, p.ver, p.path.toNativeString());
		logInfo("");
		return 0;
	}
}

class ListInstalledCommand : ListCommand {
	this() { this.name = "list-installed"; hidden = true; }
	override void prepare(scope CommandArgs args) { super.prepare(args); }
	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		warnRenamed("list-installed", "list");
		return super.execute(dub, free_args, app_args);
	}
}


/******************************************************************************/
/* OVERRIDES                                                                  */
/******************************************************************************/

class AddOverrideCommand : Command {
	private {
		bool m_system = false;
	}

	this()
	{
		this.name = "add-override";
		this.argumentsPattern = "<package> <version-spec> <target-path/target-version>";
		this.description = "Adds a new package override.";
		this.helpText = [
		];
	}

	override void prepare(scope CommandArgs args)
	{
		args.getopt("system", &m_system, [
			"Register system-wide instead of user-wide"
		]);
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		enforceUsage(app_args.length == 0, "Unexpected application arguments.");
		enforceUsage(free_args.length == 3, "Expected three arguments, not "~free_args.length.to!string);
		auto scope_ = m_system ? LocalPackageType.system : LocalPackageType.user;
		auto pack = free_args[0];
		auto ver = Dependency(free_args[1]);
		if (existsFile(Path(free_args[2]))) {
			auto target = Path(free_args[2]);
			dub.packageManager.addOverride(scope_, pack, ver, target);
			logInfo("Added override %s %s => %s", pack, ver, target);
		} else {
			auto target = Version(free_args[2]);
			dub.packageManager.addOverride(scope_, pack, ver, target);
			logInfo("Added override %s %s => %s", pack, ver, target);
		}
		return 0;
	}
}

class RemoveOverrideCommand : Command {
	private {
		bool m_system = false;
	}

	this()
	{
		this.name = "remove-override";
		this.argumentsPattern = "<package> <version-spec>";
		this.description = "Removes an existing package override.";
		this.helpText = [
		];
	}

	override void prepare(scope CommandArgs args)
	{
		args.getopt("system", &m_system, [
			"Register system-wide instead of user-wide"
		]);
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		enforceUsage(app_args.length == 0, "Unexpected application arguments.");
		enforceUsage(free_args.length == 2, "Expected two arguments, not "~free_args.length.to!string);
		auto scope_ = m_system ? LocalPackageType.system : LocalPackageType.user;
		dub.packageManager.removeOverride(scope_, free_args[0], Dependency(free_args[1]));
		return 0;
	}
}

class ListOverridesCommand : Command {
	this()
	{
		this.name = "list-overrides";
		this.argumentsPattern = "";
		this.description = "Prints a list of all local package overrides";
		this.helpText = [
			"Prints a list of all overriden packages added via \"dub add-override\"."
		];
	}
	override void prepare(scope CommandArgs args) {}
	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		void printList(in PackageOverride[] overrides, string caption)
		{
			if (overrides.length == 0) return;
			logInfo("# %s", caption);
			foreach (ovr; overrides) {
				if (!ovr.targetPath.empty) logInfo("%s %s => %s", ovr.package_, ovr.version_, ovr.targetPath);
				else logInfo("%s %s => %s", ovr.package_, ovr.version_, ovr.targetVersion);
			}
		}
		printList(dub.packageManager.getOverrides(LocalPackageType.user), "User wide overrides");
		printList(dub.packageManager.getOverrides(LocalPackageType.system), "System wide overrides");
		return 0;
	}
}

/******************************************************************************/
/* Cache cleanup                                                              */
/******************************************************************************/

class CleanCachesCommand : Command {
	this()
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
		dub.cleanCaches();
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
		bool m_combined;
	}

	this()
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
		args.getopt("linker-status", &m_linkerStatusCode, ["The expected status code of the liner run"]);
		args.getopt("linker-regex", &m_linkerRegex, ["A regular expression used to match against the linker output"]);
		args.getopt("program-status", &m_programStatusCode, ["The expected status code of the built executable"]);
		args.getopt("program-regex", &m_programRegex, ["A regular expression used to match against the program output"]);
		args.getopt("test-package", &m_testPackage, ["Perform a test run - usually only used internally"]);
		args.getopt("combined", &m_combined, ["Builds multiple packages with one compiler run"]);
		super.prepare(args);

		// speed up loading when in test mode
		if (m_testPackage.length) {
			skipDubInitialization = true;
			m_nodeps = true;
		}
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		if (m_testPackage.length) {
			dub = new Dub(Path(getcwd()));

			setupPackage(dub, m_testPackage);
			m_defaultConfig = dub.project.getDefaultConfiguration(m_buildPlatform);

			GeneratorSettings gensettings;
			gensettings.platform = m_buildPlatform;
			gensettings.config = m_buildConfig.length ? m_buildConfig : m_defaultConfig;
			gensettings.buildType = m_buildType;
			gensettings.compiler = m_compiler;
			gensettings.buildSettings = m_buildSettings;
			gensettings.combined = m_combined;
			gensettings.run = m_programStatusCode != int.min || m_programRegex.length;
			gensettings.runArgs = app_args;
			gensettings.force = true;
			gensettings.compileCallback = check(m_compilerStatusCode, m_compilerRegex);
			gensettings.linkCallback = check(m_linkerStatusCode, m_linkerRegex);
			gensettings.runCallback = check(m_programStatusCode, m_programRegex);
			try dub.generateProject("build", gensettings);
			catch (DustmiteMismatchException) {
				logInfo("Dustmite test doesn't match.");
				return 3;
			}
			catch (DustmiteMatchException) {
				logInfo("Dustmite test matches.");
				return 0;
			}
		} else {
			enforceUsage(free_args.length == 1, "Expected destination path.");
			auto path = Path(free_args[0]);
			path.normalize();
			enforceUsage(path.length > 0, "Destination path must not be empty.");
			if (!path.absolute) path = Path(getcwd()) ~ path;
			enforceUsage(!path.startsWith(dub.rootPath), "Destination path must not be a sub directory of the tested package!");

			setupPackage(dub, null);
			auto prj = dub.project;
			if (m_buildConfig.empty)
				m_buildConfig = prj.getDefaultConfiguration(m_buildPlatform);

			void copyFolderRec(Path folder, Path dstfolder)
			{
				mkdirRecurse(dstfolder.toNativeString());
				foreach (de; iterateDirectory(folder.toNativeString())) {
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

			bool[string] visited;
			foreach (pack_; prj.getTopologicalPackageList()) {
				auto pack = pack_.basePackage;
				if (pack.name in visited) continue;
				visited[pack.name] = true;
				auto dst_path = path ~ pack.name;
				logInfo("Copy package '%s' to destination folder...", pack.name);
				copyFolderRec(pack.path, dst_path);

				// overwrite package description file with additional version information
				pack_.storeInfo(dst_path);
			}
			logInfo("Executing dustmite...");
			auto testcmd = format("%s dustmite --vquiet --test-package=%s -b %s -c %s --compiler %s -a %s",
								  thisExePath, prj.name, m_buildType, m_buildConfig, m_compilerName, m_arch);
			if (m_compilerStatusCode != int.min) testcmd ~= format(" --compiler-status=%s", m_compilerStatusCode);
			if (m_compilerRegex.length) testcmd ~= format(" \"--compiler-regex=%s\"", m_compilerRegex);
			if (m_linkerStatusCode != int.min) testcmd ~= format(" --linker-status=%s", m_linkerStatusCode);
			if (m_linkerRegex.length) testcmd ~= format(" \"--linker-regex=%s\"", m_linkerRegex);
			if (m_programStatusCode != int.min) testcmd ~= format(" --program-status=%s", m_programStatusCode);
			if (m_programRegex.length) testcmd ~= format(" \"--program-regex=%s\"", m_programRegex);
			if (m_combined) testcmd ~= " --combined";
			// TODO: pass *all* original parameters
			logDiagnostic("Running dustmite: %s", testcmd);
			auto dmpid = spawnProcess(["dustmite", path.toNativeString(), testcmd]);
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
			if (arg.defaultValue.peek!bool) {
				writef("--%s", larg);
				col += larg.length + 2;
			} else {
				writef("--%s=VALUE", larg);
				col += larg.length + 8;
			}
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
	auto wrapped = string.wrap(lineWidth, getRepString!' '(first_line_pos), getRepString!' '(indent));
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

private void warnRenamed(string prev, string curr)
{
	logWarn("The '%s' Command was renamed to '%s'. Please update your scripts.", prev, curr);
}

