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
import dub.internal.buildtimings;

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
	string determineVersion(in BuildPlatform platform, string verboseOutput);

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
		if (s_invocationTiming !is null) {
			status = invokeTimedTool(args, output_callback, cwd, env);
		} else if (output_callback) {
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

	/** Default compiler arguments for performing a probe. They should
		be the D compiler equivalent of "don't output executables"
	*/
	protected string[] defaultProbeArgs() const;

	/** Compiles platform probe file with the specified compiler and parses its output.
		Params:
			compiler_binary =	binary to invoke compiler with
			arch_flags      =   compiler specific flags derived from the user's arch override
	*/
	protected final BuildPlatform probePlatform(string compiler_binary, string[] arch_flags)
	{
		import dub.compilers.utils : generatePlatformProbeFile, readPlatformSDLProbe;
		import std.string : format, strip;

		immutable fileArg = generatePlatformProbeFile().toNativeString;

		auto result = execute(compiler_binary ~ defaultProbeArgs ~ arch_flags ~ fileArg);
		enforce!CompilerInvocationException(result.status == 0,
				format("Failed to invoke the compiler %s to determine the build platform: %s",
				compiler_binary, result.output));
		BuildPlatform build_platform = readPlatformSDLProbe(result.output);
		build_platform.compilerBinary = compiler_binary;
		string ver = determineVersion(build_platform, result.output).strip;

		if (ver.empty) {
			logWarn(`Could not probe the compiler version for "%s". ` ~
				`Toolchain requirements might be ineffective`, build_platform.compiler);
		}
		else {
			build_platform.compilerVersion = ver;
		}

		return build_platform;
	}

}

private {
	Compiler[] s_compilers;

	struct InvocationTiming {
		BuildTimingCollector collector;
		BuildTimingContext context;
	}
	// D module variables are thread-local: parallel compiler jobs never share
	// the active context. Compiler instances themselves may be shared.
	InvocationTiming* s_invocationTiming;
}

// Keep the disabled path in invokeTool identical to ordinary process execution,
// apart from the context check. No clocks, TLS writes, or timing cleanup there.
private int invokeTimedTool(string[] args, void delegate(int, string) output_callback,
	NativePath cwd, string[string] env)
{
	import core.time : MonoTime;
	import std.typecons : Nullable;

	// A reentrant invocation from an output callback must not inherit this context.
	auto timing = s_invocationTiming;
	s_invocationTiming = null;
	scope (exit) s_invocationTiming = timing;

	int status;
	string output;
	auto nativeCwd = cwd.toNativeString();
	{
		Nullable!int exitStatus;
		auto start = MonoTime.currTime;
		// Also record launch/wait failures, for which no exit status is known.
		scope (exit)
			timing.collector.record(timing.context, start, MonoTime.currTime, exitStatus);
		if (output_callback) {
			auto result = execute(args, env, Config.none, size_t.max, nativeCwd);
			status = result.status;
			output = result.output;
		} else {
			auto compiler_pid = spawnProcess(args, env, Config.none, nativeCwd);
			status = compiler_pid.wait();
		}
		exitStatus = status;
	}
	if (output_callback) output_callback(status, output);
	return status;
}

/** Attach timing context to a synchronous compiler invocation without changing
	Compiler's extension interface. Implementations using invokeTool participate;
	implementations launching their own processes do not. Restore context on
	normal return and failure, including nested invocations.
*/
package(dub) void withCompilerTiming(BuildTimingCollector collector,
	BuildTimingContext context, scope void delegate() invoke)
{
	auto previous = s_invocationTiming;
	s_invocationTiming = collector is null ? null : new InvocationTiming(collector, context);
	scope (exit) s_invocationTiming = previous;
	invoke();
}

unittest {
	import dub.compilers.dmd : DMDCompiler;
	import std.exception : assertThrown;
	import std.string : strip;

	static class TestCompiler : DMDCompiler {
		void run(string[] args, void delegate(int, string) callback = null) {
			invokeTool(args, callback, getWorkingDirectory());
		}
	}
	version (Windows) {
		auto shell = [environment.get("COMSPEC", "cmd.exe"), "/d", "/c"];
		auto success = shell ~ "echo timing-test";
		auto failure = shell ~ "exit /b 7";
	} else {
		auto success = ["/bin/sh", "-c", "echo timing-test"];
		auto failure = ["/bin/sh", "-c", "exit 7"];
	}
	auto compiler = new TestCompiler;
	auto collector = new BuildTimingCollector;
	auto context = BuildTimingContext(BuildTimingPhase.compile, "example", ["source/app.d"]);

	bool called;
	withCompilerTiming(collector, context, {
		compiler.run(success, (status, output) {
			called = true;
			assert(status == 0 && output.strip == "timing-test");
			// Collection must finish before the callback, not when it returns.
			auto records = collector.snapshot();
			assert(records.length == 1 && records[0].exitStatus.get == 0);
			assert(records[0].context == context);
			// Reentrant, untimed calls must not acquire the outer context.
			assertThrown!CompilerInvocationException(
				compiler.run(failure, (status, output) { assert(status == 7); }));
		});
	});
	assert(called && collector.snapshot().length == 1);
	assert(s_invocationTiming is null);

	// Both inherited-output and captured-output paths record nonzero exits.
	foreach (capture; [false, true]) {
		auto failures = new BuildTimingCollector;
		void delegate(int, string) callback;
		if (capture) callback = (status, output) { assert(status == 7); };
		assertThrown!CompilerInvocationException(withCompilerTiming(failures, context, {
			compiler.run(failure, callback);
		}));
		assert(failures.snapshot().length == 1);
		assert(failures.snapshot()[0].exitStatus.get == 7);
		assert(s_invocationTiming is null);

		auto launches = new BuildTimingCollector;
		assertThrown!ProcessException(withCompilerTiming(launches, context, {
			compiler.run(["dub-timing-test-missing-directory/no-such-compiler"], callback);
		}));
		assert(launches.snapshot().length == 1);
		assert(launches.snapshot()[0].exitStatus.isNull);
		assert(s_invocationTiming is null);
	}

	// A callback exception must not erase or duplicate the completed record.
	auto callbackError = new Exception("callback failure");
	try {
		withCompilerTiming(collector, context, {
			compiler.run(success, (status, output) { throw callbackError; });
		});
		assert(false);
	} catch (Exception e) {
		assert(e is callbackError);
	}
	assert(collector.snapshot().length == 2);
	assert(collector.snapshot()[1].exitStatus.get == 0);
	assert(s_invocationTiming is null);

	// Nested timing scopes restore the outer context even after an exception.
	auto inner = new BuildTimingCollector;
	auto innerContext = BuildTimingContext(BuildTimingPhase.link, "inner", []);
	withCompilerTiming(collector, context, {
		assertThrown!CompilerInvocationException(withCompilerTiming(inner, innerContext, {
			compiler.run(failure);
		}));
		compiler.run(success, (status, output) {});
	});
	assert(inner.snapshot().length == 1);
	assert(inner.snapshot()[0].context == innerContext);
	assert(collector.snapshot().length == 3);
	assert(collector.snapshot()[2].context == context);
	compiler.run(success, (status, output) {});
	assert(collector.snapshot().length == 3);
}

/// Adds the given flags to the build settings if desired, otherwise informs the user
package void maybeAddArchFlags(ref BuildSettings settings, bool keep_arch, string[] arch_flags, string arch_override) {
	if (keep_arch)
		settings.addDFlags(arch_flags);
	else if (arch_override.length) {
		logDebug("Ignoring arch_override '%s' for better caching because it doesn't affect the build", arch_override);
	}
}
