/**
	Compiler settings and abstraction.

	Copyright: © 2013 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.compilers.compiler;

import dub.compilers.dmd;
import dub.compilers.gdc;
import dub.compilers.ldc;
import dub.internal.std.process;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.data.json;
import dub.internal.vibecompat.inet.path;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;


static this()
{
	registerCompiler(new DmdCompiler);
	registerCompiler(new GdcCompiler);
	registerCompiler(new LdcCompiler);
}


Compiler getCompiler(string name)
{
	foreach( c; s_compilers )
		if( c.name == name )
			return c;

	// try to match names like gdmd or gdc-2.61
	if( name.canFind("dmd") ) return getCompiler("dmd");
	if( name.canFind("gdc") ) return getCompiler("gdc");
	if( name.canFind("ldc") ) return getCompiler("ldc");
			
	throw new Exception("Unknown compiler: "~name);
}

void registerCompiler(Compiler c)
{
	s_compilers ~= c;
}

void warnOnSpecialCompilerFlags(string[] compiler_flags, string package_name, string config_name)
{
	struct SpecialFlag {
		string[] flags;
		string alternative;
	}
	static immutable SpecialFlag[] s_specialFlags = [
		{["-c", "-o-"], "Automatically issued by DUB, do not specify in package.json"},
		{[ "-w", "-Wall", "-Werr"], `Use "buildRequirements" to control warning behavior`},
		{["-property", "-fproperty"], "Using this flag may break building of dependencies and it will probably be removed from DMD in the future"},
		{["-wi"], `Use the "buildRequirements" field to control warning behavior`},
		{["-d", "-de", "-dw"], `Use the "buildRequirements" field to control deprecation behavior`},
		{["-of"], `Use "targetPath" and "targetName" to customize the output file`},
		{["-debug", "-fdebug", "-g"], "Call dub with --build=debug"},
		{["-release", "-frelease", "-O", "-inline"], "Call dub with --build=release"},
		{["-unittest", "-funittest"], "Call dub with --build=unittest"},
		{["-lib"], `Use {"targetType": "staticLibrary"} or let dub manage this`},
		{["-D"], "Call dub with --build=docs or --build=ddox"},
		{["-X"], "Call dub with --build=ddox"},
		{["-cov"], "Call dub with --build=cov or --build=unittest-cox"},
		{["-profile"], "Call dub with --build=profile"},
		{["-version="], `Use "versions" to specify version constants in a compiler independent way`},
		//{["-debug=", `Use "debugVersions" to specify version constants in a compiler independent way`]},
		{["-I"], `Use "importPaths" to specify import paths in a compiler independent way`},
		{["-J"], `Use "stringImportPaths" to specify import paths in a compiler independent way`},
	];

	bool got_preamble = false;
	void outputPreamble()
	{
		if (got_preamble) return;
		got_preamble = true;
		logWarn("");
		if (config_name.empty) logWarn("## Warning for package %s ##", package_name);
		else logWarn("## Warning for package %s, configuration %s ##", package_name, config_name);
		logWarn("");
		logWarn("The following compiler flags have been specified in the package description");
		logWarn("file. They are handled by DUB and direct use in packages is discouraged.");
		logWarn("Alternatively, you can set the DFLAGS environment variable to pass custom flags");
		logWarn("to the compiler, or use one of the suggestions below:");
		logWarn("");
	}

	foreach (f; compiler_flags) {
		foreach (sf; s_specialFlags) {
			if (sf.flags.canFind!(sff => f == sff || (sff.endsWith("=") && f.startsWith(sff)))) {
				outputPreamble();
				logWarn("%s: %s", f, sf.alternative);
				break;
			}
		}
	}

	if (got_preamble) logWarn("");
}


/**
	Replaces each referenced import library by the appropriate linker flags.

	This function tries to invoke "pkg-config" if possible and falls back to
	direct flag translation if that fails.
*/
void resolveLibs(ref BuildSettings settings)
{
	if (settings.libs.length == 0) return;

	if (settings.targetType == TargetType.library || settings.targetType == TargetType.staticLibrary) {
		logDiagnostic("Ignoring all import libraries for static library build.");
		settings.libs = null;
		version(Windows) settings.sourceFiles = settings.sourceFiles.filter!(f => !f.endsWith(".lib")).array;
	}
	
	try {
		logDiagnostic("Trying to use pkg-config to resolve library flags for %s.", settings.libs);
		auto libflags = execute(["pkg-config", "--libs"] ~ settings.libs.map!(l => "lib"~l)().array());
		enforce(libflags.status == 0, "pkg-config exited with error code "~to!string(libflags.status));
		foreach (f; libflags.output.split()) {
			if (f.startsWith("-Wl,")) settings.addLFlags(f[4 .. $].split(","));
			else settings.addLFlags(f);
		}
	} catch( Exception e ){
		logDiagnostic("pkg-config failed: %s", e.msg);
		logDiagnostic("Falling back to direct -lxyz flags.");
		version(Windows) settings.addSourceFiles(settings.libs.map!(l => l~".lib")().array());
		else settings.addLFlags(settings.libs.map!(l => "-l"~l)().array());
	}
	settings.libs = null;
}


interface Compiler {
	@property string name() const;

	BuildPlatform determinePlatform(ref BuildSettings settings, string compiler_binary, string arch_override = null);

	/// Replaces high level fields with low level fields and converts
	/// dmd flags to compiler-specific flags
	void prepareBuildSettings(ref BuildSettings settings, BuildSetting supported_fields = BuildSetting.all);

	/// Adds the appropriate flag to set a target path
	void setTarget(ref BuildSettings settings, in BuildPlatform platform);

	/// Invokes the underlying linker directly
	void invokeLinker(in BuildSettings settings, in BuildPlatform platform, string[] objects);
}


/// BuildPlatform specific settings, like needed libraries or additional
/// include paths.
struct BuildSettings {
	TargetType targetType;
	string targetPath;
	string targetName;
	string workingDirectory;
	string[] dflags;
	string[] lflags;
	string[] libs;
	string[] sourceFiles;
	string[] copyFiles;
	string[] versions;
	string[] importPaths;
	string[] stringImportPaths;
	string[] preGenerateCommands;
	string[] postGenerateCommands;
	string[] preBuildCommands;
	string[] postBuildCommands;
	BuildRequirements requirements;

	void addDFlags(in string[] value...) { dflags ~= value; }
	void removeDFlags(in string[] value...) { remove(dflags, value); }
	void addLFlags(in string[] value...) { lflags ~= value; }
	void addLibs(in string[] value...) { add(libs, value); }
	void addSourceFiles(in string[] value...) { add(sourceFiles, value); }
	void removeSourceFiles(in string[] value...) { removePaths(sourceFiles, value); }
	void addCopyFiles(in string[] value...) { add(copyFiles, value); }
	void addVersions(in string[] value...) { add(versions, value); }
	void addImportPaths(in string[] value...) { add(importPaths, value); }
	void addStringImportPaths(in string[] value...) { add(stringImportPaths, value); }
	void addPreGenerateCommands(in string[] value...) { add(preGenerateCommands, value, false); }
	void addPostGenerateCommands(in string[] value...) { add(postGenerateCommands, value, false); }
	void addPreBuildCommands(in string[] value...) { add(preBuildCommands, value, false); }
	void addPostBuildCommands(in string[] value...) { add(postBuildCommands, value, false); }
	void addRequirements(in BuildRequirements[] value...) { foreach (v; value) this.requirements |= v; }

	// Adds vals to arr without adding duplicates.
	private void add(ref string[] arr, in string[] vals, bool no_duplicates = true)
	{
		if (!no_duplicates) {
			arr ~= vals;
			return;
		}

		foreach (v; vals) {
			bool found = false;
			foreach (i; 0 .. arr.length)
				if (arr[i] == v) {
					found = true;
					break;
				}
			if (!found) arr ~= v;
		}
	}

	private void removePaths(ref string[] arr, in string[] vals)
	{
		bool matches(string s)
		{
			foreach (p; vals)
				if (Path(s) == Path(p))
					return true;
			return false;
		}
		arr = arr.filter!(s => !matches(s))().array();
	}

	private void remove(ref string[] arr, in string[] vals)
	{
		bool matches(string s)
		{
			foreach (p; vals)
				if (s == p)
					return true;
			return false;
		}
		arr = arr.filter!(s => !matches(s))().array();
	}
}

/// Represents a platform a package can be build upon.
struct BuildPlatform {
	/// e.g. ["posix", "windows"]
	string[] platform;
	/// e.g. ["x86", "x86_64"]
	string[] architecture;
	/// e.g. "dmd"
	string compiler;

	/// Build platforms can be specified via a string specification.
	///
	/// Specifications are build upon the following scheme, where each component
	/// is optional (indicated by []), but the order is obligatory.
	/// "[-platform][-architecture][-compiler]"
	///
	/// So the following strings are valid specifications:
	/// "-windows-x86-dmd"
	/// "-dmd"
	/// "-arm"
	/// "-arm-dmd"
	/// "-windows-dmd"
	///
	/// Params:
	///     specification = The specification being matched. It must be the empty string or start with a dash.  
	///
	/// Returns: 
	///     true if the given specification matches this BuildPlatform, false otherwise. (The empty string matches)
	///
	bool matchesSpecification(const(char)[] specification) const {
		if(specification.empty)
			return true;
		auto splitted=specification.splitter('-');
		assert(!splitted.empty, "No valid platform specification! The leading hyphen is required!");
		splitted.popFront(); // Drop leading empty match.
		enforce(!splitted.empty, "Platform specification if present, must not be empty!");
		if(platform.canFind(splitted.front)) {
			splitted.popFront();
			if(splitted.empty)
			    return true;
		}
		if(architecture.canFind(splitted.front)) {
			splitted.popFront();
			if(splitted.empty)
			    return true;
		}
		if(compiler==splitted.front) {
			splitted.popFront();
			enforce(splitted.empty, "No valid specification! The compiler has to be the last element!");
			return true;
		}
		return false;
	}
	unittest {
		auto platform=BuildPlatform(["posix", "linux"], ["x86_64"], "dmd");
		assert(platform.matchesSpecification("-posix"));
		assert(platform.matchesSpecification("-linux"));
		assert(platform.matchesSpecification("-linux-dmd"));
		assert(platform.matchesSpecification("-linux-x86_64-dmd"));
		assert(platform.matchesSpecification("-x86_64"));
		assert(!platform.matchesSpecification("-windows"));
		assert(!platform.matchesSpecification("-ldc"));
		assert(!platform.matchesSpecification("-windows-dmd"));
	}
}

enum BuildSetting {
	dflags            = 1<<0,
	lflags            = 1<<1,
	libs              = 1<<2,
	sourceFiles       = 1<<3,
	copyFiles         = 1<<4,
	versions          = 1<<5,
	importPaths       = 1<<6,
	stringImportPaths = 1<<7,
	none = 0,
	commandLine = dflags|copyFiles,
	commandLineSeparate = commandLine|lflags,
	all = dflags|lflags|libs|sourceFiles|copyFiles|versions|importPaths|stringImportPaths
}

enum TargetType {
	autodetect,
	none,
	executable,
	library,
	sourceLibrary,
	dynamicLibrary,
	staticLibrary
}

enum BuildRequirements {
	none = 0,                     /// No special requirements
	allowWarnings        = 1<<0,  /// Warnings do not abort compilation
	silenceWarnings      = 1<<1,  /// Don't show warnings
	disallowDeprecations = 1<<2,  /// Using deprecated features aborts compilation
	silenceDeprecations  = 1<<3,  /// Don't show deprecation warnings
	disallowInlining     = 1<<4,  /// Avoid function inlining, even in release builds
	disallowOptimization = 1<<5,  /// Avoid optimizations, even in release builds
	requireBoundsCheck   = 1<<6,  /// Always perform bounds checks
	requireContracts     = 1<<7,  /// Leave assertions and contracts enabled in release builds
	relaxProperties      = 1<<8,  /// DEPRECATED: Do not enforce strict property handling (-property)
	noDefaultFlags       = 1<<9,  /// Do not issue any of the default build flags (e.g. -debug, -w, -property etc.) - use only for development purposes
}

string getTargetFileName(in BuildSettings settings, in BuildPlatform platform)
{
	assert(settings.targetName.length > 0, "No target name set.");
	final switch(settings.targetType){
		case TargetType.autodetect: assert(false, "Configurations must have a concrete target type.");
		case TargetType.none: return null;
		case TargetType.sourceLibrary: return null;
		case TargetType.executable:
			if( platform.platform.canFind("windows") )
				return settings.targetName ~ ".exe";
			else return settings.targetName;
		case TargetType.library:
		case TargetType.staticLibrary:
			if( platform.platform.canFind("windows") )
				return settings.targetName ~ ".lib";
			else return "lib" ~ settings.targetName ~ ".a";
		case TargetType.dynamicLibrary:
			if( platform.platform.canFind("windows") )
				return settings.targetName ~ ".dll";
			else return "lib" ~ settings.targetName ~ ".so";
	}
} 



private {
	Compiler[] s_compilers;
}
