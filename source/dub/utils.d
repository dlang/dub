/**
	...
	
	Copyright: © 2012 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff
*/
module dub.utils;

import dub.internal.std.process;
import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.data.json;
import dub.internal.vibecompat.inet.url;
import dub.version_;

// todo: cleanup imports.
import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.file;
import std.net.curl;
import std.typecons;
import std.zip;


package bool isEmptyDir(Path p) {
	foreach(DirEntry e; dirEntries(p.toNativeString(), SpanMode.shallow))
		return false;
	return true;
}

package Json jsonFromFile(Path file, bool silent_fail = false) {
	if( silent_fail && !existsFile(file) ) return Json.EmptyObject;
	auto f = openFile(file.toNativeString(), FileMode.Read);
	scope(exit) f.close();
	auto text = stripUTF8Bom(cast(string)f.readAll());
	return parseJson(text);
}

package Json jsonFromZip(Path zip, string filename) {
	auto f = openFile(zip, FileMode.Read);
	ubyte[] b = new ubyte[cast(size_t)f.size];
	f.rawRead(b);
	f.close();
	auto archive = new ZipArchive(b);
	auto text = stripUTF8Bom(cast(string)archive.expand(archive.directory[filename]));
	return parseJson(text);
}

package void writeJsonFile(Path path, Json json)
{
	auto f = openFile(path, FileMode.CreateTrunc);
	scope(exit) f.close();
	f.writePrettyJsonString(json);
}

package bool isPathFromZip(string p) {
	enforce(p.length > 0);
	return p[$-1] == '/';
}

package bool existsDirectory(Path path) {
	if( !existsFile(path) ) return false;
	auto fi = getFileInfo(path);
	return fi.isDirectory;
}

private string stripUTF8Bom(string str)
{
	if( str.length >= 3 && str[0 .. 3] == [0xEF, 0xBB, 0xBF] )
		return str[3 ..$];
	return str;
}

void runCommands(string[] commands, string[string] env = null)
{
	foreach(cmd; commands){
		logDiagnostic("Running %s", cmd);
		Pid pid;
		if( env !is null ) pid = spawnShell(cmd, env);
		else pid = spawnShell(cmd);
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
	auto conn = setupHTTPClient();
	logDebug("Storing %s...", url);
	std.net.curl.download(url, filename, conn);
}
/// ditto
void download(Url url, Path filename)
{
	download(url.toString(), filename.toNativeString());
}
/// ditto
char[] download(string url)
{
	auto conn = setupHTTPClient();
	logDebug("Getting %s...", url);
	return get(url, conn);
}
/// ditto
char[] download(Url url)
{
	return download(url.toString());
}

private HTTP setupHTTPClient()
{
	auto conn = HTTP();
	static if( is(typeof(&conn.verifyPeer)) )
		conn.verifyPeer = false;
	conn.addRequestHeader("User-Agent", "dub/"~dubVersion~" (std.net.curl; +https://github.com/rejectedsoftware/dub)");
	return conn;
}