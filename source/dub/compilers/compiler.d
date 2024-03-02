/**
	Compiler settings and abstraction.

	Copyright: © 2013-2016 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.compilers.compiler;

public import dub.compilers.buildsettings;
deprecated("Please `import dub.dependency : Dependency` instead") public import dub.dependency : Dependency;
public import dub.platform : BuildPlatform, matchesSpecification;

import dub.internal.vibecompat.inet.path;
import dub.internal.vibecompat.core.file;

import dub.internal.logging;

import std.algorithm;
import std.array;
import std.exception;
import std.process;

/// Exception thrown in Compiler.determinePlatform if the given architecture is
/// not supported.
class UnsupportedArchitectureException : Exception
{
	this(string architecture, string file = __FILE__, size_t line = __LINE__, Throwable nextInChain = null) pure nothrow @safe
	{
		super("Unsupported architecture: "~architecture, file, line, nextInChain);
	}
}

/// Exception thrown in getCompiler if no compiler matches the given name.
class UnknownCompilerException : Exception
{
	this(string compilerName, string file = __FILE__, size_t line = __LINE__, Throwable nextInChain = null) pure nothrow @safe
	{
		super("Unknown compiler: "~compilerName, file, line, nextInChain);
	}
}

/// Exception thrown in invokeTool and probePlatform if running the compiler
/// returned non-zero exit code.
class CompilerInvocationException : Exception
{
	this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable nextInChain = null) pure nothrow @safe
	{
		super(msg, file, line, nextInChain);
	}
}

/** Returns a compiler handler for a given binary name.

	The name will be compared against the canonical name of each registered
	compiler handler. If no match is found, the sub strings "dmd", "gdc" and
	"ldc", in this order, will be searched within the name. If this doesn't
	yield a match either, an $(LREF UnknownCompilerException) will be thrown.
*/
Compiler getCompiler(string name)
{
	foreach (c; s_compilers)
		if (c.name == name)
			return c;

	// try to match names like gdmd or gdc-2.61
	if (name.canFind("dmd")) return getCompiler("dmd");
	if (name.canFind("gdc")) return getCompiler("gdc");
	if (name.canFind("ldc")) return getCompiler("ldc");

	throw new UnknownCompilerException(name);
}

/** Registers a new compiler handler.

	Note that by default `DMDCompiler`, `GDCCompiler` and `LDCCompiler` are
	already registered at startup.
*/
void registerCompiler(Compiler c)
{
	s_compilers ~= c;
}


interface Compiler {
	/// Returns the canonical name of the compiler (e.g. "dmd").
	@property string name() const;

	/** Determines the build platform properties given a set of build settings.

		This will invoke the compiler to build a platform probe file, which
		determines the target build platform's properties during compile-time.

		See_Also: `dub.compilers.utils.generatePlatformProbeFile`
	*/
	BuildPlatform determinePlatform(ref BuildSettings settings, string compiler_binary, string arch_override = null);

	/// Replaces high level fields with low level fields and converts
	/// dmd flags to compiler-specific flags
	void prepareBuildSettings(ref BuildSettings settings, const scope ref BuildPlatform platform, BuildSetting supported_fields = BuildSetting.all) const;

	/// Removes any dflags that match one of the BuildOptions values and populates the BuildSettings.options field.
	void extractBuildOptions(ref BuildSettings settings) const;

	/// Computes the full file name of the generated binary.
	string getTargetFileName(in BuildSettings settings, in BuildPlatform platform) const;

	/// Adds the appropriate flag to set a target path
	void setTarget(ref BuildSettings settings, in BuildPlatform platform, string targetPath = null) const;

	/// Invokes the compiler using the given flags
	deprecated("specify the working directory")
	final void invoke(in BuildSettings settings, in BuildPlatform platform, void delegate(int, string) output_callback)
	{
		invoke(settings, platform, output_callback, getWorkingDirectory());
	}

	/// ditto
	void invoke(in BuildSettings settings, in BuildPlatform platform, void delegate(int, string) output_callback, NativePath cwd);

	/// Invokes the underlying linker directly
	deprecated("specify the working directory")
	final void invokeLinker(in BuildSettings settings, in BuildPlatform platform, string[] objects, void delegate(int, string) output_callback)
	{
		invokeLinker(settings, platform, objects, output_callback, getWorkingDirectory());
	}

	/// ditto
	void invokeLinker(in BuildSettings settings, in BuildPlatform platform, string[] objects, void delegate(int, string) output_callback, NativePath cwd);

	/// Convert linker flags to compiler format
	string[] lflagsToDFlags(const string[] lflags) const;

	/// Determines compiler version
	string determineVersion(string compiler_binary, string verboseOutput);

	/** Runs a tool and provides common boilerplate code.

		This method should be used by `Compiler` implementations to invoke the
		compiler or linker binary.
	*/
	deprecated("specify the working directory")
	protected final void invokeTool(string[] args, void delegate(int, string) output_callback, string[string] env = null)
	{
		invokeTool(args, output_callback, getWorkingDirectory(), env);
	}

	/// ditto
	protected final void invokeTool(string[] args, void delegate(int, string) output_callback, NativePath cwd, string[string] env = null)
	{
		import std.string;

		int status;
		if (output_callback) {
			auto result = execute(args,
				env, Config.none, size_t.max, cwd.toNativeString());
			output_callback(result.status, result.output);
			status = result.status;
		} else {
			auto compiler_pid = spawnProcess(args,
				env, Config.none, cwd.toNativeString());
			status = compiler_pid.wait();
		}

		version (Posix) if (status == -9) {
			throw new CompilerInvocationException(
				format("%s failed with exit code %s. This may indicate that the process has run out of memory.",
					args[0], status));
		}
		enforce!CompilerInvocationException(status == 0,
			format("%s failed with exit code %s.", args[0], status));
	}

	/** Compiles platform probe file with the specified compiler and parses its output.
		Params:
			compiler_binary =	binary to invoke compiler with
			args			=	arguments for the probe compilation
			arch_override	=	special handler for x86_mscoff
	*/
	protected final BuildPlatform probePlatform(string compiler_binary, string[] args, string arch_override)
	{
		import dub.compilers.utils : generatePlatformProbeFile, readPlatformSDLProbe;
		import std.string : format, strip;

		NativePath fil = generatePlatformProbeFile();

		auto result = execute(compiler_binary ~ args ~ fil.toNativeString());
		enforce!CompilerInvocationException(result.status == 0,
				format("Failed to invoke the compiler %s to determine the build platform: %s",
				compiler_binary, result.output));
		BuildPlatform build_platform = readPlatformSDLProbe(result.output);
		string ver = determineVersion(compiler_binary, result.output).strip;
		build_platform.compilerBinary = compiler_binary;

		if (ver.empty) {
			logWarn(`Could not probe the compiler version for "%s". ` ~
				`Toolchain requirements might be ineffective`, build_platform.compiler);
		}
		else {
			build_platform.compilerVersion = ver;
		}

		// Skip the following check for LDC, emitting a warning if the specified `-arch`
		// cmdline option does not lead to the same string being found among
		// `build_platform.architecture`, as it's brittle and doesn't work with triples.
		if (build_platform.compiler != "ldc") {
			if (arch_override.length && !build_platform.architecture.canFind(arch_override) &&
				!(build_platform.compiler == "dmd" && arch_override.among("x86_omf", "x86_mscoff")) // Will be fixed in determinePlatform
			) {
				logWarn(`Failed to apply the selected architecture %s. Got %s.`,
					arch_override, build_platform.architecture);
			}
		}

		return build_platform;
	}
}

private {
	Compiler[] s_compilers;
}
