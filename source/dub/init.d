/**
	Empty package initialization code.

	Copyright: © 2013 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.init;

import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.core.log;
import dub.package_ : packageInfoFiles, defaultPackageFilename, Package;

import std.datetime;
import std.exception;
import std.file;
import std.path;
import std.format;
import std.process;
import std.string;
import std.algorithm : map;
import std.array;
import std.traits : EnumMembers;
import std.conv : to;
import std.stdio : File;

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

void initPackage(Path package_root, Path user_dub_path, string[string] deps, InitType type)
{
	void enforceDoesNotExist(string filename) {
		enforce(!existsFile(package_root ~ filename), "The target directory already contains a '"~filename~"' file. Aborting.");
	}

	//Check to see if a target directory needs to be created
	if( !package_root.empty ){
		if( !existsFile(package_root) )
			createDirectory(package_root);
	}

	//Make sure we do not overwrite anything accidentally
	foreach (fil; packageInfoFiles)
		enforceDoesNotExist(fil.filename);

	auto files = ["source/", "views/", "public/", "dub.json", ".gitignore"];
	foreach (fil; files)
		enforceDoesNotExist(fil);

	final switch (type) {
		case InitType.minimal: initMinimalPackage(package_root, deps); break;
		case InitType.vibe_d:  initVibeDPackage(package_root, deps); break;
		case InitType.deimos:  initDeimosPackage(package_root, deps); break;
		case InitType.custom:  initCustomPackage(package_root, user_dub_path ~ CUSTOM_INIT_PACKAGE_DIR, deps); break;
	}
	writeGitignore(package_root);
}

void initMinimalPackage(Path package_root, string[string] deps)
{
	writePackageJson(package_root, "A minimal D application.", deps);
	createDirectory(package_root ~ "source");
	write((package_root ~ "source/app.d").toNativeString(),
q{import std.stdio;

void main()
{
	writeln("Edit source/app.d to start your project.");
}
});
}

void initVibeDPackage(Path package_root, string[string] deps)
{
	if("vibe-d" !in deps)
		deps["vibe-d"] = "~>0.7.19";

	writePackageJson(package_root, "A simple vibe.d server application.",
	                 deps, ["versions": `["VibeDefaultMain"]`]);
	createDirectory(package_root ~ "source");
	createDirectory(package_root ~ "views");
	createDirectory(package_root ~ "public");
	write((package_root ~ "source/app.d").toNativeString(),
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

void initDeimosPackage(Path package_root, string[string] deps)
{
	auto name = package_root.head.toString().toLower();
	writePackageJson(package_root, "Deimos Bindings for "~name~".",
	                 deps, ["targetType": `"sourceLibrary"`, "importPaths": `["."]`]);
	createDirectory(package_root ~ "C");
	createDirectory(package_root ~ "deimos");
}

void writePackageJson(Path package_root, string description, string[string] dependencies = null, string[string] addFields = null)
{
	assert(!package_root.empty);

	string username;
	version (Windows) enum USER_VAR = "USERNAME";
	else enum USER_VAR = "USER";
	environment.get(USER_VAR, "Peter Parker");

	auto fil = openFile(package_root ~ defaultPackageFilename, FileMode.Append);
	scope(exit) fil.close();

	fil.formattedWrite("{\n\t\"name\": \"%s\",\n", package_root.head.toString().toLower());
	fil.formattedWrite("\t\"description\": \"%s\",\n", description);
	fil.formattedWrite("\t\"copyright\": \"Copyright © %s, %s\",\n", Clock.currTime().year, username);
	fil.formattedWrite("\t\"authors\": [\"%s\"],\n", username);
	fil.formattedWrite("\t\"dependencies\": {");
	fil.formattedWrite("%(\n\t\t%s: %s,%)", dependencies);
	fil.formattedWrite("\n\t}");
	fil.formattedWrite("%-(,\n\t\"%s\": %s%)", addFields);
	fil.write("\n}\n");
}

void writeGitignore(Path package_root)
{
	write((package_root ~ ".gitignore").toNativeString(),
		".dub\ndocs.json\n__dummy.html\n*.o\n*.obj\n");
}

void initCustomPackage(Path package_root, Path custom_package_path, string[string] deps)
{
	enforce(existsFile(custom_package_path), format("no custom package in dub path (%s)", custom_package_path));
	enforce(isDir(custom_package_path.toString()), "custom package in dub path not a dir");

	auto cpps = custom_package_path.toString();
	auto package_name = package_root.head.toString();

	foreach (file; dirEntries(cpps, SpanMode.breadth))
	{
		auto dst = (package_root ~ file.name.relativePath(cpps)).toString();
		if (file.isDir) mkdir(dst);
		else
		{
			auto templ = File(file.name,"r");
			scope(exit) templ.close();

			auto res = File(dst,"w");
			scope(exit) res.close();

			foreach (ln; templ.byLine)
				res.writeln(replaceTemplateVarialbes(ln.idup, package_name, deps));
		}
	}
}

string replaceTemplateVarialbes(string line, string name, string[string] deps )
{
	return line
		.replace("$name", name.toLower())
		.replace("$Name", name)
		.replace("$deps_json", deps.byKeyValue.map!(a=>format(`"%s": "%s"`,a.key,a.value)).join(", ") )
		;
}
