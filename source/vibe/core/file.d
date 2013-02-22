/**
	File handling.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.core.file;

public import vibe.inet.url;
public import std.stdio;

import vibe.core.log;

import std.conv;
import std.c.stdio;
import std.datetime;
import std.exception;
import std.file;
import std.path;
import std.string;
import std.utf;


version(Posix){
	private extern(C) int mkstemps(char* templ, int suffixlen);
}


/* Add output range support to File
*/
struct RangeFile {
	File file;
	alias file this;

	void put(in char[] str) { file.write(str); }
	void put(char ch) { file.write(cast(ubyte)ch); }
	void put(dchar ch) { char[4] chars; put(chars[0 .. encode(chars, ch)]); }
	
	ubyte[] readAll()
	{
		file.seek(0, SEEK_END);
		auto sz = file.tell();
		enforce(sz <= size_t.max, "File is too big to read to memory.");
		file.seek(0, SEEK_SET);
		auto ret = new ubyte[cast(size_t)sz];
		return file.rawRead(ret);
	}
}


/**
	Opens a file stream with the specified mode.
*/
RangeFile openFile(Path path, FileMode mode = FileMode.Read)
{
	string strmode;
	final switch(mode){
		case FileMode.Read: strmode = "rb"; break;
		case FileMode.ReadWrite: strmode = "rb+"; break;
		case FileMode.CreateTrunc: strmode = "wb+"; break;
		case FileMode.Append: strmode = "ab"; break;
	}
	auto ret = File(path.toNativeString(), strmode);
	assert(ret.isOpen());
	return RangeFile(ret);
}
/// ditto
RangeFile openFile(string path, FileMode mode = FileMode.Read)
{
	return openFile(Path(path), mode);
}

/**
	Creates and opens a temporary file for writing.
*/
RangeFile createTempFile(string suffix = null)
{
	version(Windows){
		char[L_tmpnam] tmp;
		tmpnam(tmp.ptr);
		auto tmpname = to!string(tmp.ptr);
		if( tmpname.startsWith("\\") ) tmpname = tmpname[1 .. $];
		tmpname ~= suffix;
		logDebug("tmp %s", tmpname);
		return openFile(tmpname, FileMode.CreateTrunc);
	} else {
		import core.sys.posix.stdio;
		enum pattern ="/tmp/vtmp.XXXXXX";
		scope templ = new char[pattern.length+suffix.length+1];
		templ[0 .. pattern.length] = pattern;
		templ[pattern.length .. $-1] = suffix;
		templ[$-1] = '\0';
		assert(suffix.length <= int.max);
		auto fd = mkstemps(templ.ptr, cast(int)suffix.length);
		enforce(fd >= 0, "Failed to create temporary file.");
		auto ret = File.wrapFile(fdopen(fd, "wb+"));
		return RangeFile(ret);
	}
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
	{
		auto src = openFile(from, FileMode.Read);
		scope(exit) src.close();
		enforce(overwrite || !existsFile(to), "Destination file already exists.");
		auto dst = openFile(to, FileMode.CreateTrunc);
		scope(exit) dst.close();
		dst.write(src);
	}

	// TODO: retain attributes and time stamps
}
/// ditto
void copyFile(string from, string to)
{
	copyFile(Path(from), Path(to));
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
	auto ent = std.file.dirEntry(path.toNativeString());
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
	Read,
	/// The file is opened for read-write random access.
	ReadWrite,
	/// The file is truncated if it exists and created otherwise and the opened for read-write access.
	CreateTrunc,
	/// The file is opened for appending data to it and created if it does not exist.
	Append
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
	ret.size = ent.size;
	ret.timeModified = ent.timeLastModified;
	version(Windows) ret.timeCreated = ent.timeCreated;
	else ret.timeCreated = ent.timeLastModified;
	ret.isSymlink = ent.isSymlink;
	ret.isDirectory = ent.isDir;
	return ret;
}

