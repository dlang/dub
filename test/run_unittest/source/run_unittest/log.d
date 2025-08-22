module run_unittest.log;

import std.conv;
import std.format;
import std.stdio;

enum Severity {
	Info,
	Warning,
	Error,
	Status,
}

string getName(Severity severity) {
	final switch (severity) {
		case Severity.Warning:
			return "WARN";
		case Severity.Info:
			return "INFO";
		case Severity.Error:
			return "ERROR";
		case Severity.Status:
			return "STAT";
	}
}

abstract class ErrorSink {
	void info (const(char)[] msg) {
		log(Severity.Info, msg);
	}
	void warn (const(char)[] msg) {
		log(Severity.Warning, msg);
	}
	void error (const(char)[] msg) {
		log(Severity.Error, msg);
	}
	void status (const(char)[] msg) {
		log(Severity.Status, msg);
	}

	void info (Args...) (Args args) {
		log(Severity.Info, text(args));
	}
	void warn (Args...) (Args args) {
		log(Severity.Warning, text(args));
	}
	void error (Args...) (Args args) {
		log(Severity.Error, text(args));
	}
	void status (Args...) (Args args) {
		log(Severity.Status, text(args));
	}

	abstract void log(Severity severity, const(char)[] msg);
	void log (Args...) (Severity severity, Args args) {
		log(severity, text(args));
	}
}

class ConsoleSink : ErrorSink {
	this(bool useColor) {
		this.useColor = useColor;
	}

	override void log (Severity severity, const(char)[] msg) {
		immutable preamble = severity.getName;
		immutable color = getColor(severity);

		immutable colorBegin = useColor ? "\033[0;" ~ color ~ "m" : "";
		immutable colorEnd = useColor ? "\033[0;m" : "";
		immutable str = format("%s[%5s]:%s %s", colorBegin, preamble, colorEnd, msg);

		stderr.writeln(str);
		stderr.flush();
	}

private:
	bool useColor;

	enum AnsiColor {
		Red = "31",
		Green = "32",
		Yellow = "33",
	}

	string getColor(Severity severity) {
		final switch (severity) {
			case Severity.Warning:
				return AnsiColor.Yellow;
			case Severity.Info:
				return AnsiColor.Green;
			case Severity.Error:
				return AnsiColor.Red;
			case Severity.Status:
				return AnsiColor.Green;
		}
	}
}

class FileSink : ErrorSink {
	this(string logFile) {
		this.logFile = File(logFile, "w");
	}

	override void log (Severity severity, const(char)[] msg) {
		immutable preamble = severity.getName;
		immutable str = format("[%5s]: %s", preamble, msg);
		logFile.writeln(str);
	}

private:
	File logFile;
}

class GroupSink : ErrorSink {
	this (ErrorSink[] sinks...) {
		this.sinks = sinks.dup;
	}

	override void log (Severity severity, const(char)[] msg) {
		foreach (sink; sinks)
			sink.log(severity, msg);
	}

private:
	ErrorSink[] sinks;
}

class TestCaseSink : ErrorSink {
	ErrorSink proxy;
	string tc;
	this(ErrorSink proxy, string testCase) {
		this.proxy = proxy;
		tc = testCase;
	}

	override void log(Severity severity, const(char)[] msg) {
		proxy.log(severity, tc, ": ", msg);
	}
}

class CaptureErrorSink : ErrorSink {
	const(char)[][][Severity] capturedMessages;

	override void log (Severity severity, const(char)[] msg) {
		capturedMessages[severity] ~= msg;
	}

	override string toString() const {
		import std.conv;
		return text(capturedMessages);
	}

	bool empty() {
		int result = 0;
		foreach (value; capturedMessages)
			result += value.length;
		return result == 0;
	}
	void clear() {
		foreach (ref value; capturedMessages) value = [];
	}

	const(char)[][] errors () {
		return capturedMessages[Severity.Error];
	}
	const(char)[] errorsBlock () {
		return block(Severity.Error);
	}
	const(char)[] warningsBlock () {
		return block(Severity.Warning);
	}
	const(char)[] infosBlock () {
		return block(Severity.Info);
	}
	const(char)[] statusBlock () {
		return block(Severity.Status);
	}

private:
	const(char)[] block(Severity severity) {
		import std.array;
		return capturedMessages.get(severity, []).join(" ");
	}
}

class NonVerboseSink : ErrorSink {
	public ErrorSink sink;
	this(ErrorSink sink) {
		this.sink = sink;
	}

	override void log(Severity severity, const(char)[] msg) {
		if (severity == Severity.Info) return;
		sink.log(severity, msg);
	}
}
