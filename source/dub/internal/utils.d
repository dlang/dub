/**
	...

	Copyright: © 2012 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff
*/
module dub.internal.utils;

import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.data.json;
import dub.internal.vibecompat.inet.url;
import dub.compilers.buildsettings : BuildSettings;
import dub.version_;

import core.time : Duration;
import std.algorithm : canFind, startsWith;
import std.array : appender, array;
import std.conv : to;
import std.exception : enforce;
import std.file;
import std.string : format;
import std.process;
import std.traits : isIntegral;
version(DubUseCurl)
{
	import std.net.curl;
	public import std.net.curl : HTTPStatusException;
}


private NativePath[] temporary_files;

NativePath getTempDir()
{
	return NativePath(std.file.tempDir());
}

NativePath getTempFile(string prefix, string extension = null)
{
	import std.uuid : randomUUID;
	import std.array: replace;

	string fileName = prefix ~ "-" ~ randomUUID.toString() ~ extension;

	if (extension !is null && extension == ".d")
		fileName = fileName.replace("-", "_");

	auto path = getTempDir() ~ fileName;
	temporary_files ~= path;
	return path;
}

/**
   Obtain a lock for a file at the given path. If the file cannot be locked
   within the given duration, an exception is thrown.  The file will be created
   if it does not yet exist. Deleting the file is not safe as another process
   could create a new file with the same name.
   The returned lock will get unlocked upon destruction.

   Params:
     path = path to file that gets locked
     timeout = duration after which locking failed
   Returns:
     The locked file or an Exception on timeout.
*/
auto lockFile(string path, Duration timeout)
{
	import core.thread : Thread;
	import std.datetime, std.stdio : File;
	import std.algorithm : move;

	// Just a wrapper to hide (and destruct) the locked File.
	static struct LockFile
	{
		// The Lock can't be unlinked as someone could try to lock an already
		// opened fd while a new file with the same name gets created.
		// Exclusive filesystem locks (O_EXCL, mkdir) could be deleted but
		// aren't automatically freed when a process terminates, see #1149.
		private File f;
	}

	auto file = File(path, "w");
	auto t0 = Clock.currTime();
	auto dur = 1.msecs;
	while (true)
	{
		if (file.tryLock())
			return LockFile(move(file));
		enforce(Clock.currTime() - t0 < timeout, "Failed to lock '"~path~"'.");
		if (dur < 1024.msecs) // exponentially increase sleep time
			dur *= 2;
		Thread.sleep(dur);
	}
}

static ~this()
{
	foreach (path; temporary_files)
	{
		auto spath = path.toNativeString();
		if (spath.exists)
			std.file.remove(spath);
	}
}

bool isWritableDir(NativePath p, bool create_if_missing = false)
{
	import std.random;
	auto fname = p ~ format("__dub_write_test_%08X", uniform(0, uint.max));
	if (create_if_missing && !exists(p.toNativeString())) mkdirRecurse(p.toNativeString());
	try openFile(fname, FileMode.createTrunc).close();
	catch (Exception) return false;
	remove(fname.toNativeString());
	return true;
}

Json jsonFromFile(NativePath file, bool silent_fail = false) {
	if( silent_fail && !existsFile(file) ) return Json.emptyObject;
	auto f = openFile(file.toNativeString(), FileMode.read);
	scope(exit) f.close();
	auto text = stripUTF8Bom(cast(string)f.readAll());
	return parseJsonString(text, file.toNativeString());
}

/**
	Read package info file content from archive.
	File needs to be in root folder or in first
	sub folder.

	Params:
		zip = path to archive file
		fileName = Package file name
	Returns:
		package file content.
*/
string packageInfoFileFromZip(NativePath zip, out string fileName) {
	import std.zip : ZipArchive, ArchiveMember;
	import dub.package_ : packageInfoFiles;

	auto f = openFile(zip, FileMode.read);
	ubyte[] b = new ubyte[cast(size_t)f.size];
	f.rawRead(b);
	f.close();
	auto archive = new ZipArchive(b);
	alias PSegment = typeof (NativePath.init.head);
	foreach (ArchiveMember am; archive.directory) {
		auto path = NativePath(am.name).bySegment.array;
		foreach (fil; packageInfoFiles) {
			if ((path.length == 1 && path[0] == fil.filename) || (path.length == 2 && path[$-1].name == fil.filename)) {
				fileName = fil.filename;
				return stripUTF8Bom(cast(string) archive.expand(archive.directory[am.name]));
			}
		}
	}
	throw new Exception("No package descriptor found");
}

void writeJsonFile(NativePath path, Json json)
{
	auto f = openFile(path, FileMode.createTrunc);
	scope(exit) f.close();
	f.writePrettyJsonString(json);
}

/// Performs a write->delete->rename sequence to atomically "overwrite" the destination file
void atomicWriteJsonFile(NativePath path, Json json)
{
	import std.random : uniform;
	auto tmppath = path.parentPath ~ format("%s.%s.tmp", path.head, uniform(0, int.max));
	auto f = openFile(tmppath, FileMode.createTrunc);
	scope (failure) {
		f.close();
		removeFile(tmppath);
	}
	f.writePrettyJsonString(json);
	f.close();
	if (existsFile(path)) removeFile(path);
	moveFile(tmppath, path);
}

bool existsDirectory(NativePath path) {
	if( !existsFile(path) ) return false;
	auto fi = getFileInfo(path);
	return fi.isDirectory;
}

void runCommand(string command, string[string] env = null, string workDir = null)
{
	runCommands((&command)[0 .. 1], env, workDir);
}

void runCommands(in string[] commands, string[string] env = null, string workDir = null)
{
	import std.stdio : stdin, stdout, stderr, File;

	version(Windows) enum nullFile = "NUL";
	else version(Posix) enum nullFile = "/dev/null";
	else static assert(0);

	auto childStdout = stdout;
	auto childStderr = stderr;
	auto config = Config.retainStdout | Config.retainStderr;

	// Disable child's stdout/stderr depending on LogLevel
	auto logLevel = getLogLevel();
	if(logLevel >= LogLevel.warn)
		childStdout = File(nullFile, "w");
	if(logLevel >= LogLevel.none)
		childStderr = File(nullFile, "w");

	foreach(cmd; commands){
		logDiagnostic("Running %s", cmd);
		Pid pid;
		pid = spawnShell(cmd, stdin, childStdout, childStderr, env, config, workDir);
		auto exitcode = pid.wait();
		enforce(exitcode == 0, "Command failed with exit code "
			~ to!string(exitcode) ~ ": " ~ cmd);
	}
}

version (Have_vibe_d_http)
	public import vibe.http.common : HTTPStatusException;

/**
	Downloads a file from the specified URL.

	Any redirects will be followed until the actual file resource is reached or if the redirection
	limit of 10 is reached. Note that only HTTP(S) is currently supported.

	The download times out if a connection cannot be established within
	`timeout` ms, or if the average transfer rate drops below 10 bytes / s for
	more than `timeout` seconds.  Pass `0` as `timeout` to disable both timeout
	mechanisms.

	Note: Timeouts are only implemented when curl is used (DubUseCurl).
*/
void download(string url, string filename, uint timeout = 8)
{
	version(DubUseCurl) {
		auto conn = HTTP();
		setupHTTPClient(conn, timeout);
		logDebug("Storing %s...", url);
		std.net.curl.download(url, filename, conn);
		// workaround https://issues.dlang.org/show_bug.cgi?id=18318
		auto sl = conn.statusLine;
		logDebug("Download %s %s", url, sl);
		if (sl.code / 100 != 2)
			throw new HTTPStatusException(sl.code,
				"Downloading %s failed with %d (%s).".format(url, sl.code, sl.reason));
	} else version (Have_vibe_d_http) {
		import vibe.inet.urltransfer;
		vibe.inet.urltransfer.download(url, filename);
	} else assert(false);
}
/// ditto
void download(URL url, NativePath filename, uint timeout = 8)
{
	download(url.toString(), filename.toNativeString(), timeout);
}
/// ditto
ubyte[] download(string url, uint timeout = 8)
{
	version(DubUseCurl) {
		auto conn = HTTP();
		setupHTTPClient(conn, timeout);
		logDebug("Getting %s...", url);
		return cast(ubyte[])get(url, conn);
	} else version (Have_vibe_d_http) {
		import vibe.inet.urltransfer;
		import vibe.stream.operations;
		ubyte[] ret;
		vibe.inet.urltransfer.download(url, (scope input) { ret = input.readAll(); });
		return ret;
	} else assert(false);
}
/// ditto
ubyte[] download(URL url, uint timeout = 8)
{
	return download(url.toString(), timeout);
}

/**
	Downloads a file from the specified URL with retry logic.

	Downloads a file from the specified URL with up to n tries on failure
	Throws: `Exception` if the download failed or `HTTPStatusException` after the nth retry or
	on "unrecoverable failures" such as 404 not found
	Otherwise might throw anything else that `download` throws.
	See_Also: download

	The download times out if a connection cannot be established within
	`timeout` ms, or if the average transfer rate drops below 10 bytes / s for
	more than `timeout` seconds.  Pass `0` as `timeout` to disable both timeout
	mechanisms.

	Note: Timeouts are only implemented when curl is used (DubUseCurl).
**/
void retryDownload(URL url, NativePath filename, size_t retryCount = 3, uint timeout = 8)
{
	foreach(i; 0..retryCount) {
		version(DubUseCurl) {
			try {
				download(url, filename, timeout);
				return;
			}
			catch(HTTPStatusException e) {
				if (e.status == 404) throw e;
				else {
					logDebug("Failed to download %s (Attempt %s of %s)", url, i + 1, retryCount);
					if (i == retryCount - 1) throw e;
					else continue;
				}
			}
			catch(CurlException e) {
				logDebug("Failed to download %s (Attempt %s of %s)", url, i + 1, retryCount);
				continue;
			}
		}
		else
		{
			try {
				download(url, filename);
				return;
			}
			catch(HTTPStatusException e) {
				if (e.status == 404) throw e;
				else {
					logDebug("Failed to download %s (Attempt %s of %s)", url, i + 1, retryCount);
					if (i == retryCount - 1) throw e;
					else continue;
				}
			}
		}
	}
	throw new Exception("Failed to download %s".format(url));
}

///ditto
ubyte[] retryDownload(URL url, size_t retryCount = 3, uint timeout = 8)
{
	foreach(i; 0..retryCount) {
		version(DubUseCurl) {
			try {
				return download(url, timeout);
			}
			catch(HTTPStatusException e) {
				if (e.status == 404) throw e;
				else {
					logDebug("Failed to download %s (Attempt %s of %s)", url, i + 1, retryCount);
					if (i == retryCount - 1) throw e;
					else continue;
				}
			}
			catch(CurlException e) {
				logDebug("Failed to download %s (Attempt %s of %s)", url, i + 1, retryCount);
				continue;
			}
		}
		else
		{
			try {
				return download(url);
			}
			catch(HTTPStatusException e) {
				if (e.status == 404) throw e;
				else {
					logDebug("Failed to download %s (Attempt %s of %s)", url, i + 1, retryCount);
					if (i == retryCount - 1) throw e;
					else continue;
				}
			}
		}
	}
	throw new Exception("Failed to download %s".format(url));
}

/// Returns the current DUB version in semantic version format
string getDUBVersion()
{
	import dub.version_;
	import std.array : split, join;
	// convert version string to valid SemVer format
	auto verstr = dubVersion;
	if (verstr.startsWith("v")) verstr = verstr[1 .. $];
	auto parts = verstr.split("-");
	if (parts.length >= 3) {
		// detect GIT commit suffix
		if (parts[$-1].length == 8 && parts[$-1][1 .. $].isHexNumber() && parts[$-2].isNumber())
			verstr = parts[0 .. $-2].join("-") ~ "+" ~ parts[$-2 .. $].join("-");
	}
	return verstr;
}


/**
	Get current executable's path if running as DUB executable,
	or find a DUB executable if DUB is used as a library.
	For the latter, the following locations are checked in order:
	$(UL
		$(LI current working directory)
		$(LI same directory as `compilerBinary` (if supplied))
		$(LI all components of the `$PATH` variable)
	)
	Params:
		compilerBinary = optional path to a D compiler executable, used to locate DUB executable
	Returns:
		The path to a valid DUB executable
	Throws:
		an Exception if no valid DUB executable is found
*/
public string getDUBExePath(in string compilerBinary=null)
{
	version(DubApplication) {
		import std.file : thisExePath;
		return thisExePath();
	}
	else {
		// this must be dub as a library
		import std.algorithm : filter, map, splitter;
		import std.array : array;
		import std.file : exists, getcwd;
		import std.path : chainPath, dirName;
		import std.range : chain, only, take;
		import std.process : environment;

		version(Windows) {
			enum exeName = "dub.exe";
			enum pathSep = ';';
		}
		else {
			enum exeName = "dub";
			enum pathSep = ':';
		}

		auto dubLocs = only(
			getcwd().chainPath(exeName),
			compilerBinary.dirName.chainPath(exeName),
		)
		.take(compilerBinary.length ? 2 : 1)
		.chain(
			environment.get("PATH", "")
				.splitter(pathSep)
				.map!(p => p.chainPath(exeName))
		)
		.filter!exists;

		enforce(!dubLocs.empty, "Could not find DUB executable");
		return dubLocs.front.array;
	}
}


version(DubUseCurl) {
	void setupHTTPClient(ref HTTP conn, uint timeout)
	{
		static if( is(typeof(&conn.verifyPeer)) )
			conn.verifyPeer = false;

		auto proxy = environment.get("http_proxy", null);
		if (proxy.length) conn.proxy = proxy;

		auto noProxy = environment.get("no_proxy", null);
		if (noProxy.length) conn.handle.set(CurlOption.noproxy, noProxy);

		conn.handle.set(CurlOption.encoding, "");
		if (timeout) {
			// connection (TLS+TCP) times out after 8s
			conn.handle.set(CurlOption.connecttimeout, timeout);
			// transfers time out after 8s below 10 byte/s
			conn.handle.set(CurlOption.low_speed_limit, 10);
			conn.handle.set(CurlOption.low_speed_time, timeout);
		}

		conn.addRequestHeader("User-Agent", "dub/"~getDUBVersion()~" (std.net.curl; +https://github.com/rejectedsoftware/dub)");

		enum CURL_NETRC_OPTIONAL = 1;
		conn.handle.set(CurlOption.netrc, CURL_NETRC_OPTIONAL);
	}
}

string stripUTF8Bom(string str)
{
	if( str.length >= 3 && str[0 .. 3] == [0xEF, 0xBB, 0xBF] )
		return str[3 ..$];
	return str;
}

private bool isNumber(string str) {
	foreach (ch; str)
		switch (ch) {
			case '0': .. case '9': break;
			default: return false;
		}
	return true;
}

private bool isHexNumber(string str) {
	foreach (ch; str)
		switch (ch) {
			case '0': .. case '9': break;
			case 'a': .. case 'f': break;
			case 'A': .. case 'F': break;
			default: return false;
		}
	return true;
}

/**
	Get the closest match of $(D input) in the $(D array), where $(D distance)
	is the maximum levenshtein distance allowed between the compared strings.
	Returns $(D null) if no closest match is found.
*/
string getClosestMatch(string[] array, string input, size_t distance)
{
	import std.algorithm : countUntil, map, levenshteinDistance;
	import std.uni : toUpper;

	auto distMap = array.map!(elem =>
		levenshteinDistance!((a, b) => toUpper(a) == toUpper(b))(elem, input));
	auto idx = distMap.countUntil!(a => a <= distance);
	return (idx == -1) ? null : array[idx];
}

/**
	Searches for close matches to input in range. R must be a range of strings
	Note: Sorts the strings range. Use std.range.indexed to avoid this...
  */
auto fuzzySearch(R)(R strings, string input){
	import std.algorithm : levenshteinDistance, schwartzSort, partition3;
	import std.traits : isSomeString;
	import std.range : ElementType;

	static assert(isSomeString!(ElementType!R), "Cannot call fuzzy search on non string rang");
	immutable threshold = input.length / 4;
	return strings.partition3!((a, b) => a.length + threshold < b.length)(input)[1]
			.schwartzSort!(p => levenshteinDistance(input.toUpper, p.toUpper));
}

/**
	If T is a bitfield-style enum, this function returns a string range
	listing the names of all members included in the given value.

	Example:
	---------
	enum Bits {
		none = 0,
		a = 1<<0,
		b = 1<<1,
		c = 1<<2,
		a_c = a | c,
	}

	assert( bitFieldNames(Bits.none).equals(["none"]) );
	assert( bitFieldNames(Bits.a).equals(["a"]) );
	assert( bitFieldNames(Bits.a_c).equals(["a", "c", "a_c"]) );
	---------
  */
auto bitFieldNames(T)(T value) if(is(T==enum) && isIntegral!T)
{
	import std.algorithm : filter, map;
	import std.conv : to;
	import std.traits : EnumMembers;

	return [ EnumMembers!(T) ]
		.filter!(member => member==0? value==0 : (value & member) == member)
		.map!(member => to!string(member));
}


bool isIdentChar(dchar ch)
{
	import std.ascii : isAlphaNum;
	return isAlphaNum(ch) || ch == '_';
}

string stripDlangSpecialChars(string s)
{
	import std.array : appender;
	auto ret = appender!string();
	foreach(ch; s)
		ret.put(isIdentChar(ch) ? ch : '_');
	return ret.data;
}

string determineModuleName(BuildSettings settings, NativePath file, NativePath base_path)
{
	import std.algorithm : map;
	import std.array : array;
	import std.range : walkLength;

	assert(base_path.absolute);
	if (!file.absolute) file = base_path ~ file;

	size_t path_skip = 0;
	foreach (ipath; settings.importPaths.map!(p => NativePath(p))) {
		if (!ipath.absolute) ipath = base_path ~ ipath;
		assert(!ipath.empty);
		if (file.startsWith(ipath) && ipath.bySegment.walkLength > path_skip)
			path_skip = ipath.bySegment.walkLength;
	}

	enforce(path_skip > 0,
		format("Source file '%s' not found in any import path.", file.toNativeString()));

	auto mpath = file.bySegment.array[path_skip .. $];
	auto ret = appender!string;

	//search for module keyword in file
	string moduleName = getModuleNameFromFile(file.to!string);

	if(moduleName.length) {
		assert(moduleName.length > 0, "Wasn't this module name already checked? what");
		return moduleName;
	}

	//create module name from path
	foreach (i; 0 .. mpath.length) {
		import std.path;
		auto p = mpath[i].name;
		if (p == "package.d") break ;
		if (ret.data.length > 0) ret ~= ".";
		if (i+1 < mpath.length) ret ~= p;
		else ret ~= p.baseName(".d");
	}

	assert(ret.data.length > 0, "A module name was expected to be computed, and none was.");
	return ret.data;
}

/**
 * Search for module keyword in D Code
 */
string getModuleNameFromContent(string content) {
	import std.regex;
	import std.string;

	content = content.strip;
	if (!content.length) return null;

	static bool regex_initialized = false;
	static Regex!char comments_pattern, module_pattern;

	if (!regex_initialized) {
		comments_pattern = regex(`//[^\r\n]*\r?\n?|/\*.*?\*/|/\+.*\+/`, "gs");
		module_pattern = regex(`module\s+([\w\.]+)\s*;`, "g");
		regex_initialized = true;
	}

	content = replaceAll(content, comments_pattern, " ");
	auto result = matchFirst(content, module_pattern);

	if (!result.empty) return result[1];

	return null;
}

unittest {
	assert(getModuleNameFromContent("") == "");
	assert(getModuleNameFromContent("module myPackage.myModule;") == "myPackage.myModule");
	assert(getModuleNameFromContent("module \t\n myPackage.myModule \t\r\n;") == "myPackage.myModule");
	assert(getModuleNameFromContent("// foo\nmodule bar;") == "bar");
	assert(getModuleNameFromContent("/*\nfoo\n*/\nmodule bar;") == "bar");
	assert(getModuleNameFromContent("/+\nfoo\n+/\nmodule bar;") == "bar");
	assert(getModuleNameFromContent("/***\nfoo\n***/\nmodule bar;") == "bar");
	assert(getModuleNameFromContent("/+++\nfoo\n+++/\nmodule bar;") == "bar");
	assert(getModuleNameFromContent("// module foo;\nmodule bar;") == "bar");
	assert(getModuleNameFromContent("/* module foo; */\nmodule bar;") == "bar");
	assert(getModuleNameFromContent("/+ module foo; +/\nmodule bar;") == "bar");
	assert(getModuleNameFromContent("/+ /+ module foo; +/ +/\nmodule bar;") == "bar");
	assert(getModuleNameFromContent("// module foo;\nmodule bar; // module foo;") == "bar");
	assert(getModuleNameFromContent("// module foo;\nmodule// module foo;\nbar//module foo;\n;// module foo;") == "bar");
	assert(getModuleNameFromContent("/* module foo; */\nmodule/*module foo;*/bar/*module foo;*/;") == "bar", getModuleNameFromContent("/* module foo; */\nmodule/*module foo;*/bar/*module foo;*/;"));
	assert(getModuleNameFromContent("/+ /+ module foo; +/ module foo; +/ module bar;") == "bar");
	//assert(getModuleNameFromContent("/+ /+ module foo; +/ module foo; +/ module bar/++/;") == "bar"); // nested comments require a context-free parser!
	assert(getModuleNameFromContent("/*\nmodule sometest;\n*/\n\nmodule fakemath;\n") == "fakemath");
}

/**
 * Search for module keyword in file
 */
string getModuleNameFromFile(string filePath) {
	string fileContent = filePath.readText;

	logDiagnostic("Get module name from path: " ~ filePath);
	return getModuleNameFromContent(fileContent);
}
