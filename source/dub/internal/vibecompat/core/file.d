/**
	File handling.

	Copyright: © 2012 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.internal.vibecompat.core.file;

public import dub.internal.vibecompat.inet.path;

import dub.internal.logging;

import std.conv;
import core.stdc.stdio;
import std.datetime;
import std.exception;
import std.file;
import std.path;
import std.stdio;
import std.string;
import std.utf;


/// Writes `buffer` to a file
public void writeFile(NativePath path, const void[] buffer)
{
	std.file.write(path.toNativeString(), buffer);
}

/// Returns the content of a file
public ubyte[] readFile(NativePath path)
{
	return cast(ubyte[]) std.file.read(path.toNativeString());
}

/// Returns the content of a file as text
public string readText(NativePath path)
{
    return std.file.readText(path.toNativeString());
}

/**
	Moves or renames a file.
*/
void moveFile(NativePath from, NativePath to)
{
	moveFile(from.toNativeString(), to.toNativeString());
}
/// ditto
void moveFile(string from, string to)
{
	std.file.rename(from, to);
}

/**
	Copies a file.

	Note that attributes and time stamps are currently not retained.

	Params:
		from = NativePath of the source file
		to = NativePath for the destination file
		overwrite = If true, any file existing at the destination path will be
			overwritten. If this is false, an exception will be thrown should
			a file already exist at the destination path.

	Throws:
		An Exception if the copy operation fails for some reason.
*/
void copyFile(NativePath from, NativePath to, bool overwrite = false)
{
	enforce(existsFile(from), "Source file does not exist.");

	if (existsFile(to)) {
		enforce(overwrite, "Destination file already exists.");
		// remove file before copy to allow "overwriting" files that are in
		// use on Linux
		removeFile(to);
	}

	static if (is(PreserveAttributes))
	{
		.copy(from.toNativeString(), to.toNativeString(), PreserveAttributes.yes);
	}
	else
	{
		.copy(from.toNativeString(), to.toNativeString());
		// try to preserve ownership/permissions in Posix
		version (Posix) {
			import core.sys.posix.sys.stat;
			import core.sys.posix.unistd;
			import std.utf;
			auto cspath = toUTFz!(const(char)*)(from.toNativeString());
			auto cdpath = toUTFz!(const(char)*)(to.toNativeString());
			stat_t st;
			enforce(stat(cspath, &st) == 0, "Failed to get attributes of source file.");
			if (chown(cdpath, st.st_uid, st.st_gid) != 0)
				st.st_mode &= ~(S_ISUID | S_ISGID);
			chmod(cdpath, st.st_mode);
		}
	}
}
/// ditto
void copyFile(string from, string to)
{
	copyFile(NativePath(from), NativePath(to));
}

version (Windows) extern(Windows) int CreateHardLinkW(const(wchar)* to, const(wchar)* from, void* attr=null);

// guess whether 2 files are identical, ignores filename and content
private bool sameFile(NativePath a, NativePath b)
{
	version (Posix) {
		auto st_a = std.file.DirEntry(a.toNativeString).statBuf;
		auto st_b = std.file.DirEntry(b.toNativeString).statBuf;
		return st_a == st_b;
	} else {
		static assert(__traits(allMembers, FileInfo)[0] == "name");
		return getFileInfo(a).tupleof[1 .. $] == getFileInfo(b).tupleof[1 .. $];
	}
}

private bool isWritable(NativePath name)
{
	version (Windows)
	{
		import core.sys.windows.windows;

		return (name.toNativeString.getAttributes & FILE_ATTRIBUTE_READONLY) == 0;
	}
	else version (Posix)
	{
		import core.sys.posix.sys.stat;

		return (name.toNativeString.getAttributes & S_IWUSR) != 0;
	}
	else
		static assert(false, "Needs implementation.");
}

private void makeWritable(NativePath name)
{
	makeWritable(name.toNativeString);
}

private void makeWritable(string name)
{
	version (Windows)
	{
		import core.sys.windows.windows;

		name.setAttributes(name.getAttributes & ~FILE_ATTRIBUTE_READONLY);
	}
	else version (Posix)
	{
		import core.sys.posix.sys.stat;

		name.setAttributes(name.getAttributes | S_IWUSR);
	}
	else
		static assert(false, "Needs implementation.");
}

/**
	Creates a hardlink if possible, a copy otherwise.

	If `from` is read-only and `overwrite` is true, then a copy is made instead
	and `to` is made writable; so that repeating the command will not fail.
*/
void hardLinkFile(NativePath from, NativePath to, bool overwrite = false)
{
	if (existsFile(to)) {
		enforce(overwrite, "Destination file already exists.");
		if (auto fe = collectException!FileException(removeFile(to))) {
			if (sameFile(from, to)) return;
			throw fe;
		}
	}
	const writeAccessChangeRequired = overwrite && !isWritable(from);
	if (!writeAccessChangeRequired)
	{
		version (Windows)
		{
			alias cstr = toUTFz!(const(wchar)*);
			if (CreateHardLinkW(cstr(to.toNativeString), cstr(from.toNativeString)))
				return;
		}
		else
		{
			import core.sys.posix.unistd : link;
			alias cstr = toUTFz!(const(char)*);
			if (!link(cstr(from.toNativeString), cstr(to.toNativeString)))
				return;
		}
	}
	// fallback to copy
	copyFile(from, to, overwrite);
	if (writeAccessChangeRequired)
		to.makeWritable;
}

/**
	Removes a file
*/
void removeFile(NativePath path)
{
	removeFile(path.toNativeString());
}
/// ditto
void removeFile(string path) {
	std.file.remove(path);
}

/**
	Checks if a file exists
*/
bool existsFile(NativePath path) {
	return existsFile(path.toNativeString());
}
/// ditto
bool existsFile(string path)
{
	return std.file.exists(path);
}

/// Checks if a directory exists
bool existsDirectory(NativePath path) {
	if( !existsFile(path) ) return false;
	auto fi = getFileInfo(path);
	return fi.isDirectory;
}

/** Stores information about the specified file/directory into 'info'

	Returns false if the file does not exist.
*/
FileInfo getFileInfo(NativePath path)
{
	auto ent = std.file.DirEntry(path.toNativeString());
	return makeFileInfo(ent);
}
/// ditto
FileInfo getFileInfo(string path)
{
	return getFileInfo(NativePath(path));
}

/**
	Creates a new directory.
*/
void ensureDirectory(NativePath path)
{
	if (!existsDirectory(path))
		mkdirRecurse(path.toNativeString());
}

/**
	Enumerates all files in the specified directory.
*/
int delegate(scope int delegate(ref FileInfo)) iterateDirectory(NativePath path)
{
	int iterator(scope int delegate(ref FileInfo) del){
		foreach (DirEntry ent; dirEntries(path.toNativeString(), SpanMode.shallow)) {
			auto fi = makeFileInfo(ent);
			if (auto res = del(fi))
				return res;
		}
		return 0;
	}
	return &iterator;
}

/**
	Returns the current working directory.
*/
NativePath getWorkingDirectory()
{
	return NativePath(std.file.getcwd());
}


/** Contains general information about a file.
*/
struct FileInfo {
	/// Name of the file (not including the path)
	string name;

	/// Size of the file (zero for directories)
	ulong size;

	/// Time of the last modification
	SysTime timeModified;

	/// True if this is a symlink to an actual file
	bool isSymlink;

	/// True if this is a directory or a symlink pointing to a directory
	bool isDirectory;
}

/**
	Specifies how a file is manipulated on disk.
*/
enum FileMode {
	/// The file is opened read-only.
	read,
	/// The file is opened for read-write random access.
	readWrite,
	/// The file is truncated if it exists and created otherwise and the opened for read-write access.
	createTrunc,
	/// The file is opened for appending data to it and created if it does not exist.
	append
}

/**
	Accesses the contents of a file as a stream.
*/

private FileInfo makeFileInfo(DirEntry ent)
{
	FileInfo ret;
	ret.name = baseName(ent.name);
	if( ret.name.length == 0 ) ret.name = ent.name;
	assert(ret.name.length > 0);
	ret.isSymlink = ent.isSymlink;
	try {
		ret.isDirectory = ent.isDir;
		ret.size = ent.size;
		ret.timeModified = ent.timeLastModified;
	} catch (Exception e) {
		logDiagnostic("Failed to get extended file information for %s: %s", ret.name, e.msg);
	}
	return ret;
}
