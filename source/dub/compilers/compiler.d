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
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.data.json;
import dub.internal.vibecompat.inet.path;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.process;
import std.path : globMatch;


static this()
{
	registerCompiler(new DmdCompiler);
	registerCompiler(new GdcCompiler);
	registerCompiler(new LdcCompiler);
}


Compiler getCompiler(string name)
{
	foreach (c; s_compilers)
		if (c.name == name)
			return c;

	// try to match names like gdmd or gdc-2.61
	if (name.canFind("dmd")) return getCompiler("dmd");
	if (name.canFind("gdc")) return getCompiler("gdc");
	if (name.canFind("ldc")) return getCompiler("ldc");
			
	throw new Exception("Unknown compiler: "~name);
}

void registerCompiler(Compiler c)
{
	s_compilers ~= c;
}

void warnOnSpecialCompilerFlags(string[] compiler_flags, BuildOptions options, string package_name, string config_name)
{
	struct SpecialFlag {
		string[] flags;
		string alternative;
	}
	static immutable SpecialFlag[] s_specialFlags = [
		{["-c", "-o-"], "Automatically issued by DUB, do not specify in package.json"},
		{["-w", "-Wall", "-Werr"], `Use "buildRequirements" to control warning behavior`},
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
		{["-debug=", `Use "debugVersions" to specify version constants in a compiler independent way`]},
		{["-I"], `Use "importPaths" to specify import paths in a compiler independent way`},
		{["-J"], `Use "stringImportPaths" to specify import paths in a compiler independent way`},
		{["-m32", "-m64"], `Use --arch=x86/--arch=x86_64 to specify the target architecture`}
	];

	struct SpecialOption {
		BuildOptions[] flags;
		string alternative;
	}
	static immutable SpecialOption[] s_specialOptions = [
		{[BuildOptions.debugMode], "Call DUB with --build=debug"},
		{[BuildOptions.releaseMode], "Call DUB with --build=release"},
		{[BuildOptions.coverage], "Call DUB with --build=cov or --build=unittest-cov"},
		{[BuildOptions.debugInfo], "Call DUB with --build=debug"},
		{[BuildOptions.inline], "Call DUB with --build=release"},
		{[BuildOptions.noBoundsCheck], "Call DUB with --build=release-nobounds"},
		{[BuildOptions.optimize], "Call DUB with --build=release"},
		{[BuildOptions.profile], "Call DUB with --build=profile"},
		{[BuildOptions.unittests], "Call DUB with --build=unittest"},
		{[BuildOptions.warnings, BuildOptions.warningsAsErrors], "Use \"buildRequirements\" to control the warning level"},
		{[BuildOptions.ignoreDeprecations, BuildOptions.deprecationWarnings, BuildOptions.deprecationErrors], "Use \"buildRequirements\" to control the deprecation warning level"},
		{[BuildOptions.property], "This flag is deprecated and has no effect"}
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
			if (sf.flags.any!(sff => f == sff || (sff.endsWith("=") && f.startsWith(sff)))) {
				outputPreamble();
				logWarn("%s: %s", f, sf.alternative);
				break;
			}
		}
	}

	foreach (sf; s_specialOptions) {
		foreach (f; sf.flags) {
			if (options & f) {
				outputPreamble();
				logWarn("%s: %s", f, sf.alternative);
				break;
			}
		}
	}

	if (got_preamble) logWarn("");
}


/**
	Alters the build options to comply with the specified build requirements.
*/
void enforceBuildRequirements(ref BuildSettings settings)
{
	settings.addOptions(BuildOptions.warningsAsErrors);
	if (settings.requirements & BuildRequirements.allowWarnings) { settings.options &= ~BuildOptions.warningsAsErrors; settings.options |= BuildOptions.warnings; }
	if (settings.requirements & BuildRequirements.silenceWarnings) settings.options &= ~(BuildOptions.warningsAsErrors|BuildOptions.warnings);
	if (settings.requirements & BuildRequirements.disallowDeprecations) { settings.options &= ~(BuildOptions.ignoreDeprecations|BuildOptions.deprecationWarnings); settings.options |= BuildOptions.deprecationErrors; }
	if (settings.requirements & BuildRequirements.silenceDeprecations) { settings.options &= ~(BuildOptions.deprecationErrors|BuildOptions.deprecationWarnings); settings.options |= BuildOptions.ignoreDeprecations; }
	if (settings.requirements & BuildRequirements.disallowInlining) settings.options &= ~BuildOptions.inline;
	if (settings.requirements & BuildRequirements.disallowOptimization) settings.options &= ~BuildOptions.optimize;
	if (settings.requirements & BuildRequirements.requireBoundsCheck) settings.options &= ~BuildOptions.noBoundsCheck;
	if (settings.requirements & BuildRequirements.requireContracts) settings.options &= ~BuildOptions.releaseMode;
	if (settings.requirements & BuildRequirements.relaxProperties) settings.options &= ~BuildOptions.property;
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
		settings.libs = null;
	} catch (Exception e) {
		logDiagnostic("pkg-config failed: %s", e.msg);
		logDiagnostic("Falling back to direct -lxyz flags.");
	}
}


interface Compiler {
	@property string name() const;

	BuildPlatform determinePlatform(ref BuildSettings settings, string compiler_binary, string arch_override = null);

	/// Replaces high level fields with low level fields and converts
	/// dmd flags to compiler-specific flags
	void prepareBuildSettings(ref BuildSettings settings, BuildSetting supported_fields = BuildSetting.all);

	/// Removes any dflags that match one of the BuildOptions values and populates the BuildSettings.options field.
	void extractBuildOptions(ref BuildSettings settings);

	/// Adds the appropriate flag to set a target path
	void setTarget(ref BuildSettings settings, in BuildPlatform platform);

	/// Invokes the compiler using the given flags
	void invoke(in BuildSettings settings, in BuildPlatform platform, void delegate(int, string) output_callback);

	/// Invokes the underlying linker directly
	void invokeLinker(in BuildSettings settings, in BuildPlatform platform, string[] objects, void delegate(int, string) output_callback);

	protected final void invokeTool(string[] args, void delegate(int, string) output_callback)
	{
		int status;
		if (output_callback) {
			auto result = execute(args);
			output_callback(result.status, result.output);
			status = result.status;
		} else {
			auto compiler_pid = spawnProcess(args);
			status = compiler_pid.wait();
		}
		enforce(status == 0, args[0] ~ " failed with exit code "~to!string(status));
	}
}

/// BuildPlatform specific settings, like needed libraries or additional
/// include paths.
struct BuildSettings {
	TargetType targetType;
	string targetPath;
	string targetName;
	string workingDirectory;
	string mainSourceFile;
	string[] dflags;
	string[] lflags;
	string[] libs;
	string[] sourceFiles;
	string[] copyFiles;
	string[] versions;
	string[] debugVersions;
	string[] importPaths;
	string[] stringImportPaths;
	string[] importFiles;
	string[] stringImportFiles;
	string[] preGenerateCommands;
	string[] postGenerateCommands;
	string[] preBuildCommands;
	string[] postBuildCommands;
	BuildRequirements requirements;
	BuildOptions options;

	BuildSettings dup()
	const {
		BuildSettings ret;
		foreach (m; __traits(allMembers, BuildSettings)) {
			static if (is(typeof(__traits(getMember, ret, m) = __traits(getMember, this, m).dup)))
				__traits(getMember, ret, m) = __traits(getMember, this, m).dup;
			else static if (is(typeof(__traits(getMember, ret, m) = __traits(getMember, this, m))))
				__traits(getMember, ret, m) = __traits(getMember, this, m);
		}
		assert(ret.targetType == targetType);
		assert(ret.targetName == targetName);
		assert(ret.importPaths == importPaths);
		return ret;
	}

	void add(in BuildSettings bs)
	{
		addDFlags(bs.dflags);
		addLFlags(bs.lflags);
		addLibs(bs.libs);
		addSourceFiles(bs.sourceFiles);
		addCopyFiles(bs.copyFiles);
		addVersions(bs.versions);
		addDebugVersions(bs.debugVersions);
		addImportPaths(bs.importPaths);
		addStringImportPaths(bs.stringImportPaths);
		addImportFiles(bs.importFiles);
		addStringImportFiles(bs.stringImportFiles);
		addPreGenerateCommands(bs.preGenerateCommands);
		addPostGenerateCommands(bs.postGenerateCommands);
		addPreBuildCommands(bs.preBuildCommands);
		addPostBuildCommands(bs.postBuildCommands);
	}

	void addDFlags(in string[] value...) { dflags ~= value; }
	void removeDFlags(in string[] value...) { remove(dflags, value); }
	void addLFlags(in string[] value...) { lflags ~= value; }
	void addLibs(in string[] value...) { add(libs, value); }
	void addSourceFiles(in string[] value...) { add(sourceFiles, value); }
	void prependSourceFiles(in string[] value...) { prepend(sourceFiles, value); }
	void removeSourceFiles(in string[] value...) { removePaths(sourceFiles, value); }
	void addCopyFiles(in string[] value...) { add(copyFiles, value); }
	void addVersions(in string[] value...) { add(versions, value); }
	void addDebugVersions(in string[] value...) { add(debugVersions, value); }
	void addImportPaths(in string[] value...) { add(importPaths, value); }
	void addStringImportPaths(in string[] value...) { add(stringImportPaths, value); }
	void prependStringImportPaths(in string[] value...) { prepend(stringImportPaths, value); }
	void addImportFiles(in string[] value...) { add(importFiles, value); }
	void removeImportFiles(in string[] value...) { removePaths(importFiles, value); }
	void addStringImportFiles(in string[] value...) { add(stringImportFiles, value); }
	void addPreGenerateCommands(in string[] value...) { add(preGenerateCommands, value, false); }
	void addPostGenerateCommands(in string[] value...) { add(postGenerateCommands, value, false); }
	void addPreBuildCommands(in string[] value...) { add(preBuildCommands, value, false); }
	void addPostBuildCommands(in string[] value...) { add(postBuildCommands, value, false); }
	void addRequirements(in BuildRequirements[] value...) { foreach (v; value) this.requirements |= v; }
	void addOptions(in BuildOptions[] value...) { foreach (v; value) this.options |= v; }
	void removeOptions(in BuildOptions[] value...) { foreach (v; value) this.options &= ~v; }

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

	private void prepend(ref string[] arr, in string[] vals, bool no_duplicates = true)
	{
		if (!no_duplicates) {
			arr = vals ~ arr;
			return;
		}

		foreach_reverse (v; vals) {
			bool found = false;
			foreach (i; 0 .. arr.length)
				if (arr[i] == v) {
					found = true;
					break;
				}
			if (!found) arr = v ~ arr;
		}
	}

	private void removePaths(ref string[] arr, in string[] vals)
	{
		bool matches(string s)
		{
			foreach (p; vals)
				if (Path(s) == Path(p) || globMatch(s, p))
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
	/// Canonical compiler name e.g. "dmd"
	string compiler;
	/// Compiler binary name e.g. "ldmd2"
	string compilerBinary;

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
		if (specification.empty)
			return true;
		auto splitted=specification.splitter('-');
		assert(!splitted.empty, "No valid platform specification! The leading hyphen is required!");
		splitted.popFront(); // Drop leading empty match.
		enforce(!splitted.empty, "Platform specification if present, must not be empty!");
		if (platform.canFind(splitted.front)) {
			splitted.popFront();
			if(splitted.empty)
			    return true;
		}
		if (architecture.canFind(splitted.front)) {
			splitted.popFront();
			if(splitted.empty)
			    return true;
		}
		if (compiler == splitted.front) {
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
	debugVersions     = 1<<6,
	importPaths       = 1<<7,
	stringImportPaths = 1<<8,
	options           = 1<<9,
	none = 0,
	commandLine = dflags|copyFiles,
	commandLineSeparate = commandLine|lflags,
	all = dflags|lflags|libs|sourceFiles|copyFiles|versions|debugVersions|importPaths|stringImportPaths|options,
	noOptions = all & ~options
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

enum BuildOptions {
	none = 0,                     /// Use compiler defaults
	debugMode = 1<<0,             /// Compile in debug mode (enables contracts, -debug)
	releaseMode = 1<<1,           /// Compile in release mode (disables assertions and bounds checks, -release)
	coverage = 1<<2,              /// Enable code coverage analysis (-cov)
	debugInfo = 1<<3,             /// Enable symbolic debug information (-g)
	debugInfoC = 1<<4,            /// Enable symbolic debug information in C compatible form (-gc)
	alwaysStackFrame = 1<<5,      /// Always generate a stack frame (-gs)
	stackStomping = 1<<6,         /// Perform stack stomping (-gx)
	inline = 1<<7,                /// Perform function inlining (-inline)
	noBoundsCheck = 1<<8,         /// Disable all bounds checking (-noboundscheck)
	optimize = 1<<9,              /// Enable optimizations (-O)
	profile = 1<<10,              /// Emit profiling code (-profile)
	unittests = 1<<11,            /// Compile unit tests (-unittest)
	verbose = 1<<12,              /// Verbose compiler output (-v)
	ignoreUnknownPragmas = 1<<13, /// Ignores unknown pragmas during compilation (-ignore)
	syntaxOnly = 1<<14,           /// Don't generate object files (-o-)
	warnings = 1<<15,             /// Enable warnings (-wi)
	warningsAsErrors = 1<<16,     /// Treat warnings as errors (-w)
	ignoreDeprecations = 1<<17,   /// Do not warn about using deprecated features (-d)
	deprecationWarnings = 1<<18,  /// Warn about using deprecated features (-dw)
	deprecationErrors = 1<<19,    /// Stop compilation upon usage of deprecated features (-de)
	property = 1<<20,             /// DEPRECATED: Enforce property syntax (-property)
}

string getTargetFileName(in BuildSettings settings, in BuildPlatform platform)
{
	assert(settings.targetName.length > 0, "No target name set.");
	final switch (settings.targetType) {
		case TargetType.autodetect: assert(false, "Configurations must have a concrete target type.");
		case TargetType.none: return null;
		case TargetType.sourceLibrary: return null;
		case TargetType.executable:
			if( platform.platform.canFind("windows") )
				return settings.targetName ~ ".exe";
			else return settings.targetName;
		case TargetType.library:
		case TargetType.staticLibrary:
			if (platform.platform.canFind("windows") && platform.compiler == "dmd")
				return settings.targetName ~ ".lib";
			else return "lib" ~ settings.targetName ~ ".a";
		case TargetType.dynamicLibrary:
			if( platform.platform.canFind("windows") )
				return settings.targetName ~ ".dll";
			else return "lib" ~ settings.targetName ~ ".so";
	}
} 


bool isLinkerFile(string f)
{
	import std.path;
	switch (extension(f)) {
		default:
			return false;
		version (Windows) {
			case ".lib", ".obj", ".res":
				return true;
		} else {
			case ".a", ".o", ".so", ".dylib":
				return true;
		}
	}
}

private {
	Compiler[] s_compilers;
}
