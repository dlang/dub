/**
	The entry point to dub

	Copyright: © 2012 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff, Sönke Ludwig
*/
module app;

import dub.compilers.compiler;
import dub.dependency;
import dub.dub;
import dub.generators.generator;
import dub.internal.std.process;
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
		LogLevel loglevel = LogLevel.info;
		string build_type, build_config;
		string compiler_name = "dmd";
		string arch;
		bool rdmd = false;
		bool print_platform, print_builds, print_configs;
		bool install_system = false, install_local = false;
		string install_version;
		string[] registry_urls;
		string[] debug_versions;
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
			"debug", &debug_versions,
			"print-builds", &print_builds,
			"print-configs", &print_configs,
			"print-platform", &print_platform,
			"system", &install_system,
			"local", &install_local,
			"version", &install_version,
			"registry", &registry_urls
			);

		if( vverbose ) loglevel = LogLevel.debug_;
		else if( verbose ) loglevel = LogLevel.diagnostic;
		else if( vquiet ) loglevel = LogLevel.none;
		else if( quiet ) loglevel = LogLevel.warn;
		setLogLevel(loglevel);

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

		BuildSettings build_settings;
		auto compiler = getCompiler(compiler_name);
		auto build_platform = compiler.determinePlatform(build_settings, compiler_name, arch);
		build_settings.addDebugVersions(debug_versions);

		if( print_platform ){
			logInfo("Build platform:");
			logInfo("  Compiler: %s", build_platform.compiler);
			logInfo("  System: %s", build_platform.platform.join(" "));
			logInfo("  Architecture: %s", build_platform.architecture.join(" "));
			logInfo("");
		}

		Dub dub = new Dub(registry_urls.map!(url => cast(PackageSupplier)new RegistryPackageSupplier(Url(url))).array);
		string def_config;

		bool loadCwdPackage()
		{
			if( !existsFile("package.json") && !existsFile("source/app.d") ){
				logInfo("");
				logInfo("Neither package.json, nor source/app.d was found in the current directory.");
				logInfo("Please run dub from the root directory of an existing package, or create a new");
				logInfo("package using \"dub init <name>\".");
				logInfo("");
				showHelp(null);
				return false;
			}

			dub.loadPackageFromCwd();

			def_config = dub.getDefaultConfiguration(build_platform);
			if( !build_config.length ) build_config = def_config;

			return true;
		}

		// handle the command
		switch( cmd ){
			default:
				enforce(false, "Command is unknown: " ~ cmd);
				assert(false);
			case "help":
				if(args.length >= 2) cmd = args[1];
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
				dub.update(UpdateOptions.Upgrade | (annotate ? UpdateOptions.JustAnnotate : UpdateOptions.None));
				return 0;
			case "install":
				enforce(args.length >= 2, "Missing package name.");
				auto location = InstallLocation.userWide;
				auto name = args[1];
				enforce(!install_local || !install_system, "Cannot install locally and system wide at the same time.");
				if (install_local) location = InstallLocation.local;
				else if (install_system) location = InstallLocation.systemWide;
				if (install_version.length) dub.install(name, Dependency(install_version), location, true);
				else {
					try dub.install(name, Dependency(">=0.0.0"), location, true);
					catch(Exception e){
						logInfo("Installing a release version failed: %s", e.msg);
						logInfo("Retry with ~master...");
						dub.install(name, Dependency("~master"), location, true);
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
			case "add-path":
				enforce(args.length >= 2, "Missing search path.");
				dub.addSearchPath(args[1], install_system);
				break;
			case "remove-path":
				enforce(args.length >= 2, "Missing search path.");
				dub.removeSearchPath(args[1], install_system);
				break;
			case "list-installed":
				logInfo("Installed packages:");
				foreach (p; dub.packageManager.getPackageIterator())
					logInfo("  %s %s: %s", p.name, p.ver, p.path.toNativeString());
				logInfo("");
				break;
			case "run":
			case "build":
			case "generate":
				if (!loadCwdPackage()) return 1;

				string generator;
				if( cmd == "run" || cmd == "build" ) generator = rdmd ? "rdmd" : "build";
				else {
					if( args.length >= 2 ) generator = args[1];
					if(generator.empty) {
						logInfo("Usage: dub generate <generator_name>");
						return 1;
					}
				}

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
					dub.update(annotate ? UpdateOptions.JustAnnotate : UpdateOptions.None);
				}

				enforce(build_config.length == 0 || dub.configurations.canFind(build_config), "Unknown build configuration: "~build_config);

				if (build_type.length == 0) {
					if (environment.get("DFLAGS")) build_type = "$DFLAGS";
					else build_type = "debug";
				}

				GeneratorSettings gensettings;
				gensettings.platform = build_platform;
				gensettings.config = build_config;
				gensettings.buildType = build_type;
				gensettings.compiler = compiler;
				gensettings.compilerBinary = compiler_name;
				gensettings.buildSettings = build_settings;
				gensettings.run = cmd == "run";
				gensettings.runArgs = args[1 .. $];

				logDiagnostic("Generating using %s", generator);
				dub.generateProject(generator, gensettings);
				if( build_type == "ddox" ) dub.runDdox();
				break;
			case "describe":
				if (!loadCwdPackage()) return 1;
				dub.describeProject(build_platform, build_config);				
				break;
		}

		return 0;
	}
	catch(Throwable e)
	{
		logError("Error: %s\n", e.msg);
		logDiagnostic("Full exception: %s", sanitize(e.toString()));
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
`Usage: dub [<command>] [<options...>] [-- <application arguments...>]

Manages the DUB project in the current directory. "--" can be used to separate
DUB options from options passed to the application. If the command is omitted,
dub will default to "run".

Available commands:
    help                 Prints this help screen
    init [<directory>]   Initializes an empty project in the specified directory
    run                  Compiles and runs the application (default command)
    build                Just compiles the application in the project directory
    upgrade              Forces an upgrade of all dependencies
    install <name>       Manually installs a package. See 'dub help install'.
    uninstall <name>     Uninstalls a package. See 'dub help uninstall'.
    add-local <dir> <version>
                         Adds a local package directory (e.g. a git repository)
    remove-local <dir>   Removes a local package directory
    add-path <dir>       Adds a default package search path
    remove-path <dir>    Removes a package search path
    list-installed       Prints a list of all installed packages
    generate <name>      Generates project files using the specified generator:
                           visuald, visuald-combined, mono-d, build, rdmd
    describe             Prints a JSON description of the project and its
                         dependencies

General options:
        --annotate       Do not execute dependency installations, just print
    -v  --verbose        Also output debug messages
        --vverbose       Also output trace messages (produces a lot of output)
    -q  --quiet          Only output warnings and errors
        --vquiet         No output
        --registry=URL   Search the given DUB registry URL first when resolving
                         dependencies. Can be specified multiple times.

Build/run options:
        --build=NAME     Specifies the type of build to perform. Note that
                         setting the DFLAGS environment variable will override
                         the build type with custom flags.
                         Possible names:
                           debug (default), plain, release, unittest, profile,
                           docs, ddox, cov, unittest-cov and custom types
        --config=NAME    Builds the specified configuration. Configurations can
                         be defined in package.json
        --compiler=NAME  Specifies the compiler binary to use. Arbitrary pre-
                         and suffixes to the identifiers below are recognized
                         (e.g. ldc2 or dmd-2.063) and matched to the proper
                         compiler type:
                           dmd (default), gcc, ldc, gdmd, ldmd
        --arch=NAME      Force a different architecture (e.g. x86 or x86_64)
        --nodeps         Do not check dependencies for 'run' or 'build'
        --print-builds   Prints the list of available build types
        --print-configs  Prints the list of available configurations
        --print-platform Prints the identifiers for the current build platform
                         as used for the build fields in package.json
        --rdmd           Use rdmd instead of directly invoking the compiler
        --debug=NAME     Define the specified debug version identifier when
                         building - can be used multiple times

Install options:
        --version        Use the specified version/branch instead of the latest
        --system         Install system wide instead of user local
        --local          Install as in a sub folder of the current directory

`);
	logInfo("DUB version %s", dubVersion);
}
