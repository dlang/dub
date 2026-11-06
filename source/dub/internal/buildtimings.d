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
	or completion order. Reporting may sort a snapshot without holding the lock.
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

	/// Independent array; callers can edit or sort it without altering collection.
	BuildTimingRecord[] snapshot() {
		synchronized (m_mutex) {
			return m_records.dup;
		}
	}
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
