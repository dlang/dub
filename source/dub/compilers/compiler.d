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

import core.time : Duration, dur;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.inet.path;

import std.algorithm;
import std.array;
import std.exception;
import std.process;


/** Returns a compiler handler for a given binary name.

	The name will be compared against the canonical name of each registered
	compiler handler. If no match is found, the sub strings "dmd", "gdc" and
	"ldc", in this order, will be searched within the name. If this doesn't
	yield a match either, an exception will be thrown.
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

	throw new Exception("Unknown compiler: "~name);
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
	void invoke(in BuildSettings settings, in BuildPlatform platform, void delegate(int, string) output_callback);

	/// Invokes the underlying linker directly
	void invokeLinker(in BuildSettings settings, in BuildPlatform platform, string[] objects, void delegate(int, string) output_callback);

	/// Convert linker flags to compiler format
	string[] lflagsToDFlags(in string[] lflags) const;

	/// Determines compiler version
	string determineVersion(string compiler_binary, string verboseOutput);

	/** Runs a tool and provides common boilerplate code.

		This method should be used by `Compiler` implementations to invoke the
		compiler or linker binary.
	*/
	protected final void invokeTool(string[] args, void delegate(int, string) output_callback, string[string] env = null, Duration timeout = Duration.max)
	{
		import std.string;

		string[] timeouted(string[] args) @safe pure
		{
			if (timeout)
			{
				import std.conv : to;
				return ["timeout", timeout.total!"seconds".to!string] ~ args;
			}
			return args;
		}

		int status;
		if (output_callback) {
			auto result = executeShell(escapeShellCommand(timeouted(args)), env); // TODO: avoid using timeoutArgs
			output_callback(result.status, result.output);
			status = result.status;
		} else {
			auto compiler_pid = spawnShell(escapeShellCommand(args), env);
			if (timeout)
			{
				version (Windows)
				{
					import std.process : waitTimeout;
					const result = waitTimeout(compiler_pid, timeout);
					if (result.terminated)
						status = res.status;
					else
						status = timeoutExitStatus;
				}
			    else
				{
					import std.datetime : Clock;
					const start = Clock.currTime;
					while (1)
					{
						if (Clock.currTime - start >= timeout)
						{
							status = timeoutExitStatus;
							break;
						}
						import std.process : tryWait;
						auto result = tryWait(compiler_pid);
						if (result.terminated)
						{
							status = result.status;
							break;
						}
						import core.thread : Thread;
						Thread.sleep(dur!"msecs"(1));
					}
				}
			}
			else
				status = compiler_pid.wait();
		}

		version (Posix) if (status == -9) {
			throw new Exception(format("%s failed with exit code %s. This may indicate that the process has run out of memory.",
				args[0], status));
		}
		enforce(status == 0, format("%s failed with exit code %s.", args[0], status));
	}

	/** Compiles platform probe file with the specified compiler and parses its output.
		Params:
			compiler_binary =	binary to invoke compiler with
			args			=	arguments for the probe compilation
			arch_override	=	special handler for x86_mscoff
	*/
	protected final BuildPlatform probePlatform(string compiler_binary, string[] args,
		string arch_override)
	{
		import dub.compilers.utils : generatePlatformProbeFile, readPlatformJsonProbe;
		import std.string : format, strip;

		auto fil = generatePlatformProbeFile();

		auto result = executeShell(escapeShellCommand(compiler_binary ~ args ~ fil.toNativeString()));
		enforce(result.status == 0, format("Failed to invoke the compiler %s to determine the build platform: %s",
				compiler_binary, result.output));

		auto build_platform = readPlatformJsonProbe(result.output);
		build_platform.compilerBinary = compiler_binary;

		auto ver = determineVersion(compiler_binary, result.output)
			.strip;
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
			if (arch_override.length && !build_platform.architecture.canFind(arch_override)) {
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
