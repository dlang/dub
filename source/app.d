/**
	The entry point to vibe.d

	Copyright: © 2012 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff, Sönke Ludwig
*/
module app;

import dub.compilers.compiler;
import dub.dependency;
import dub.dub;
import dub.generators.generator;
import dub.package_;
import dub.project;
import dub.registry;

import vibecompat.core.file;
import vibecompat.core.log;
import vibecompat.inet.url;

import std.algorithm;
import std.array;
import std.conv;
import std.encoding;
import std.exception;
import std.file;
import std.getopt;
import stdx.process;


int main(string[] args)
{
	string cmd;

	version(Windows){
		// rdmd uses $TEMP to compute a temporary path. since cygwin substitutes backslashes
		// with slashes, this causes OPTLINK to fail (it thinks path segments are options)
		// we substitute the other way around here to fix this.
		environment["TEMP"] = environment["TEMP"].replace("/", "\\");
	}

	try {
		// parse general options
		bool verbose, vverbose, quiet, vquiet;
		bool help, nodeps, annotate;
		LogLevel loglevel = LogLevel.Info;
		string build_type = "debug", build_config;
		string compiler_name = "dmd";
		string arch;
		bool rdmd = false;
		bool print_platform, print_builds, print_configs;
		bool install_system = false, install_local = false;
		string install_version;
		getopt(args,
			"v|verbose", &verbose,
			"vverbose", &vverbose,
			"q|quiet", &quiet,
			"vquiet", &vquiet,
			"h|help", &help, // obsolete
			"nodeps", &nodeps,
			"annotate", &annotate,
			"build", &build_type,
			"compiler", &compiler_name,
			"arch", &arch,
			"rdmd", &rdmd,
			"config", &build_config,
			"print-builds", &print_builds,
			"print-configs", &print_configs,
			"print-platform", &print_platform,
			"system", &install_system,
			"local", &install_local,
			"version", &install_version
			);

		if( vverbose ) loglevel = LogLevel.Trace;
		else if( verbose ) loglevel = LogLevel.Debug;
		else if( vquiet ) loglevel = LogLevel.None;
		else if( quiet ) loglevel = LogLevel.Warn;
		setLogLevel(loglevel);
		if( loglevel >= LogLevel.Info ) setPlainLogging(true);

		// extract the command
		if( args.length > 1 && !args[1].startsWith("-") ){
			cmd = args[1];
			args = args[0] ~ args[2 .. $];
		} else cmd = "run";

		// contrary to the documentation, getopt does not remove --
		if( args.length >= 2 && args[1] == "--" ) args = args[0] ~ args[2 .. $];

		// display help if requested (obsolete)
		if( help ){
			showHelp(cmd);
			return 0;
		}

		Url registryUrl = Url.parse("http://registry.vibed.org/");
		logDebug("Using dub registry url '%s'", registryUrl);

		BuildSettings build_settings;
		auto compiler = getCompiler(compiler_name);
		auto build_platform = compiler.determinePlatform(build_settings, compiler_name, arch);

		if( print_platform ){
			logInfo("Build platform:");
			logInfo("  Compiler: %s", build_platform.compiler);
			logInfo("  System: %s", build_platform.platform.join(" "));
			logInfo("  Architecture: %s", build_platform.architecture.join(" "));
			logInfo("");
		}

		Dub dub = new Dub(new RegistryPS(registryUrl));

		// handle the command
		switch( cmd ){
			default:
				enforce(false, "Command is unknown: " ~ cmd);
				assert(false);
			case "help":
				showHelp(cmd);
				return 0;
			case "init":
				string dir;
				if( args.length >= 2 ) dir = args[1];
				dub.createEmptyPackage(Path(dir));
				return 0;
			case "upgrade":
				dub.loadPackageFromCwd();
				logInfo("Upgrading project in %s", dub.projectPath.toNativeString());
				logDebug("dub initialized");
				dub.update(UpdateOptions.Reinstall | (annotate ? UpdateOptions.JustAnnotate : UpdateOptions.None));
				return 0;
			case "install":
				enforce(args.length >= 2, "Missing package name.");
				dub.loadPackageFromCwd();
				auto location = InstallLocation.userWide;
				auto name = args[1];
				enforce(!install_local || !install_system, "Cannot install locally and system wide at the same time.");
				if( install_local ) location = InstallLocation.local;
				else if( install_system ) location = InstallLocation.systemWide;
				if( install_version.length ) dub.install(name, new Dependency(install_version), location);
				else {
					try dub.install(name, new Dependency(">=0.0.0"), location);
					catch(Exception e){
						logInfo("Installing a release version failed: %s", e.msg);
						logInfo("Retry with ~master...");
						dub.install(name, new Dependency("~master"), location);
					}
				}
				break;
			case "uninstall":
				enforce(args.length >= 2, "Missing package name.");
				auto location = InstallLocation.userWide;
				auto package_id = args[1];
				enforce(!install_local || !install_system, "Cannot install locally and system wide at the same time.");
				if( install_local ) location = InstallLocation.local;
				else if( install_system ) location = InstallLocation.systemWide;
				try dub.uninstall(package_id, install_version, location);
				catch logError("Please specify a individual version or use the wildcard identifier '%s' (without quotes).", Dub.UninstallVersionWildcard);
				break;
			case "add-local":
				enforce(args.length >= 3, "Missing arguments.");
				dub.addLocalPackage(args[1], args[2], install_system);
				break;
			case "remove-local":
				enforce(args.length >= 2, "Missing path to package.");
				dub.removeLocalPackage(args[1], install_system);
				break;
			case "list-locals":
				logInfo("Locals:");
				foreach( p; dub.packageManager.getPackageIterator() )
					if( p.installLocation == InstallLocation.local )
						logInfo("  %s %s: %s", p.name, p.ver, p.path.toNativeString());
				logInfo("");
				break;
			case "run":
			case "build":
			case "generate":
				if( !existsFile("package.json") && !existsFile("source/app.d") ){
					logInfo("");
					logInfo("Neither package.json, nor source/app.d was found in the current directory.");
					logInfo("Please run dub from the root directory of an existing package, or create a new");
					logInfo("package using \"dub init <name>\".");
					logInfo("");
					showHelp(null);
					return 1;
				}

				dub.loadPackageFromCwd();

				string generator;
				if( cmd == "run" || cmd == "build" ) generator = rdmd ? "rdmd" : "build";
				else {
					if( args.length >= 2 ) generator = args[1];
					if(generator.empty) {
						logInfo("Usage: dub generate <generator_name>");
						return 1;
					}
				}


				auto def_config = dub.getDefaultConfiguration(build_platform);
				if( !build_config.length ) build_config = def_config;

				if( print_builds ){
					logInfo("Available build types:");
					foreach( tp; ["debug", "release", "unittest", "profile"] )
						logInfo("  %s", tp);
					logInfo("");
				}

				if( print_configs ){
					logInfo("Available configurations:");
					foreach( tp; dub.configurations )
						logInfo("  %s%s", tp, tp == def_config ? " [default]" : null);
					logInfo("");
				}

				if( !nodeps ){
					logInfo("Checking dependencies in '%s'", dub.projectPath.toNativeString());
					logDebug("dub initialized");
					dub.update(annotate ? UpdateOptions.JustAnnotate : UpdateOptions.None);
				}

				enforce(build_config.length == 0 || dub.configurations.canFind(build_config), "Unknown build configuration: "~build_config);

				GeneratorSettings gensettings;
				gensettings.platform = build_platform;
				gensettings.config = build_config;
				gensettings.buildType = build_type;
				gensettings.compiler = compiler;
				gensettings.compilerBinary = compiler_name;
				gensettings.buildSettings = build_settings;
				gensettings.run = cmd == "run";
				gensettings.runArgs = args[1 .. $];

				logDebug("Generating using %s", generator);
				dub.generateProject(generator, gensettings);
				break;
		}

		return 0;
	}
	catch(Throwable e)
	{
		logError("Error: %s\n", e.msg);
		logDebug("Full exception: %s", sanitize(e.toString()));
		logInfo("Run 'dub help' for usage information.");
		return 1;
	}
}

private void showHelp(string command)
{
	if(command == "uninstall" || command == "install") {
		logInfo(
`Usage: dub <install|uninstall> <package> [<options>]

Note: use dependencies (package.json) if you want to add a dependency, you
      don't have to fiddle with installation stuff.

(Un)Installation of packages is only needed when you want to put packages to a 
place where several applications can share these. If you just have an 
dependency to a package, just add it to your package.json, dub will do the rest
for you.

Without specified options, (un)installation will default to a user wide shared
location.

Complete applications can be installed and run easily by e.g.
        dub install vibelog --local
        cd vibelog
        dub
This will grab all needed dependencies and compile and run the application.

Install options:
        --version        Use the specified version/branch instead of the latest
                         For the uninstall command, this may be a wildcard 
                         string: "*", which will remove all packages from the
                         specified location.
        --system         Install system wide instead of user local
        --local          Install as in a sub folder of the current directory
                         Note that system and local cannot be mixed.
`);
		return;
	}

	// No specific help, show general help.
	logInfo(
`Usage: dub [<command>] [<vibe options...>] [-- <application options...>]

Manages the DUB project in the current directory. "--" can be used to separate
DUB options from options passed to the application. If the command is omitted,
dub will default to "run".

Possible commands:
    help                 Prints this help screen
    init [<directory>]   Initializes an empy project in the specified directory
    run                  Compiles and runs the application (default command)
    build                Just compiles the application in the project directory
    upgrade              Forces an upgrade of all dependencies
    install <name>       Manually installs a package. See 'dub help install'.
    uninstall <name>     Uninstalls a package. See 'dub help uninstall'.
    add-local <dir> <version>
                         Adds a local package directory (e.g. a git repository)
    remove-local <dir>   Removes a local package directory
    list-locals          Prints a list of all locals
    generate <name>      Generates project files using the specified generator:
                         visuald, mono-d, build, rdmd

General options:
        --annotate       Do not execute dependency installations, just print
    -v  --verbose        Also output debug messages
        --vverbose       Also output trace messages (produces a lot of output)
    -q  --quiet          Only output warnings and errors
        --vquiet         No output

Build/run options:
        --build=NAME     Specifies the type of build to perform. Valid names:
                         debug (default), release, unittest, profile, docs,
                         plain
        --config=NAME    Builds the specified configuration. Configurations can
                         be defined in package.json
        --compiler=NAME  Uses one of the supported compilers:
                         dmd (default), gcc, ldc, gdmd, ldmd
        --arch=NAME      Force a different architecture (e.g. x86 or x86_64)
        --nodeps         Do not check dependencies for 'run' or 'build'
        --print-builds   Prints the list of available build types
        --print-configs  Prints the list of available configurations
        --print-platform Prints the identifiers for the current build platform
                         as used for the build fields in package.json
        --rdmd           Use rdmd instead of directly invoking the compiler

Install options:
        --version        Use the specified version/branch instead of the latest
        --system         Install system wide instead of user local
        --local          Install as in a sub folder of the current directory

`);
}
