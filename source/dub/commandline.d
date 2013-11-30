/**
	Defines the behavior of the DUB command line client.

	Copyright: © 2012-2013 Matthias Dondorff
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
import dub.internal.vibecompat.inet.url;
import dub.package_;
import dub.packagesupplier;
import dub.project;
import dub.version_;

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
import std.variant;


int runDubCommandLine(string[] args)
{
	logDiagnostic("DUB version %s", dubVersion);

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

	// parse general options
	bool verbose, vverbose, quiet, vquiet;
	bool help, annotate;
	LogLevel loglevel = LogLevel.info;
	string[] registry_urls;
	string root_path = getcwd();

	auto common_args = new CommandArgs(args);
	try {
		common_args.getopt("h|help", &help, ["Display general or command specific help"]);
		common_args.getopt("root", &root_path, ["Path to operate in instead of the current working dir"]);
		common_args.getopt("registry", &registry_urls, ["Search the given DUB registry URL first when resolving dependencies. Can be specified multiple times."]);
		common_args.getopt("annotate", &annotate, ["Do not perform any action, just print what would be done"]);
		common_args.getopt("v|verbose", &verbose, ["Print diagnostic output"]);
		common_args.getopt("vverbose", &vverbose, ["Print debug output"]);
		common_args.getopt("q|quiet", &quiet, ["Only print warnings and errors"]);
		common_args.getopt("vquiet", &vquiet, ["Print no messages"]);

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
	Command[] commands = [
		new InitCommand,
		new RunCommand,
		new BuildCommand,
		new GenerateCommand,
		new DescribeCommand,
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
		new ListInstalledCommand
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

	// execute the sepected command
	foreach (cmd; commands)
		if (cmd.name == cmdname) {
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

			// initialize DUB
			auto package_suppliers = registry_urls.map!(url => cast(PackageSupplier)new RegistryPackageSupplier(Url(url))).array;
			Dub dub = new Dub(package_suppliers, root_path);
			dub.dryRun = annotate;
			
			// make the CWD package available so that for example sub packages can reference their
			// parent package.
			try dub.packageManager.getTemporaryPackage(Path(root_path), Version("~master"));
			catch (Exception e) { logDiagnostic("No package found in current working directory."); }

			try return cmd.execute(dub, command_args.extractRemainingArgs(), app_args);
			catch (UsageException e) {
				logError("%s", e.msg);
				logDiagnostic("Full exception: %s", e.toString().sanitize);
				return 1;
			}
			catch (Throwable e) {
				logError("Error executing command %s: %s\n", cmd.name, e.msg);
				logDiagnostic("Full exception: %s", e.toString().sanitize);
				return 2;
			}
		}
	
	logError("Unknown command: %s", cmdname);
	writeln();
	showHelp(commands, common_args);
	return 1;
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

	abstract void prepare(scope CommandArgs args);
	abstract int execute(Dub dub, string[] free_args, string[] app_args);
}


/******************************************************************************/
/* INIT                                                                       */
/******************************************************************************/

class InitCommand : Command {
	private {
		string m_directory;
		string m_type = "minimal";
	}

	this()
	{
		this.name = "init";
		this.argumentsPattern = "[<directory> [<type>]]";
		this.description = "Initializes an empty package skeleton";
		this.helpText = [
			"Initializes an empty package of the specified type in the given directory. By default, the current working dirctory is used. Available types:",
			"",
			"minimal - a simple \"hello world\" project with no dependencies (default)",
			"vibe.d - minimal HTTP server based on vibe.d"
		];
	}

	override void prepare(scope CommandArgs args)
	{
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		string dir, type = "minimal";
		enforceUsage(app_args.empty, "Unexpected application arguments.");
		enforceUsage(free_args.length <= 2, "Too many arguments.");
		if (free_args.length >= 1) dir = free_args[0];
		if (free_args.length >= 2) type = free_args[1];
		dub.createEmptyPackage(Path(m_directory), m_type);
		return 0;
	}
}


/******************************************************************************/
/* FETCH / REMOVE / UPGRADE                                                   */
/******************************************************************************/

class UpgradeCommand : Command {
	private {
		bool m_prerelease = false;
	}

	this()
	{
		this.name = "upgrade";
		this.argumentsPattern = "";
		this.description = "Forces an upgrade of all dependencies";
		this.helpText = [
			"Upgrades all dependencies of the package by querying the package registry(ies) for new versions."
		];
	}

	override void prepare(scope CommandArgs args)
	{
		args.getopt("prerelease", &m_prerelease, [
			"Uses the latest pre-release version, even if release versions are available"
		]);
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		enforceUsage(free_args.length == 0, "Unexpected arguments.");
		enforceUsage(app_args.length == 0, "Unexpected application arguments.");
		dub.loadPackageFromCwd();
		logInfo("Upgrading project in %s", dub.projectPath.toNativeString());
		auto options = UpdateOptions.upgrade;
		if (m_prerelease) options |= UpdateOptions.preRelease;
		dub.update(options);
		return 0;
	}
}

class FetchRemoveCommand : Command {
	protected {
		string m_version;
		bool m_system = false;
		bool m_local = false;
	}

	override void prepare(scope CommandArgs args)
	{
		args.getopt("version", &m_version, [
			"Use the specified version/branch instead of the latest available match",
			"The remove command also accepts \"*\" here as a wildcard to remove all versions of the package from the specified location"
		]);

		args.getopt("system", &m_system, ["Puts the package into the system wide package cache instead of the user local one."]);
		args.getopt("local", &m_system, ["Puts the package into a sub folder of the current working directory. Cannot be mixed with --system."]);
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
			"Note: Use the \"dependencies\" field in the package description file (e.g. package.json) if you just want to use a certain package as a dependency, you don't have to explicitly fetch packages.",
			"",
			"Explicit retrieval/removal of packages is only needed when you want to put packages to a place where several applications can share these. If you just have an dependency to a package, just add it to your package.json, dub will do the rest for you."
			"",
			"Without specified options, placement/removal will default to a user wide shared location."
			"",
			"Complete applications can be retrieved and run easily by e.g.",
			"$ dub fetch vibelog --local",
			"$ cd vibelog",
			"$ dub",
			""
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

		auto location = PlacementLocation.userWide;
		if (m_local) location = PlacementLocation.local;
		else if (m_system) location = PlacementLocation.systemWide;

		auto name = free_args[0];

		if (m_version.length) dub.fetch(name, Dependency(m_version), location, true, false);
		else {
			try {
				dub.fetch(name, Dependency(">=0.0.0"), location, true, false);
				logInfo(
					"Please note that you need to use `dub run <pkgname>` " ~ 
					"or add it to dependencies of your package to actually use/run it. " ~
					"dub does not do actual installation of packages outside of its own ecosystem.");
			}
			catch(Exception e){
				logInfo("Getting a release version failed: %s", e.msg);
				logInfo("Retry with ~master...");
				dub.fetch(name, Dependency("~master"), location, true, true);
			}
		}
		return 0;
	}
}

class InstallCommand : FetchCommand {
	this() { this.name = "install"; }
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
		enforceUsage(!m_local || !m_system, "--local and --system are exclusive to each other.");
		enforceUsage(free_args.length == 1, "Expecting exactly one argument.");
		enforceUsage(app_args.length == 0, "Unexpected application arguments.");

		auto package_id = free_args[0];
		auto location = PlacementLocation.userWide;
		if (m_local) location = PlacementLocation.local;
		else if (m_system) location = PlacementLocation.systemWide;

		try dub.remove(package_id, m_version, location);
		catch {
			logError("Please specify a individual version or use the wildcard identifier '%s' (without quotes).", Dub.RemoveVersionWildcard);
			return 1;
		}

		return 0;
	}
}

class UninstallCommand : RemoveCommand {
	this() { this.name = "uninstall"; }
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
		this.argumentsPattern = "<path> <version>";
		this.description = "Adds a local package directory (e.g. a git repository)";
		this.helpText = ["Adds a local package directory (e.g. a git repository)"];
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		enforceUsage(free_args.length == 2, "Expecting two arguments.");
		dub.addLocalPackage(free_args[0], free_args[1], m_system);
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


/******************************************************************************/
/* LIST                                                                       */
/******************************************************************************/

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
		return true;
	}
}

class ListInstalledCommand : ListCommand {
	this() { this.name = "list-installed"; }
	override void prepare(scope CommandArgs args) { super.prepare(args); }
	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		warnRenamed("list-installed", "list");
		return super.execute(dub, free_args, app_args);
	}
}


/******************************************************************************/
/* GENERATE / BUILD / RUN / DESCRIBE                                          */
/******************************************************************************/

abstract class PackageBuildCommand : Command {
	protected {
		string m_build_type;
		string m_build_config;
		string m_compiler_name = "dmd";
		string m_arch;
		string[] m_debug_versions;
		Compiler m_compiler;
		BuildPlatform m_buildPlatform;
		BuildSettings m_buildSettings;
		string m_defaultConfig;
	}

	override void prepare(scope CommandArgs args)
	{
		args.getopt("build", &m_build_type, [
			"Specifies the type of build to perform. Note that setting the DFLAGS environment variable will override the build type with custom flags.",
			"Possible names:",
			"  debug (default), plain, release, unittest, profile, docs, ddox, cov, unittest-cov and custom types"
		]);
		args.getopt("config", &m_build_config, [
			"Builds the specified configuration. Configurations can be defined in package.json"
		]);
		args.getopt("compiler", &m_compiler_name, [
			"Specifies the compiler binary to use. Arbitrary pre- and suffixes to the identifiers below are recognized (e.g. ldc2 or dmd-2.063) and matched to the proper compiler type:",
			"  dmd (default), gdc, ldc, gdmd, ldmd"
		]);
		args.getopt("arch", &m_arch, [
			"Force a different architecture (e.g. x86 or x86_64)"
		]);
		args.getopt("debug", &m_debug_versions, [
			"Define the specified debug version identifier when building - can be used multiple times"
		]);
	}

	protected void setupPackage(Dub dub, string package_name)
	{
		m_compiler = getCompiler(m_compiler_name);
		m_buildPlatform = m_compiler.determinePlatform(m_buildSettings, m_compiler_name, m_arch);
		m_buildSettings.addDebugVersions(m_debug_versions);

		m_defaultConfig = null;
		enforce (loadSpecificPackage(dub, package_name), "Failed to load package.");

		enforce(m_build_config.length == 0 || dub.configurations.canFind(m_build_config), "Unknown build configuration: "~m_build_config);

		if (m_build_type.length == 0) {
			if (environment.get("DFLAGS")) m_build_type = "$DFLAGS";
			else m_build_type = "debug";
		}
	}

	private bool loadSpecificPackage(Dub dub, string package_name)
	{
		Package pack;
		if (!package_name.empty) {
			// load package in root_path to enable searching for sub packages
			loadCwdPackage(dub, null, false);
			pack = dub.packageManager.getFirstPackage(package_name);
			enforce(pack, "Failed to find a package named '"~package_name~"'.");
			logInfo("Building package %s in %s", pack.name, pack.path.toNativeString());
			dub.rootPath = pack.path;
		}
		if (!loadCwdPackage(dub, pack, true)) return false;
		if (!m_build_config.length) m_build_config = m_defaultConfig;
		return true;
	}

	private bool loadCwdPackage(Dub dub, Package pack, bool warn_missing_package)
	{
		if (warn_missing_package && !existsFile(dub.rootPath~"package.json") && !existsFile(dub.rootPath~"source/app.d")) {
			logInfo("");
			logInfo("Neither package.json, nor source/app.d was found in the current directory.");
			logInfo("Please run dub from the root directory of an existing package, or create a new");
			logInfo("package using \"dub init <name>\".");
			logInfo("");
			return false;
		}

		if (pack) dub.loadPackage(pack);
		else dub.loadPackageFromCwd();

		m_defaultConfig = dub.getDefaultConfiguration(m_buildPlatform);

		return true;
	}
}

class GenerateCommand : PackageBuildCommand {
	protected {
		string m_generator;
		bool m_rdmd = false;
		bool m_run = false;
		bool m_force = false;
		bool m_print_platform, m_print_builds, m_print_configs;
		bool m_nodeps;
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
			"visuald-combined - VisualD single project file",
			"build - Builds the package directly",
			"",
			"An optional package name can be given to generate a different package than the root/CWD package."
		];
	}

	override void prepare(scope CommandArgs args)
	{
		super.prepare(args);

		args.getopt("print-builds", &m_print_builds, [
			"Prints the list of available build types"
		]);
		args.getopt("print-configs", &m_print_configs, [
			"Prints the list of available configurations"
		]);
		args.getopt("print-platform", &m_print_platform, [
			"Prints the identifiers for the current build platform as used for the build fields in package.json"
		]);
		args.getopt("nodeps", &m_nodeps, [
			"Do not check dependencies for 'run' or 'build'"
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
		
		if (m_print_builds) { // FIXME: use actual package data
			logInfo("Available build types:");
			foreach (tp; ["debug", "release", "unittest", "profile"])
				logInfo("  %s", tp);
			logInfo("");
		}

		if (m_print_configs) {
			logInfo("Available configurations:");
			foreach (tp; dub.configurations)
				logInfo("  %s%s", tp, tp == m_defaultConfig ? " [default]" : null);
			logInfo("");
		}

		if (!m_nodeps) {
			logInfo("Checking dependencies in '%s'", dub.projectPath.toNativeString());
			dub.update(UpdateOptions.none);
		}

		GeneratorSettings gensettings;
		gensettings.platform = m_buildPlatform;
		gensettings.config = m_build_config;
		gensettings.buildType = m_build_type;
		gensettings.compiler = m_compiler;
		gensettings.buildSettings = m_buildSettings;
		gensettings.run = m_run;
		gensettings.runArgs = app_args;
		gensettings.force = m_force;
		gensettings.rdmd = m_rdmd;

		logDiagnostic("Generating using %s", m_generator);
		dub.generateProject(m_generator, gensettings);
		if (m_build_type == "ddox") dub.runDdox(gensettings.run);
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
		args.getopt("force", &m_force, [
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
		super.prepare(args);
		m_run = true;
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		return super.execute(dub, free_args, app_args);
	}
}

class DescribeCommand : PackageBuildCommand {
	this()
	{
		this.name = "describe";
		this.argumentsPattern = "[<package>]";
		this.description = "Prints a JSON description of the project and its dependencies";
		this.helpText = [
			"Prints a JSON build description for the root package an all of their dependencies in a format similar to a JSON package description file. This is useful mostly for IDEs.",
			"All usual options that are also used for build/run/generate apply."
		];
	}

	override void prepare(scope CommandArgs args)
	{
		super.prepare(args);
	}

	override int execute(Dub dub, string[] free_args, string[] app_args)
	{
		string package_name;
		enforceUsage(free_args.length <= 1, "Expected one or zero arguments.");
		if (free_args.length >= 1) package_name = free_args[1];

		setupPackage(dub, package_name);

		dub.describeProject(m_buildPlatform, m_build_config);				
		return 0;
	}
}


/******************************************************************************/
/* HELP                                                                       */
/******************************************************************************/

private {
	enum shortArgColumn = 4;
	enum longArgColumn = 8;
	enum descColumn = 25;
	enum lineWidth = 80;
}

private void showHelp(Command[] commands, CommandArgs common_args)
{
	writeln(
`Usage: dub [<command>] [<options...>] [-- [<application arguments...>]]

Manages the DUB project in the current directory. If the command is omitted,
DUB will default to "run". When running an application, "--" can be used to
separate DUB options from options passed to the application. 

Run "dub <command> --help" to get help for a specific command.

Available commands:`);

	foreach (cmd; commands) {
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
	writeln();
	writeln(`General options:`);
	writeOptions(common_args);
}

private void showCommandHelp(Command cmd, CommandArgs args, CommandArgs common_args)
{
	writefln(`Usage: dub %s %s [<options...>]%s`, cmd.name, cmd.argumentsPattern, cmd.acceptsAppArgs ? " [-- <application arguments...>]": null);
	writeln();
	foreach (ln; cmd.helpText)
		ln.writeWrapped();
	
	if (args.recognizedArgs.length) {
		writeln();
		writeln("Options:");
		writeOptions(args);
	}
	
	writeln();
	writeln("General options:");
	writeOptions(common_args);
}

private void writeOptions(CommandArgs args)
{
	foreach (arg; args.recognizedArgs) {
		auto names = arg.names.split("|");
		assert(names.length == 1 || names.length == 2);
		string sarg = names[0].length == 1 ? names[0] : null;
		string larg = names[0].length > 1 ? names[0] : names.length > 1 ? names[1] : null;
		if (sarg) {
			writeWS(shortArgColumn);
			writef("-%s", sarg);
			writeWS(longArgColumn - shortArgColumn - 2);
		} else writeWS(longArgColumn);
		size_t col = longArgColumn;
		if (larg) {
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
	auto wrapped = string.wrap(lineWidth, getWSString(first_line_pos), getWSString(indent));
	wrapped = wrapped[first_line_pos .. $];
	foreach (ln; wrapped.splitLines())
		writeln(ln);
}

private void writeWS(size_t num) { write(getWSString(num)); }

private string getWSString(size_t len)
{
	static string buf;
	if (len > buf.length) buf ~= " ".replicate(len-buf.length);
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
	logWarn("Command '%s' was renamed to '%s'. Old name is deprecated, please update your scripts", prev, curr);
}