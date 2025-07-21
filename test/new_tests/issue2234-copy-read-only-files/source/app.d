import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	immutable deploymentDir = "sample/bin";
	auto deployables = dirEntries("sample/files", SpanMode.depth).filter!isFile;

	if (deploymentDir.exists) {
		foreach (entry; dirEntries(deploymentDir, SpanMode.depth))
			if (entry.isDir)
				entry.rmdir;
			else {
				entry.makeWritable;
				entry.remove;
			}
		deploymentDir.rmdirRecurse;
	}

	foreach (ref f; deployables)
		f.makeReadOnly;

	if (spawnProcess([dub, "build", "--build=release"], null, Config.none, "sample").wait != 0)
		die("Dub build failed");

	foreach (deployed; dirEntries(deploymentDir, SpanMode.depth).filter!isFile)
		if (!isWritable(deployed))
			die(deployed, " is expected to be writable, but it is not.");
}

void makeReadOnly(string name)
{
	version (Windows)
	{
		import core.sys.windows.windows;

		name.setAttributes(name.getAttributes() | FILE_ATTRIBUTE_READONLY);
	}
	else version (Posix)
	{
		import core.sys.posix.sys.stat;

		name.setAttributes(name.getAttributes() & ~(S_IWUSR | S_IWGRP | S_IWOTH));
	}
	else
		static assert(false, "Needs implementation.");

	// This fails on posix when run as root. Just assume that the
	// functions above work.
	version(none) {
		import std.exception;
		import std.stdio;
		assertThrown!ErrnoException(File(name, "w"));
	}
}

void makeWritable(string name)
{
	version (Windows)
	{
		import core.sys.windows.windows;

		name.setAttributes(name.getAttributes() & ~FILE_ATTRIBUTE_READONLY);
	}
	else version (Posix)
	{
		import core.sys.posix.sys.stat;

		name.setAttributes(name.getAttributes() | S_IWUSR);
	}
	else
		static assert(false, "Needs implementation.");

	import std.exception;
	import std.stdio;
	assertNotThrown!ErrnoException(File(name, "w"));
}

bool isWritable(string name)
{
	version (Windows)
	{
		import core.sys.windows.windows;

		return (name.getAttributes() & FILE_ATTRIBUTE_READONLY) == 0;
	}
	else version (Posix)
	{
		import core.sys.posix.sys.stat;

		return (name.getAttributes() & S_IWUSR) != 0;
	}
	else
		static assert(false, "Needs implementation.");
}
