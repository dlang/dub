/**
	Collection of compiler invocation timings for a single build.

	License: Subject to the terms of the MIT license, as written in LICENSE.txt.
*/
module dub.internal.buildtimings;

import core.sync.mutex : Mutex;
import core.time : Duration, MonoTime;
import std.exception : enforce;
import std.typecons : Nullable;

package(dub):

/// The work performed by an invocation, not the name of its executable.
enum BuildTimingPhase {
	compile,
	link,
	compileAndLink,
}

/// Context supplied by the build generator before launching a tool.
struct BuildTimingContext {
	BuildTimingPhase phase;
	/// Package owning the target; combined targets may contain other packages.
	string targetPackage;
	/// Explicit source inputs, not every module transitively imported by them.
	/// Immutable storage allows records and snapshots to share it safely.
	immutable(string[]) sourceFiles;
}

/// One completed invocation, including unsuccessful invocations.
struct BuildTimingRecord {
	BuildTimingContext context;
	/// Monotonic offsets relative to the collector's creation.
	Duration startOffset;
	Duration endOffset;
	/// Null when the process could not be launched or no exit status was obtained.
	Nullable!int exitStatus;

	@property Duration elapsed() const pure nothrow @safe {
		return endOffset - startOffset;
	}
}

/**
	Own one collector per build and share it with compilation workers.

	Callers take timestamps immediately around process execution, inside the
	worker, and submit the record even on failure. The collector deliberately
	accepts timestamps rather than timing submission: queueing and collector
	lock contention must not contribute to the invocation's elapsed time.

	Records are retained in submission order, which is not necessarily launch
	or completion order. Reporting can order snapshot indices without holding the lock.
*/
final class BuildTimingCollector {
	private immutable MonoTime m_origin;
	private Mutex m_mutex;
	private BuildTimingRecord[] m_records;

	this() {
		m_origin = MonoTime.currTime;
		m_mutex = new Mutex;
	}

	void record(BuildTimingContext context, MonoTime start, MonoTime end,
		Nullable!int exitStatus = Nullable!int.init)
	{
		enforce(start >= m_origin, "Invocation starts before the build timing origin.");
		enforce(end >= start, "Invocation ends before it starts.");
		auto entry = BuildTimingRecord(context, start - m_origin, end - m_origin, exitStatus);
		synchronized (m_mutex) {
			m_records ~= entry;
		}
	}

	/// Independent array; callers can inspect it without holding the collection lock.
	BuildTimingRecord[] snapshot() {
		synchronized (m_mutex) {
			return m_records.dup;
		}
	}
}

/// A reporting error must not replace the original build exception.
void printBuildTimings(BuildTimingCollector collector, Duration buildElapsed, bool completed)
{
	import std.stdio : stderr;
	import dub.internal.logging : logWarn;
	try {
		stderr.write(formatBuildTimings(collector.snapshot(), buildElapsed, completed));
		stderr.flush();
	} catch (Exception e) {
		logWarn("Could not print build timings: %s", e.msg);
	}
}

/// Format a snapshot without changing its records or their submission order.
string formatBuildTimings(in BuildTimingRecord[] records, Duration buildElapsed, bool completed)
{
	import std.algorithm : sort;
	import std.array : appender, array, join;
	import std.format : formattedWrite;
	import std.range : iota;
	import std.conv : to;

	auto result = appender!string;
	formattedWrite(result, "Build timings (%s)\n", completed ? "completed" : "partial; build failed");
	if (!records.length) {
		result.put("  No compiler or linker invocations were recorded.");
		if (completed) result.put(" Targets may be up to date; use --force to rebuild.");
		result.put("\n");
	} else {
		result.put("  Elapsed ms    Start ms      End ms  Status       Phase         Target / sources\n");
		// Records contain immutable source lists. Sort indices rather than moving
		// records, and break equal-duration ties by submission index.
		auto order = iota(records.length).array;
		order.sort!((a, b) => records[a].elapsed == records[b].elapsed
			? a < b : records[a].elapsed > records[b].elapsed);
		foreach (i; order) {
			auto entry = records[i];
			string phase;
			final switch (entry.context.phase) {
			case BuildTimingPhase.compile: phase = "compile"; break;
			case BuildTimingPhase.link: phase = "link"; break;
			case BuildTimingPhase.compileAndLink: phase = "compile+link"; break;
			}
			auto status = entry.exitStatus.isNull ? "no status"
				: entry.exitStatus.get == 0 ? "ok" : "exit " ~ to!string(entry.exitStatus.get);
			formattedWrite(result, "  %10.3f  %10.3f  %10.3f  %-12s %-13s %s",
				entry.elapsed.total!"nsecs" / 1e6, entry.startOffset.total!"nsecs" / 1e6,
				entry.endOffset.total!"nsecs" / 1e6, status, phase, entry.context.targetPackage);
			if (entry.context.sourceFiles.length)
				formattedWrite(result, " / %s", entry.context.sourceFiles.join(", "));
			result.put("\n");
		}
	}
	Duration total;
	foreach (entry; records) total += entry.elapsed;
	formattedWrite(result, "  Summed invocation time: %.3f ms (%s invocation%s; parallel jobs overlap).\n",
		total.total!"nsecs" / 1e6, records.length, records.length == 1 ? "" : "s");
	formattedWrite(result, "  Build stage elapsed: %.3f ms (excludes application/test execution).\n",
		buildElapsed.total!"nsecs" / 1e6);
	result.put("  Start/end offsets are relative to timing collection start; rows are slowest first.\n");
	return result.data;
}

unittest {
	import core.time : msecs;
	import std.algorithm : canFind;
	import std.string : indexOf;

	auto compile = BuildTimingContext(BuildTimingPhase.compile, "root", ["a.d", "b.d"]);
	auto link = BuildTimingContext(BuildTimingPhase.link, "root", []);
	auto combined = BuildTimingContext(BuildTimingPhase.compileAndLink, "dependency", ["dep.d"]);
	auto records = [
		BuildTimingRecord(compile, 0.msecs, 20.msecs, Nullable!int(0)),
		BuildTimingRecord(link, 20.msecs, 25.msecs, Nullable!int(7)),
		BuildTimingRecord(combined, 0.msecs, 30.msecs, Nullable!int.init),
	];
	auto report = formatBuildTimings(records, 35.msecs, false);
	assert(report.canFind("partial; build failed"));
	assert(report.canFind("exit 7") && report.canFind("no status"));
	assert(report.canFind("compile+link") && report.canFind("root / a.d, b.d"));
	assert(report.indexOf("dependency / dep.d") < report.indexOf("root / a.d, b.d"));
	assert(report.canFind("Summed invocation time: 55.000 ms (3 invocations"));
	assert(report.canFind("Build stage elapsed: 35.000 ms"));
	assert(records[0].context == compile);
	assert(formatBuildTimings([], 0.msecs, true).canFind("use --force"));
	assert(!formatBuildTimings([], 0.msecs, false).canFind("use --force"));
}

unittest {
	import std.exception : assertThrown;

	auto before = MonoTime.currTime;
	auto collector = new BuildTimingCollector;
	assert(collector.snapshot().length == 0);
	auto start = MonoTime.currTime;
	auto end = MonoTime.currTime;
	auto context = BuildTimingContext(BuildTimingPhase.compile, "example", ["source/app.d"]);
	collector.record(context, start, end, Nullable!int(0));
	auto records = collector.snapshot();
	assert(records.length == 1);
	assert(records[0].context == context);
	assert(records[0].startOffset >= Duration.zero);
	assert(records[0].startOffset <= start - before);
	// Each offset is converted separately to Duration's 100 ns precision.
	// Their difference can round differently from converting end - start.
	auto roundingError = (records[0].elapsed - (end - start)).total!"hnsecs";
	assert(roundingError >= -1 && roundingError <= 1);
	assert(records[0].exitStatus.get == 0);

	// Nonzero status and missing status are distinct from successful execution.
	collector.record(context, end, end, Nullable!int(7));
	collector.record(context, end, end);
	assert(records.length == 1);
	records[0].context.targetPackage = "changed";
	records[0].exitStatus = 42;
	auto latest = collector.snapshot();
	assert(latest.length == 3);
	assert(latest[0].context == context);
	assert(latest[0].exitStatus.get == 0);
	assert(latest[1].exitStatus.get == 7);
	assert(latest[1].elapsed == Duration.zero);
	assert(latest[2].exitStatus.isNull);

	assertThrown!Exception(collector.record(context, MonoTime.init, end));
	assertThrown!Exception(collector.record(context, start, MonoTime.init));
	assert(collector.snapshot().length == 3);
}

unittest {
	import core.thread : Thread;
	import std.conv : to;

	auto collector = new BuildTimingCollector;
	Thread[] workers;
	enum workerCount = 4;
	enum jobsPerWorker = 64;
	foreach (worker; 0 .. workerCount) {
		// Give each delegate its own context instead of capturing the loop index.
		Thread makeWorker(int id) {
			return new Thread({
				auto context = BuildTimingContext(BuildTimingPhase.compile,
					to!string(id), ["source/module.d"]);
				foreach (job; 0 .. jobsPerWorker) {
					auto start = MonoTime.currTime;
					auto end = MonoTime.currTime;
					collector.record(context, start, end, Nullable!int(job));
					// Read snapshots while other workers may still be appending.
					foreach (entry; collector.snapshot())
						assert(entry.endOffset >= entry.startOffset);
				}
			});
		}
		workers ~= makeWorker(worker);
	}
	foreach (worker; workers) worker.start();
	foreach (worker; workers) worker.join();

	auto records = collector.snapshot();
	assert(records.length == workerCount * jobsPerWorker);
	bool[jobsPerWorker][workerCount] seen;
	foreach (entry; records) {
		auto worker = to!int(entry.context.targetPackage);
		auto job = entry.exitStatus.get;
		assert(!seen[worker][job]);
		seen[worker][job] = true;
	}
}
