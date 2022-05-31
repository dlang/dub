/+ dub.json: {
"name": "issue2234_copy_read_only_files"
} +/

/*
When DUB copies read-only files to the targetPath, the read-only flag must be
removed. If not, any subsequent copy operations will fail.

Version control systems such as Git Large File Storage typically mark binary
files as read-only, to prevent simultaneous edits in unmergeable formats.
*/

module issue2234_copy_read_only_files.script;

import
	std.algorithm.searching,
	std.algorithm.iteration,
	std.stdio, std.process, std.path, std.file;

int main()
{
	const project_dir = buildPath(__FILE_FULL_PATH__.dirName, "issue2234-copy-read-only-files");
	const deployment_dir = buildPath(project_dir, "bin");
	auto deployables = dirEntries(buildPath(project_dir, "files"), "*", SpanMode.depth).filter!isFile;

	// Prepare environment.
	if (deployment_dir.exists)
	{
		foreach (entry; dirEntries(deployment_dir, "*", SpanMode.depth))
		{
			if (entry.isDir)
				entry.rmdir;
			else
			{
				entry.makeWritable;
				entry.remove;
			}
		}
		deployment_dir.rmdir;
	}
	foreach (ref f; deployables)
		f.makeReadOnly;

	// Execute test.
	const dub = environment.get("DUB", buildPath(__FILE_FULL_PATH__.dirName.dirName, "bin", "dub.exe"));
	const cmd = [dub, "build", "--build=release"];
	const result = execute(cmd, null, Config.none, size_t.max, project_dir);
	if (result.status || result.output.canFind("Failed"))
	{
		writefln("\n> %-(%s %)", cmd);
		writeln("===========================================================");
		writeln(result.output);
		writeln("===========================================================");
		writeln("Last command failed with exit code ", result.status, '\n');
		return 1;
	}

	foreach (deployed; dirEntries(deployment_dir, "*", SpanMode.depth).filter!isFile)
		if (!isWritable(deployed))
		{
			writeln(deployed, " is expected to be writable, but it is not.");
			return 1;
		}

	return 0;
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
		static assert("Needs implementation.");

	import std.exception;
	import std.stdio;
	assertThrown!ErrnoException(File(name, "w"));
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
		static assert("Needs implementation.");

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
		static assert("Needs implementation.");
}
