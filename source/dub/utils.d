/**
	...
	
	Copyright: © 2012 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff
*/
module dub.utils;

import vibecompat.core.file;
import vibecompat.core.log;
import vibecompat.data.json;
import vibecompat.inet.url;

// todo: cleanup imports.
import std.array;
import std.file;
import std.exception;
import std.algorithm;
import std.zip;
import std.typecons;
import std.conv;
import stdx.process;


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
		logDebug("Running %s", cmd);
		Pid pid;
		if( env ) pid = spawnShell(cmd, env);
		else pid = spawnShell(cmd);
		auto exitcode = pid.wait();
		enforce(exitcode == 0, "Command failed with exit code "~to!string(exitcode));
	}
}
