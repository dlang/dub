/**
	Empty package initialization code.

	Copyright: © 2013 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.init;

import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.core.log;
import dub.package_ : packageInfoFiles, defaultPackageFilename;

import std.datetime;
import std.exception;
import std.file;
import std.path;
import std.format;
import std.process;
import std.string;
import std.algorithm : map;
import std.traits : EnumMembers;
import std.conv : to;

enum InitType
{
	minimal,
	vibe_d,
	deimos,
	custom
}

enum CUSTOM_INIT_PACKAGE_DIR = "custom_init_package";

auto fullInitTypeDescriptions(string fmt="%7s - %s")
{
	return map!(a=>fullInitTypeDescription(a,fmt))( [EnumMembers!InitType] );
}

auto initTypeNames()
{
	return map!(a=>initTypeName(a))( [EnumMembers!InitType] );
}

string fullInitTypeDescription(InitType type, string fmt="%7s - %s")
{
	return format( fmt, initTypeName(type), initTypeDescription(type) );
}

string initTypeName(InitType type)
{
	switch(type)
	{
		default: return type.to!string;
		case InitType.vibe_d: return "vibe.d";
	}
}

string initTypeDescription(InitType type)
{
	final switch(type)
	{
		case InitType.minimal: return "simple \"hello world\" project (default)";
		case InitType.vibe_d:  return "minimal HTTP server based on vibe.d";
		case InitType.deimos:  return "skeleton for C header bindings";
		case InitType.custom:  return format("skeleton from user/dub/path/%s", CUSTOM_INIT_PACKAGE_DIR);
	}
}

void initPackage(Path package_path, Path user_dub_path, string[string] deps, InitType type)
{
	void enforceDoesNotExist(string filename) {
		enforce(!existsFile(package_path ~ filename), "The target directory already contains a '"~filename~"' file. Aborting.");
	}

	//Check to see if a target directory needs to be created
	if( !package_path.empty ){
		if( !existsFile(package_path) )
			createDirectory(package_path);
	}

	//Make sure we do not overwrite anything accidentally
	foreach (fil; packageInfoFiles)
		enforceDoesNotExist(fil.filename);

	auto files = ["source/", "views/", "public/", "dub.json", ".gitignore"];
	foreach (fil; files)
		enforceDoesNotExist(fil);

	final switch (type) {
		case InitType.minimal: initMinimalPackage(package_path, deps); break;
		case InitType.vibe_d:  initVibeDPackage(package_path, deps); break;
		case InitType.deimos:  initDeimosPackage(package_path, deps); break;
		case InitType.custom:  initCustomPackage(package_path, user_dub_path ~ CUSTOM_INIT_PACKAGE_DIR, deps); break;
	}
	writeGitignore(package_path);
}

void initMinimalPackage(Path package_path, string[string] deps)
{
	writePackageJson(package_path, "A minimal D application.", deps);
	createDirectory(package_path ~ "source");
	write((package_path ~ "source/app.d").toNativeString(),
q{import std.stdio;

void main()
{
	writeln("Edit source/app.d to start your project.");
}
});
}

void initVibeDPackage(Path package_path, string[string] deps)
{
	if("vibe-d" !in deps)
		deps["vibe-d"] = "~>0.7.19";

	writePackageJson(package_path, "A simple vibe.d server application.",
	                 deps, ["versions": `["VibeDefaultMain"]`]);
	createDirectory(package_path ~ "source");
	createDirectory(package_path ~ "views");
	createDirectory(package_path ~ "public");
	write((package_path ~ "source/app.d").toNativeString(),
q{import vibe.d;

shared static this()
{
	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.bindAddresses = ["::1", "127.0.0.1"];
	listenHTTP(settings, &hello);

	logInfo("Please open http://127.0.0.1:8080/ in your browser.");
}

void hello(HTTPServerRequest req, HTTPServerResponse res)
{
	res.writeBody("Hello, World!");
}
});
}

void initDeimosPackage(Path package_path, string[string] deps)
{
	auto name = package_path.head.toString().toLower();
	writePackageJson(package_path, "Deimos Bindings for "~name~".",
	                 deps, ["targetType": `"sourceLibrary"`, "importPaths": `["."]`]);
	createDirectory(package_path ~ "C");
	createDirectory(package_path ~ "deimos");
}

void writePackageJson(Path package_path, string description, string[string] dependencies = null, string[string] addFields = null)
{
	assert(!package_path.empty);

	string username;
	version (Windows) username = environment.get("USERNAME", "Peter Parker");
	else username = environment.get("USER", "Peter Parker");

	auto fil = openFile(package_path ~ defaultPackageFilename, FileMode.Append);
	scope(exit) fil.close();

	fil.formattedWrite("{\n\t\"name\": \"%s\",\n", package_path.head.toString().toLower());
	fil.formattedWrite("\t\"description\": \"%s\",\n", description);
	fil.formattedWrite("\t\"copyright\": \"Copyright © %s, %s\",\n", Clock.currTime().year, username);
	fil.formattedWrite("\t\"authors\": [\"%s\"],\n", username);
	fil.formattedWrite("\t\"dependencies\": {");
	fil.formattedWrite("%(\n\t\t%s: %s,%)", dependencies);
	fil.formattedWrite("\n\t}");
	fil.formattedWrite("%-(,\n\t\"%s\": %s%)", addFields);
	fil.write("\n}\n");
}

void writeGitignore(Path package_path)
{
	write((package_path ~ ".gitignore").toNativeString(),
		".dub\ndocs.json\n__dummy.html\n*.o\n*.obj\n");
}

void initCustomPackage(Path package_path, Path custom_package_path, string[string] deps)
{
	enforce(existsFile(custom_package_path), format("no custom package in dub path (%s)", custom_package_path));
	enforce(isDir(custom_package_path.toString()), "custom package in dub path not a dir");

	auto cpps = custom_package_path.toString();
	foreach (file; dirEntries(cpps, SpanMode.breadth))
	{
		auto dst = (package_path ~ file.name.relativePath(cpps)).toString();
		if (file.isDir)
			mkdir(dst);
		else
			copy(file.name, dst);
	}
}
