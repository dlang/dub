/**
	The entry point to vibe.d

	Copyright: © 2012 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff
*/
module app;

import dub.dub;
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
		getopt(args,
			"v|verbose", &verbose,
			"vverbose", &vverbose,
			"q|quiet", &quiet,
			"vquiet", &vquiet,
			"h|help", &help,
			"nodeps", &nodeps,
			"annotate", &annotate
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

		// display help if requested
		if( help ){
			showHelp(cmd);
			return 0;
		}

		auto appPath = getcwd();
		string del_exe_file;
		Url registryUrl = Url.parse("http://registry.vibed.org/");
		logDebug("Using vpm registry url '%s'", registryUrl);

		// handle the command
		switch( cmd ){
			default:
				enforce(false, "Command is unknown.");
				assert(false);
			case "init":
				string dir = ".";
				if( args.length >= 2 ) dir = args[1];
				initDirectory(dir);
				break;
			case "run":
			case "build":
				Vpm vpm = new Vpm(Path(appPath), new RegistryPS(registryUrl));
				if( !nodeps ){
					logInfo("Checking dependencies in '%s'", appPath);
					logDebug("vpm initialized");
					vpm.update(annotate ? UpdateOptions.JustAnnotate : UpdateOptions.None);
				}

				//Added check for existance of [AppNameInPackagejson].d
				//If exists, use that as the starting file.
				auto outfile = getBinName(vpm);
				auto mainsrc = getMainSourceFile(vpm);

				logDebug("Application output name is '%s'", outfile);

				// Create start script, which will be used by the calling bash/cmd script.
				// build "rdmd --force %DFLAGS% -I%~dp0..\source -Jviews -Isource @deps.txt %LIBS% source\app.d" ~ application arguments
				// or with "/" instead of "\"
				string[] flags = ["--force"];
				if( cmd == "build" ){
					flags ~= "--build-only";
					flags ~= "-of"~outfile;
				} else {
					version(Windows){
						import std.random;
						auto rnd = to!string(uniform(uint.min, uint.max)) ~ "-";
						del_exe_file = environment.get("TEMP")~"\\.rdmd\\source\\"~rnd~outfile;
						flags ~= "-of"~del_exe_file;
					}
				}
				flags ~= "-g";
				flags ~= vpm.dflags;
				flags ~= getPackagesAsVersion(vpm);
				flags ~= (mainsrc).toNativeString();
				flags ~= args[1 .. $];

				logInfo("Running %s", "rdmd " ~ getDflags() ~ " " ~ join(flags, " "));
				auto rdmd_pid = spawnProcess("rdmd " ~ getDflags() ~ " " ~ join(flags, " "));
				rdmd_pid.wait();

				if( del_exe_file.length ) remove(del_exe_file);
				break;
			case "upgrade":
				logInfo("Upgrading application in '%s'", appPath);
				Vpm vpm = new Vpm(Path(appPath), new RegistryPS(registryUrl));
				logDebug("vpm initialized");
				vpm.update(UpdateOptions.Reinstall | (annotate ? UpdateOptions.JustAnnotate : UpdateOptions.None));
				break;
		}

		return 0;
	}
	catch(Throwable e)
	{
		logError("Error executing command '%s': %s\n", cmd, e.msg);
		logDebug("Full exception: %s", sanitizeUTF8(cast(ubyte[])e.toString()));
		showHelp(cmd);
		return -1;
	}
}


private void showHelp(string command)
{
	// This help is actually a mixup of help for this application and the
	// supporting vibe script / .cmd file.
	logInfo(
"Usage: vibe [<command>] [<vibe options...>] [-- <application options...>]

Manages the vibe.d application in the current directory. A single -- can be used
to separate vibe options from options passed to the application.

Possible commands:
    init [<directory>]   Initializes an empy project in the specified directory
    run                  Compiles and runs the application
    build                Just compiles the application in the project directory
    upgrade              Forces an upgrade of all dependencies

Options:
    -v  --verbose        Also output debug messages
        --vverbose       Also output trace messages (produces a lot of output)
    -q  --quiet          Only output warnings and errors
        --vquiet         No output
    -h  --help           Print this help screen
        --nodeps         Do not check dependencies for 'run' or 'build'
        --annotate       Do not execute dependency installations, just print
");
}


private string getDflags()
{
	auto globVibedDflags = environment.get("DFLAGS");
	if(globVibedDflags == null)
		globVibedDflags = "-debug -g -w -property";
	return globVibedDflags;
}

private string stripDlangSpecialChars(string s) 
{
	char[] ret = s.dup;
	for(int i=0; i<ret.length; ++i)
		if(!isAlpha(ret[i]))
			ret[i] = '_';
	return to!string(ret);
}

private string[] getPackagesAsVersion(const Vpm vpm)
{
	string[] ret;
	string[string] pkgs = vpm.installedPackages();
	foreach(id, vers; pkgs)
		ret ~= "-version=VPM_package_" ~ stripDlangSpecialChars(id);
	return ret;
}

private string getBinName(const Vpm vpm)
{
	string ret;
	if( vpm.packageName.length > 0 )
		ret = vpm.packageName();
	//Otherwise fallback to source/app.d
	else ret ="app";
	version(Windows) { ret ~= ".exe"; }

	return ret;
} 

private Path getMainSourceFile(const Vpm vpm)
{
	auto p = Path("source") ~ (vpm.packageName() ~ ".d");
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
	if( (existsFile(cwd ~ "package.json"))        ||
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
	openFile(cwd ~ "package.json", FileMode.Append).write(packageJson);
	openFile(cwd ~ "source/app.d", FileMode.Append).write(appFile);     
	//Act smug to the user. 
	logInfo("Successfully created empty project.");
}
