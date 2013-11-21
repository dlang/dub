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


int runDubCommandLine(string[] args)
{
	logDiagnostic("DUB version %s", dubVersion);

	string cmd;

	version(Windows){
		// rdmd uses $TEMP to compute a temporary path. since cygwin substitutes backslashes
		// with slashes, this causes OPTLINK to fail (it thinks path segments are options)
		// we substitute the other way around here to fix this.
		environment["TEMP"] = environment["TEMP"].replace("/", "\\");
	}

	try {
		// split application arguments from DUB arguments
		string[] app_args;
		auto app_args_idx = args.countUntil("--");
		if (app_args_idx >= 0) {
			app_args = args[app_args_idx+1 .. $];
			args = args[0 .. app_args_idx];
		}

		// parse general options
		bool verbose, vverbose, quiet, vquiet;
		bool help, nodeps, annotate;
		LogLevel loglevel = LogLevel.info;
		string build_type, build_config;
		string compiler_name = "dmd";
		string arch;
		bool rdmd = false;
		bool print_platform, print_builds, print_configs;
		bool place_system_wide = false, place_locally = false;
		bool pre_release = false;
		string retrieved_version;
		string[] registry_urls;
		string[] debug_versions;
		string root_path = getcwd();
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
			"system", &place_system_wide,
			"local", &place_locally,
			"prerelease", &pre_release,
			"version", &retrieved_version,
			"registry", &registry_urls,
			"root", &root_path
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

		auto package_suppliers = registry_urls.map!(url => cast(PackageSupplier)new RegistryPackageSupplier(Url(url))).array;
		Dub dub = new Dub(package_suppliers, root_path);
		string def_config;

		// make the CWD package available so that for example sub packages can reference their
		// parent package.
		try dub.packageManager.getTemporaryPackage(Path(root_path), Version("~master"));
		catch (Exception e) { logDiagnostic("No package found in current working directory."); }

		bool loadCwdPackage(Package pack, bool warn_missing_package)
		{
			if (warn_missing_package && !existsFile(dub.rootPath~"package.json") && !existsFile(dub.rootPath~"source/app.d")) {
				logInfo("");
				logInfo("Neither package.json, nor source/app.d was found in the current directory.");
				logInfo("Please run dub from the root directory of an existing package, or create a new");
				logInfo("package using \"dub init <name>\".");
				logInfo("");
				showHelp(null);
				return false;
			}

			if (pack) dub.loadPackage(pack);
			else dub.loadPackageFromCwd();

			def_config = dub.getDefaultConfiguration(build_platform);

			return true;
		}

		string package_name;
		bool loadSelectedPackage()
		{
			Package pack;
			if (!package_name.empty) {
				// load package in root_path to enable searching for sub packages
				loadCwdPackage(null, false);
				pack = dub.packageManager.getFirstPackage(package_name);
				enforce(pack, "Failed to find a package named '"~package_name~"'.");
				logInfo("Building package %s in %s", pack.name, pack.path.toNativeString());
				dub.rootPath = pack.path;
			}
			if (!loadCwdPackage(pack, true)) return false;
			if (!build_config.length) build_config = def_config;
			return true;
        }

		static void warnRenamed(string prev, string curr)
		{
			logWarn("Command '%s' was renamed to '%s'. Old name is deprecated, please update your scripts", prev, curr);
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
				string type = "minimal";
				if (args.length >= 2) dir = args[1];
				if (args.length >= 3) type = args[2];
				dub.createEmptyPackage(Path(dir), type);
				return 0;
			case "upgrade":
				dub.loadPackageFromCwd();
				logInfo("Upgrading project in %s", dub.projectPath.toNativeString());
				dub.update(UpdateOptions.upgrade | (annotate ? UpdateOptions.justAnnotate : UpdateOptions.none) | (pre_release ? UpdateOptions.preRelease : UpdateOptions.none));
				return 0;
			case "install":
				warnRenamed(cmd, "fetch");
				goto case "fetch";
			case "fetch":
				enforce(args.length >= 2, "Missing package name.");
				auto location = PlacementLocation.userWide;
				auto name = args[1];
				enforce(!place_locally || !place_system_wide, "Cannot place package locally and system wide at the same time.");
				if (place_locally) location = PlacementLocation.local;
				else if (place_system_wide) location = PlacementLocation.systemWide;
				if (retrieved_version.length) dub.fetch(name, Dependency(retrieved_version), location, true, false);
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
				break;
			case "uninstall":
				warnRenamed(cmd, "remove");
				goto case "remove";
			case "remove":
				enforce(args.length >= 2, "Missing package name.");
				auto location = PlacementLocation.userWide;
				auto package_id = args[1];
				enforce(!place_locally || !place_system_wide, "Cannot place package locally and system wide at the same time.");
				if ( place_locally ) location = PlacementLocation.local;
				else if( place_system_wide ) location = PlacementLocation.systemWide;
				try dub.remove(package_id, retrieved_version, location);
				catch logError("Please specify a individual version or use the wildcard identifier '%s' (without quotes).", Dub.RemoveVersionWildcard);
				break;
			case "add-local":
				enforce(args.length >= 3, "Missing arguments.");
				dub.addLocalPackage(args[1], args[2], place_system_wide);
				break;
			case "remove-local":
				enforce(args.length >= 2, "Missing path to package.");
				dub.removeLocalPackage(args[1], place_system_wide);
				break;
			case "add-path":
				enforce(args.length >= 2, "Missing search path.");
				dub.addSearchPath(args[1], place_system_wide);
				break;
			case "remove-path":
				enforce(args.length >= 2, "Missing search path.");
				dub.removeSearchPath(args[1], place_system_wide);
				break;
			case "list-installed":
				warnRenamed(cmd, "list");
				goto case "list";
			case "list":
				logInfo("Packages present in the system and known to dub:");
				foreach (p; dub.packageManager.getPackageIterator())
					logInfo("  %s %s: %s", p.name, p.ver, p.path.toNativeString());
				logInfo("");
				break;
			case "run":
			case "build":
			case "generate":
				string generator;
				if( cmd == "run" || cmd == "build" ) {
					generator = rdmd ? "rdmd" : "build";
					if (args.length >= 2) package_name = args[1];
				} else {
					if (args.length >= 2) generator = args[1];
					if (args.length >= 3) package_name = args[2];
					if(generator.empty) {
						logInfo("Usage: dub generate <generator_name> [<package name>]");
						return 1;
					}
				}

				if (!loadSelectedPackage()) return 1;

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
					dub.update(annotate ? UpdateOptions.justAnnotate : UpdateOptions.none);
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
				gensettings.buildSettings = build_settings;
				gensettings.run = cmd == "run";
				gensettings.runArgs = app_args;

				logDiagnostic("Generating using %s", generator);
				dub.generateProject(generator, gensettings);
				if (build_type == "ddox") dub.runDdox(gensettings.run);
				break;
			case "describe":
				if (args.length >= 2) package_name = args[1];
				if (!loadSelectedPackage()) return 1;
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
	if(command == "remove" || command == "fetch") {
		logInfo(
`Usage: dub <fetch|remove> <package> [<options>]

Note: use dependencies (package.json) if you want to add a dependency, you
      don't have to fiddle with caching stuff.

Explicit retrieval/removal of packages is only needed when you want to put packages to a 
place where several applications can share these. If you just have an 
dependency to a package, just add it to your package.json, dub will do the rest
for you.

Without specified options, placement/removal will default to a user wide shared
location.

Complete applications can be retrieved and run easily by e.g.
        dub fetch vibelog --local
        cd vibelog
        dub
This will grab all needed dependencies and compile and run the application.

Note: dub does not do any real "installation" of packages, those are registered
only within dub internal ecosystem. Generation of native system packages / installer
may be added later.

Options:
        --version        Use the specified version/branch instead of the latest
                         For the remove command, this may be a wildcard 
                         string: "*", which will remove all packages from the
                         specified location.
        --system         Put package into system wide dub cache instead of user local one
        --local          Put package to a sub folder of the current directory
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
    init [<directory> [<type>]]
                         Initializes an empty project of the specified type in
                         the given directory. By default, the current working
                         dirctory is used. Available types:
                           minimal (default), vibe.d
    run [<package>]      Builds and runs a package (default command)
    build [<package>]    Builds a package (uses the main package in the current
                         working directory by default)
    upgrade              Forces an upgrade of all dependencies
    fetch <name>         Manually retrieves a package. See 'dub help fetch'.
    remove <name>        Removes present package. See 'dub help remove'.
    add-local <dir> <version>
                         Adds a local package directory (e.g. a git repository)
    remove-local <dir>   Removes a local package directory
    add-path <dir>       Adds a default package search path
    remove-path <dir>    Removes a package search path
    list                 Prints a list of all present packages dub is aware of
    generate <name> [<package>]
                         Generates project files using the specified generator:
                           visuald, visuald-combined, mono-d, build, rdmd
    describe [<package>] Prints a JSON description of the project and its
                         dependencies

General options:
        --annotate       Do not execute dependency retrieval, just print
    -v  --verbose        Also output debug messages
        --vverbose       Also output trace messages (produces a lot of output)
    -q  --quiet          Only output warnings and errors
        --vquiet         No output
        --registry=URL   Search the given DUB registry URL first when resolving
                         dependencies. Can be specified multiple times.
        --root=PATH      Path to operate in instead of the current working dir

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
                           dmd (default), gdc, ldc, gdmd, ldmd
        --arch=NAME      Force a different architecture (e.g. x86 or x86_64)
        --nodeps         Do not check dependencies for 'run' or 'build'
        --print-builds   Prints the list of available build types
        --print-configs  Prints the list of available configurations
        --print-platform Prints the identifiers for the current build platform
                         as used for the build fields in package.json
        --rdmd           Use rdmd instead of directly invoking the compiler
        --debug=NAME     Define the specified debug version identifier when
                         building - can be used multiple times

Fetch/remove options:
        --version        Use the specified version/branch instead of the latest
        --system         Put package into system wide dub cache instead of the
                         user local one
        --local          Extract the package to a sub folder of the current
                         working directory

Upgrade options:
        -prerelease      Uses the latest pre-release version, even if release
                         versions are available

`);
	logInfo("DUB version %s", dubVersion);
}
