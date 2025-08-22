module common;

import core.stdc.stdio;
import std.parallelism;
import std.process;
import std.stdio : File;
import std.string;

void log (const(char)[][] args...) {
	printImpl("INFO", args);
}

void logError (const(char)[][] args...) {
	printImpl("ERROR", args);
}

void die (const(char)[][] args...) {
	printImpl("FAIL", args);
	throw new Exception("test failed");
}

void skip (const(char)[][] args...) {
	printImpl("SKIP", args);
	throw new Exception("test skipped");
}

version(Posix)
immutable DotExe = "";
else
immutable DotExe = ".exe";

immutable string dub;
immutable string dubHome;

shared static this() {
	import std.file;
	import std.path;
	dub = environment["DUB"];
	dubHome = getcwd.buildPath("dub");
	environment["DUB_HOME"] = dubHome;
}

struct ProcessT {
	string stdout(){
		if (stdoutTask is null)
			throw new Exception("Trying to access stdout but it wasn't redirected");
		return stdoutTask.yieldForce;
	}
	string stderr(){
		if (stderrTask is null)
			throw new Exception("Trying to access stderr but it wasn't redirected");
		return stderrTask.yieldForce;
	}
	string[] stdoutLines() {
		return stdout.splitLines();
	}
	string[] stderrLines() {
		return stderr.splitLines();
	}
	File stdin() { return p.stdin; }

	int wait() {
		return p.pid.wait;
	}

	Pid pid() { return p.pid; }

	this(ProcessPipes p, Redirect redirect, bool quiet = false) {
		this.p = p;
		this.redirect = redirect;
		this.quiet = quiet;

		if (redirect & Redirect.stdout) {
			this.stdoutTask = task!linesImpl(p.stdout, quiet);
			this.stdoutTask.executeInNewThread();
		}
		if (redirect & Redirect.stderr) {
			this.stderrTask = task!linesImpl(p.stderr, quiet);
			this.stderrTask.executeInNewThread();
		}
	}

	~this() {
		if (stdoutTask)
			stdoutTask.yieldForce;
		if (stderrTask)
			stderrTask.yieldForce;
	}

	ProcessPipes p;
private:
	Task!(linesImpl, File, bool)* stdoutTask;
	Task!(linesImpl, File, bool)* stderrTask;

	Redirect redirect;
	bool quiet;
	bool stdoutDone;
	bool stderrDone;

	static string linesImpl(File file, bool quiet) {
		import std.typecons;

		string result;
		foreach (line; file.byLine(Yes.keepTerminator)) {
			if (!quiet)
				log(line.chomp);
			result ~= line;
		}
		file.close();
		return result;
	}
}

ProcessT teeProcess(
	const string[] args,
	Redirect redirect = Redirect.all,
	const string[string] env = null,
	Config config = Config.none,
	const char[] workDir = null,
) {
	return ProcessT(pipeProcess(args, redirect, env, config, workDir), redirect);
}

ProcessT teeProcessQuiet(
	const string[] args,
	Redirect redirect = Redirect.all,
	const string[string] env = null,
	Config config = Config.none,
	const char[] workDir = null,
) {
	return ProcessT(pipeProcess(args, redirect, env, config, workDir), redirect, true);
}

private:

void printImpl (string header, const(char)[][] args...) {
	printf("[%.*s]: ", cast(int)header.length, header.ptr);
	foreach (arg; args)
		printf("%.*s", cast(int)arg.length, arg.ptr);
	fputc('\n', stdout);
	fflush(stdout);
}
