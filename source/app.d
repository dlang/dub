/**
	The entry point to vibe.d

	Copyright: © 2012 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff, Sönke Ludwig
*/
module app;

import dub.dependency;
import dub.dub;
import dub.platform;
import dub.package_;
import dub.registry;

import vibe.core.file;
import vibe.core.log;
import vibe.inet.url;
import vibe.utils.string;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.file;
import std.getopt;
import stdx.process;


int main(string[] args)
{
	string cmd;

	try {
		// parse general options
		bool verbose, vverbose, quiet, vquiet;
		bool help, nodeps, annotate;
		LogLevel loglevel = LogLevel.Info;
		string build_type = "debug", build_config;
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

		// FIXME: take into account command line flags
		BuildPlatform build_platform;
		build_platform.platform = determinePlatform();
		build_platform.architecture = determineArchitecture();
		build_platform.compiler = "dmd";

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
				enforce(false, "Command is unknown.");
				assert(false);
			case "help":
				showHelp(cmd);
				break;
			case "init":
				string dir = ".";
				if( args.length >= 2 ) dir = args[1];
				initDirectory(dir);
				break;
			case "run":
			case "build":
				dub.loadPackagefromCwd();
				if( print_builds ){
					logInfo("Available build types:");
					foreach( tp; ["debug", "release", "unittest", "profile"] )
						logInfo("  %s", tp);
					logInfo("");
				}

				if( print_configs ){
					logInfo("Available configurations:");
					foreach( tp; dub.configurations )
						logInfo("  %s", tp);
					logInfo("");
				}

				if( !nodeps ){
					logInfo("Checking dependencies in '%s'", dub.projectPath);
					logDebug("dub initialized");
					dub.update(annotate ? UpdateOptions.JustAnnotate : UpdateOptions.None);
				}

				enforce(build_config.length == 0 || dub.configurations.canFind(build_config), "Unknown build configuration: "~build_config);

				//Added check for existance of [AppNameInPackagejson].d
				//If exists, use that as the starting file.
				auto outfile = getBinName(dub);
				auto mainsrc = getMainSourceFile(dub);

				logDebug("Application output name is '%s'", outfile);

				// Create start script, which will be used by the calling bash/cmd script.
				// build "rdmd --force %DFLAGS% -I%~dp0..\source -Jviews -Isource @deps.txt %LIBS% source\app.d" ~ application arguments
				// or with "/" instead of "\"
				string[] flags = ["--force", "--build-only"];
				string run_exe_file;
				if( cmd == "build" ){
					flags ~= "-of"~outfile;
				} else {
					version(Windows){
						import std.random;
						auto rnd = to!string(uniform(uint.min, uint.max)) ~ "-";
						run_exe_file = environment.get("TEMP")~"\\.rdmd\\source\\"~rnd~outfile;
						flags ~= "-of"~run_exe_file;
					}
				}

				auto settings = dub.getBuildSettings(build_platform, build_config);
				settings.addDFlags(["-w", "-property"]);
				settings.addVersions(getPackagesAsVersion(dub));

				// TODO: this belongs to the builder/generator
				if( settings.libs.length ){
					try {
						logDebug("Trying to use pkg-config to resolve library flags for %s.", settings.libs);
						auto libflags = execute("pkg-config", "--libs" ~ settings.libs.map!(l => "lib"~l)().array());
						enforce(libflags.status == 0, "pkg-config exited with error code "~to!string(libflags.status));
						settings.addLFlags(libflags.output.split());
						settings.libs = null;
					} catch( Exception e ){
						logDebug("pkg-config failed: %s", e.msg);
						logDebug("Falling back to direct -lxyz flags.");
						settings.addLFlags(settings.libs.map!(l => "-l"~l)().array());
						settings.libs = null;
					}
				}

				flags ~= settings.dflags;
				flags ~= settings.lflags.map!(f => "-L"~f)().array();
				flags ~= settings.importPath.map!(f => "-I"~f)().array();
				flags ~= settings.stringImportPath.map!(f => "-J"~f)().array();
				flags ~= settings.versions.map!(f => "-version="~f)().array();
				flags ~= settings.files;
				flags ~= (mainsrc).toNativeString();

				string dflags = environment.get("DFLAGS");
				if( dflags ){
					build_type = "$DFLAGS";
				} else {
					switch( build_type ){
						default: throw new Exception("Unknown build configuration: "~build_type);
						case "plain": dflags = ""; break;
						case "debug": dflags = "-g -debug"; break;
						case "release": dflags = "-release -O -inline"; break;
						case "unittest": dflags = "-g -unittest"; break;
						case "profile": dflags = "-g -O -inline -profile"; break;
						case "docs": assert(false, "docgen not implemented");
					}
				}

				if( build_config.length ) logInfo("Building configuration "~build_config~", build type "~build_type);
				else logInfo("Building default configuration, build type "~build_type);

				logInfo("Running %s", "rdmd " ~ dflags ~ " " ~ join(flags, " "));
				auto rdmd_pid = spawnProcess("rdmd " ~ dflags ~ " " ~ join(flags, " "));
				auto result = rdmd_pid.wait();
				enforce(result == 0, "Build command failed with exit code "~to!string(result));

				if( cmd == "run" ){
					auto prg_pid = spawnProcess(run_exe_file, args[1 .. $]);
					result = prg_pid.wait();
					remove(run_exe_file);
					enforce(result == 0, "Program exited with code "~to!string(result));
				}

				break;
			case "upgrade":
				dub.loadPackagefromCwd();
				logInfo("Upgrading project in '%s'", dub.projectPath);
				logDebug("dub initialized");
				dub.update(UpdateOptions.Reinstall | (annotate ? UpdateOptions.JustAnnotate : UpdateOptions.None));
				break;
			case "install":
				enforce(args.length >= 2, "Missing package name.");
				auto location = InstallLocation.UserWide;
				auto name = args[1];
				enforce(!install_local || !install_system, "Cannot install locally and system wide at the same time.");
				if( install_local ) location = InstallLocation.Local;
				else if( install_system ) location = InstallLocation.SystemWide;
				if( install_version.length ) dub.install(name, new Dependency(install_version), location);
				else {
					try dub.install(name, new Dependency(">=0.0.0"), location);
					catch(Exception) dub.install(name, new Dependency("~master"), location);
				}
				break;
			case "uninstall":
				enforce("Not implemented.");
				break;
			case "add-local":
				enforce(args.length >= 3, "Missing arguments.");
				dub.addLocalPackage(args[1], args[2], install_system);
				break;
			case "remove-local":
				enforce(args.length >= 2, "Missing path to package.");
				dub.removeLocalPackage(args[1], install_system);
				break;
		}

		return 0;
	}
	catch(Throwable e)
	{
		logError("Error: %s\n", e.msg);
		logDebug("Full exception: %s", sanitizeUTF8(cast(ubyte[])e.toString()));
		logInfo("Run 'dub help' for usage information.");
		return 1;
	}
}

private void showHelp(string command)
{
	// This help is actually a mixup of help for this application and the
	// supporting vibe script / .cmd file.
	logInfo(
`Usage: vibe [<command>] [<vibe options...>] [-- <application options...>]

Manages the vibe.d application in the current directory. "--" can be used to
separate vibe options from options passed to the application.

Possible commands:
    help                 Prints this help screen
    init [<directory>]   Initializes an empy project in the specified directory
    run                  Compiles and runs the application (default command)
    build                Just compiles the application in the project directory
    upgrade              Forces an upgrade of all dependencies
    install <name>       Manually installs a package
    uninstall            Uninstalls a package
    add-local <dir> <version>
                         Adds a local package directory (e.g. a git repository)
    remove-local <dir>   Removes a local package directory

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
        --nodeps         Do not check dependencies for 'run' or 'build'
        --print-builds   Prints the list of available build types
        --print-configs  Prints the list of available configurations
        --print-platform Prints the identifiers for the current build platform
                         as used for the build fields in package.json

Install options:
        --version        Use the specified version/branch instead of the latest
        --system         Install system wide instead of user local
        --local          Install as in a sub folder of the current directory

`);
}

private string stripDlangSpecialChars(string s) 
{
	char[] ret = s.dup;
	for(int i=0; i<ret.length; ++i)
		if(!isAlpha(ret[i]))
			ret[i] = '_';
	return to!string(ret);
}

private string[] getPackagesAsVersion(const Dub dub)
{
	string[] ret;
	string[string] pkgs = dub.installedPackages();
	foreach(id, vers; pkgs)
		ret ~= "VPM_package_" ~ stripDlangSpecialChars(id);
	return ret;
}

private string getBinName(const Dub dub)
{
	// take the project name as the base or fall back to "app"
	string ret = dub.projectName;
	if( ret.length == 0 ) ret ="app";
	version(Windows) { ret ~= ".exe"; }
	return ret;
} 

private Path getMainSourceFile(const Dub dub)
{
	auto p = Path("source") ~ (dub.projectName ~ ".d");
	return existsFile(p) ? p : Path("source/app.d");
}

private void initDirectory(string fName)
{ 
    Path cwd; 
    //Check to see if a target directory is specified.
    if(fName != ".") {
        if(!existsFile(fName))  
            createDirectory(fName);
        cwd = Path(fName);  
    } 
    //Otherwise use the current directory.
    else 
        cwd = Path("."); 
    
    //raw strings must be unindented. 
    immutable packageJson = 
`{
    "name": "`~(fName == "." ? "my-project" : fName)~`",
    "version": "0.0.1",
    "description": "An example project skeleton",
    "homepage": "http://example.org",
    "copyright": "Copyright © 2000, Edit Me",
    "authors": [
        "Your Name"
    ],
    "dependencies": {
    }
}
`;
    immutable appFile =
`import vibe.d;

static this()
{ 
    logInfo("Edit source/app.d to start your project.");
}
`;
	//Make sure we do not overwrite anything accidentally
	if( (existsFile(cwd ~ PackageJsonFilename))        ||
		(existsFile(cwd ~ "source"      ))        ||
		(existsFile(cwd ~ "views"       ))        || 
		(existsFile(cwd ~ "public"     )))
	{
		logInfo("The current directory is not empty.\n"
				"vibe init aborted.");
		//Exit Immediately. 
		return;
	}
	//Create the common directories.
	createDirectory(cwd ~ "source");
	createDirectory(cwd ~ "views" );
	createDirectory(cwd ~ "public");
	//Create the common files. 
	openFile(cwd ~ PackageJsonFilename, FileMode.Append).write(packageJson);
	openFile(cwd ~ "source/app.d", FileMode.Append).write(appFile);     
	//Act smug to the user. 
	logInfo("Successfully created empty project.");
}
