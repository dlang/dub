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

// todo: cleanup imports.
import core.thread;
import std.algorithm : startsWith;
import std.array;
import std.conv;
import std.exception;
import std.file;
import std.process;
import std.string;
import std.traits : isIntegral;
import std.typecons;
import std.zip;
version(DubUseCurl) import std.net.curl;


private Path[] temporary_files;

Path getTempDir()
{
	return Path(std.file.tempDir());
}

Path getTempFile(string prefix, string extension = null)
{
	import std.uuid : randomUUID;

	auto path = getTempDir() ~ (prefix ~ "-" ~ randomUUID.toString() ~ extension);
	temporary_files ~= path;
	return path;
}

// lockfile based on atomic mkdir
struct LockFile
{
	bool opCast(T:bool)() { return !!path; }
	~this() { if (path) rmdir(path); }
	string path;
}

auto tryLockFile(string path)
{
	import std.file;
	if (collectException(mkdir(path)))
		return LockFile(null);
	return LockFile(path);
}

auto lockFile(string path, Duration wait)
{
	import std.datetime, std.file;
	auto t0 = Clock.currTime();
	auto dur = 1.msecs;
	while (true)
	{
		if (!collectException(mkdir(path)))
			return LockFile(path);
		enforce(Clock.currTime() - t0 < wait, "Failed to lock '"~path~"'.");
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

bool isEmptyDir(Path p) {
	foreach(DirEntry e; dirEntries(p.toNativeString(), SpanMode.shallow))
		return false;
	return true;
}

bool isWritableDir(Path p, bool create_if_missing = false)
{
	import std.random;
	auto fname = p ~ format("__dub_write_test_%08X", uniform(0, uint.max));
	if (create_if_missing && !exists(p.toNativeString())) mkdirRecurse(p.toNativeString());
	try openFile(fname, FileMode.createTrunc).close();
	catch (Exception) return false;
	remove(fname.toNativeString());
	return true;
}

Json jsonFromFile(Path file, bool silent_fail = false) {
	if( silent_fail && !existsFile(file) ) return Json.emptyObject;
	auto f = openFile(file.toNativeString(), FileMode.read);
	scope(exit) f.close();
	auto text = stripUTF8Bom(cast(string)f.readAll());
	return parseJsonString(text, file.toNativeString());
}

Json jsonFromZip(Path zip, string filename) {
	auto f = openFile(zip, FileMode.read);
	ubyte[] b = new ubyte[cast(size_t)f.size];
	f.rawRead(b);
	f.close();
	auto archive = new ZipArchive(b);
	auto text = stripUTF8Bom(cast(string)archive.expand(archive.directory[filename]));
	return parseJsonString(text, zip.toNativeString~"/"~filename);
}

void writeJsonFile(Path path, Json json)
{
	auto f = openFile(path, FileMode.createTrunc);
	scope(exit) f.close();
	f.writePrettyJsonString(json);
}

/// Performs a write->delete->rename sequence to atomically "overwrite" the destination file
void atomicWriteJsonFile(Path path, Json json)
{
	import std.random : uniform;
	auto tmppath = path[0 .. $-1] ~ format("%s.%s.tmp", path.head, uniform(0, int.max));
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

bool isPathFromZip(string p) {
	enforce(p.length > 0);
	return p[$-1] == '/';
}

bool existsDirectory(Path path) {
	if( !existsFile(path) ) return false;
	auto fi = getFileInfo(path);
	return fi.isDirectory;
}

void runCommand(string command, string[string] env = null)
{
	runCommands((&command)[0 .. 1], env);
}

void runCommands(in string[] commands, string[string] env = null)
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
		pid = spawnShell(cmd, stdin, childStdout, childStderr, env, config);
		auto exitcode = pid.wait();
		enforce(exitcode == 0, "Command failed with exit code "~to!string(exitcode));
	}
}

/**
	Downloads a file from the specified URL.

	Any redirects will be followed until the actual file resource is reached or if the redirection
	limit of 10 is reached. Note that only HTTP(S) is currently supported.
*/
void download(string url, string filename)
{
	version(DubUseCurl) {
		auto conn = HTTP();
		setupHTTPClient(conn);
		logDebug("Storing %s...", url);
		std.net.curl.download(url, filename, conn);
		enforce(conn.statusLine.code < 400,
			format("Failed to download %s: %s %s",
				url, conn.statusLine.code, conn.statusLine.reason));
	} else version (Have_vibe_d) {
		import vibe.inet.urltransfer;
		vibe.inet.urltransfer.download(url, filename);
	} else assert(false);
}
/// ditto
void download(URL url, Path filename)
{
	download(url.toString(), filename.toNativeString());
}
/// ditto
ubyte[] download(string url)
{
	version(DubUseCurl) {
		auto conn = HTTP();
		setupHTTPClient(conn);
		logDebug("Getting %s...", url);
		auto ret = cast(ubyte[])get(url, conn);
		enforce(conn.statusLine.code < 400,
			format("Failed to GET %s: %s %s",
				url, conn.statusLine.code, conn.statusLine.reason));
		return ret;
	} else version (Have_vibe_d) {
		import vibe.inet.urltransfer;
		import vibe.stream.operations;
		ubyte[] ret;
		vibe.inet.urltransfer.download(url, (scope input) { ret = input.readAll(); });
		return ret;
	} else assert(false);
}
/// ditto
ubyte[] download(URL url)
{
	return download(url.toString());
}

/// Returns the current DUB version in semantic version format
string getDUBVersion()
{
	import dub.version_;
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

version(DubUseCurl) {
	void setupHTTPClient(ref HTTP conn)
	{
		static if( is(typeof(&conn.verifyPeer)) )
			conn.verifyPeer = false;

		auto proxy = environment.get("http_proxy", null);
		if (proxy.length) conn.proxy = proxy;

		conn.addRequestHeader("User-Agent", "dub/"~getDUBVersion()~" (std.net.curl; +https://github.com/rejectedsoftware/dub)");
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

string determineModuleName(BuildSettings settings, Path file, Path base_path)
{
	import std.algorithm : map;

	assert(base_path.absolute);
	if (!file.absolute) file = base_path ~ file;

	size_t path_skip = 0;
	foreach (ipath; settings.importPaths.map!(p => Path(p))) {
		if (!ipath.absolute) ipath = base_path ~ ipath;
		assert(!ipath.empty);
		if (file.startsWith(ipath) && ipath.length > path_skip)
			path_skip = ipath.length;
	}

	enforce(path_skip > 0,
		format("Source file '%s' not found in any import path.", file.toNativeString()));

	auto mpath = file[path_skip .. file.length];
	auto ret = appender!string;

	//search for module keyword in file
	string moduleName = getModuleNameFromFile(file.to!string);

	if(moduleName.length) return moduleName;

	//create module name from path
	foreach (i; 0 .. mpath.length) {
		import std.path;
		auto p = mpath[i].toString();
		if (p == "package.d") break;
		if (i > 0) ret ~= ".";
		if (i+1 < mpath.length) ret ~= p;
		else ret ~= p.baseName(".d");
	}

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
		comments_pattern = regex(`(/\*([^*]|[\r\n]|(\*+([^*/]|[\r\n])))*\*+/)|(//.*)`, "g");
		module_pattern = regex(`module\s+([\w\.]+)\s*;`, "g");
		regex_initialized = true;
	}

	content = replaceAll(content, comments_pattern, "");
	auto result = matchFirst(content, module_pattern);

	string moduleName;
	if(!result.empty) moduleName = result.front;

	if (moduleName.length >= 7) moduleName = moduleName[7..$-1];

	return moduleName;
}

unittest {
	//test empty string
	string name = getModuleNameFromContent("");
	assert(name == "", "can't get module name from empty string");

	//test simple name
	name = getModuleNameFromContent("module myPackage.myModule;");
	assert(name == "myPackage.myModule", "can't parse module name");

	//test if it can ignore module inside comments
	name = getModuleNameFromContent("/**
	module fakePackage.fakeModule;
	*/
	module myPackage.myModule;");

	assert(name == "myPackage.myModule", "can't parse module name");

	name = getModuleNameFromContent("//module fakePackage.fakeModule;
	module myPackage.myModule;");

	assert(name == "myPackage.myModule", "can't parse module name");
}

/**
 * Search for module keyword in file
 */
string getModuleNameFromFile(string filePath) {
	string fileContent = filePath.readText;

	logDiagnostic("Get module name from path: " ~ filePath);
	return getModuleNameFromContent(fileContent);
}
