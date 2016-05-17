/**
	File handling.

	Copyright: © 2012 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.internal.vibecompat.core.file;

public import dub.internal.vibecompat.inet.url;

import dub.internal.vibecompat.core.log;

import std.conv;
import core.stdc.stdio;
import std.datetime;
import std.exception;
import std.file;
import std.path;
import std.stdio;
import std.string;
import std.utf;


/* Add output range support to File
*/
struct RangeFile {
	std.stdio.File file;

	void put(in ubyte[] bytes) { file.rawWrite(bytes); }
	void put(in char[] str) { put(cast(ubyte[])str); }
	void put(char ch) { put((&ch)[0 .. 1]); }
	void put(dchar ch) { char[4] chars; put(chars[0 .. encode(chars, ch)]); }

	ubyte[] readAll()
	{
		auto sz = file.size;
		enforce(sz <= size_t.max, "File is too big to read to memory.");
		file.seek(0, SEEK_SET);
		auto ret = new ubyte[cast(size_t)sz];
		file.rawRead(ret);
		return ret;
	}

	void rawRead(ubyte[] dst) { file.rawRead(dst); }
	void write(string str) { put(str); }
	void close() { file.close(); }
	void flush() { file.flush(); }
	@property ulong size() { return file.size; }
}


/**
	Opens a file stream with the specified mode.
*/
RangeFile openFile(Path path, FileMode mode = FileMode.read)
{
	string fmode;
	final switch(mode){
		case FileMode.read: fmode = "rb"; break;
		case FileMode.readWrite: fmode = "r+b"; break;
		case FileMode.createTrunc: fmode = "wb"; break;
		case FileMode.append: fmode = "ab"; break;
	}
	auto ret = std.stdio.File(path.toNativeString(), fmode);
	assert(ret.isOpen);
	return RangeFile(ret);
}
/// ditto
RangeFile openFile(string path, FileMode mode = FileMode.read)
{
	return openFile(Path(path), mode);
}


/**
	Moves or renames a file.
*/
void moveFile(Path from, Path to)
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
		from = Path of the source file
		to = Path for the destination file
		overwrite = If true, any file existing at the destination path will be
			overwritten. If this is false, an excpetion will be thrown should
			a file already exist at the destination path.

	Throws:
		An Exception if the copy operation fails for some reason.
*/
void copyFile(Path from, Path to, bool overwrite = false)
{
	enforce(existsFile(from), "Source file does not exist.");

	if (existsFile(to)) {
		enforce(overwrite, "Destination file already exists.");
		// remove file before copy to allow "overwriting" files that are in
		// use on Linux
		removeFile(to);
	}

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
/// ditto
void copyFile(string from, string to)
{
	copyFile(Path(from), Path(to));
}

version (Windows) extern(Windows) int CreateHardLinkW(in wchar* to, in wchar* from, void* attr=null);

// guess whether 2 files are identical, ignores filename and content
private bool sameFile(Path a, Path b)
{
	static assert(__traits(allMembers, FileInfo)[0] == "name");
	return getFileInfo(a).tupleof[1 .. $] == getFileInfo(b).tupleof[1 .. $];
}

/**
	Creates a hardlink.
*/
void hardLinkFile(Path from, Path to, bool overwrite = false)
{
	if (existsFile(to)) {
		enforce(overwrite, "Destination file already exists.");
		if (auto fe = collectException!FileException(removeFile(to))) {
			version (Windows) if (sameFile(from, to)) return;
			throw fe;
		}
	}

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
	// fallback to copy
	copyFile(from, to, overwrite);
}

/**
	Removes a file
*/
void removeFile(Path path)
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
bool existsFile(Path path) {
	return existsFile(path.toNativeString());
}
/// ditto
bool existsFile(string path)
{
	return std.file.exists(path);
}

/** Stores information about the specified file/directory into 'info'

	Returns false if the file does not exist.
*/
FileInfo getFileInfo(Path path)
{
	static if (__VERSION__ >= 2064)
		auto ent = std.file.DirEntry(path.toNativeString());
	else auto ent = std.file.dirEntry(path.toNativeString());
	return makeFileInfo(ent);
}
/// ditto
FileInfo getFileInfo(string path)
{
	return getFileInfo(Path(path));
}

/**
	Creates a new directory.
*/
void createDirectory(Path path)
{
	mkdir(path.toNativeString());
}
/// ditto
void createDirectory(string path)
{
	createDirectory(Path(path));
}

/**
	Enumerates all files in the specified directory.
*/
void listDirectory(Path path, scope bool delegate(FileInfo info) del)
{
	foreach( DirEntry ent; dirEntries(path.toNativeString(), SpanMode.shallow) )
		if( !del(makeFileInfo(ent)) )
			break;
}
/// ditto
void listDirectory(string path, scope bool delegate(FileInfo info) del)
{
	listDirectory(Path(path), del);
}
/// ditto
int delegate(scope int delegate(ref FileInfo)) iterateDirectory(Path path)
{
	int iterator(scope int delegate(ref FileInfo) del){
		int ret = 0;
		listDirectory(path, (fi){
			ret = del(fi);
			return ret == 0;
		});
		return ret;
	}
	return &iterator;
}
/// ditto
int delegate(scope int delegate(ref FileInfo)) iterateDirectory(string path)
{
	return iterateDirectory(Path(path));
}


/**
	Returns the current working directory.
*/
Path getWorkingDirectory()
{
	return Path(std.file.getcwd());
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

	/// Time of creation (not available on all operating systems/file systems)
	SysTime timeCreated;

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
		version(Windows) ret.timeCreated = ent.timeCreated;
		else ret.timeCreated = ent.timeLastModified;
	} catch (Exception e) {
		logDiagnostic("Failed to get extended file information for %s: %s", ret.name, e.msg);
	}
	return ret;
}
