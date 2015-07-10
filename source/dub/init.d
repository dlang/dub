/**
	Empty package initialization code.

	Copyright: © 2013-2015 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.init;

import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.core.log;
import dub.package_ : PackageFormat, packageInfoFiles, defaultPackageFilename;

import std.datetime;
import std.exception;
import std.file;
import std.format;
import std.process;
import std.string;


void initPackage(Path root_path, string[string] deps, string type, PackageFormat format)
{
	void enforceDoesNotExist(string filename) {
		enforce(!existsFile(root_path ~ filename), "The target directory already contains a '"~filename~"' file. Aborting.");
	}

	//Check to see if a target directory needs to be created
	if( !root_path.empty ){
		if( !existsFile(root_path) )
			createDirectory(root_path);
	}

	//Make sure we do not overwrite anything accidentally
	foreach (fil; packageInfoFiles)
		enforceDoesNotExist(fil.filename);

	auto files = ["source/", "views/", "public/", "dub.json", ".gitignore"];
	foreach (fil; files)
		enforceDoesNotExist(fil);

	switch (type) {
		default: throw new Exception("Unknown package init type: "~type);
		case "minimal": initMinimalPackage(root_path, deps, format); break;
		case "vibe.d": initVibeDPackage(root_path, deps, format); break;
		case "deimos": initDeimosPackage(root_path, deps, format); break;
	}
	writeGitignore(root_path);
}

void initMinimalPackage(Path root_path, string[string] deps, PackageFormat format)
{
	writePackageDescription(format, root_path, "A minimal D application.", deps);
	createDirectory(root_path ~ "source");
	write((root_path ~ "source/app.d").toNativeString(),
q{import std.stdio;

void main()
{
	writeln("Edit source/app.d to start your project.");
}
});
}

void initVibeDPackage(Path root_path, string[string] deps, PackageFormat format)
{
	if("vibe-d" !in deps)
		deps["vibe-d"] = "~>0.7.19";

	writePackageDescription(format, root_path, "A simple vibe.d server application.",
	                 deps, ["versions": ["VibeDefaultMain"]]);
	createDirectory(root_path ~ "source");
	createDirectory(root_path ~ "views");
	createDirectory(root_path ~ "public");
	write((root_path ~ "source/app.d").toNativeString(),
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

void initDeimosPackage(Path root_path, string[string] deps, PackageFormat format)
{
	auto name = root_path.head.toString().toLower();
	writePackageDescription(format, root_path, "Deimos Bindings for "~name~".",
		deps, ["importPaths": ["."]], ["targetType": "sourceLibrary"]);
	createDirectory(root_path ~ "C");
	createDirectory(root_path ~ "deimos");
}

void writePackageDescription(PackageFormat format, Path root_path, string description, string[string] dependencies = null, string[][string] array_fields = null, string[string] string_fields = null)
{
	final switch (format) {
		case PackageFormat.json:
			foreach (f, v; array_fields) string_fields[f] = .format("[%(%s, %)]", v);
			writePackageJSON(root_path, description, dependencies, string_fields);
			break;
		case PackageFormat.sdl:
			foreach (f, v; array_fields) string_fields[f] = .format("%(%s %)", v);
			writePackageSDL(root_path, description, dependencies, string_fields);
			break;
	}
}

private void writePackageJSON(Path root_path, string description, string[string] dependencies = null, string[string] raw_fields = null)
{
	import std.algorithm : map;

	assert(!root_path.empty);

	string username;
	version (Windows) username = environment.get("USERNAME", "Peter Parker");
	else username = environment.get("USER", "Peter Parker");

	auto fil = openFile(root_path ~ "dub.json", FileMode.append);
	scope(exit) fil.close();

	fil.formattedWrite("{\n\t\"name\": \"%s\",\n", root_path.head.toString().toLower());
	fil.formattedWrite("\t\"description\": \"%s\",\n", description);
	fil.formattedWrite("\t\"copyright\": \"Copyright © %s, %s\",\n", Clock.currTime().year, username);
	fil.formattedWrite("\t\"authors\": [\"%s\"],\n", username);
	fil.formattedWrite("\t\"dependencies\": {");
	fil.formattedWrite("%(\n\t\t%s: %s,%)", dependencies);
	fil.formattedWrite("\n\t}");
	fil.formattedWrite("%-(,\n\t\"%s\": %s%)", raw_fields);
	fil.write("\n}\n");
}

private void writePackageSDL(Path root_path, string description, string[string] dependencies = null, string[string] raw_fields = null)
{
	import std.algorithm : map;

	assert(!root_path.empty);

	string username;
	version (Windows) username = environment.get("USERNAME", "Peter Parker");
	else username = environment.get("USER", "Peter Parker");

	auto fil = openFile(root_path ~ "dub.sdl", FileMode.append);
	scope(exit) fil.close();

	fil.formattedWrite("name \"%s\"\n", root_path.head.toString().toLower());
	fil.formattedWrite("description \"%s\"\n", description);
	fil.formattedWrite("copyright \"Copyright © %s, %s\"\n", Clock.currTime().year, username);
	fil.formattedWrite("authors \"%s\"\n", username);
	foreach (d, v; dependencies)
		fil.formattedWrite("dependency \"%s\" version=\"%s\"\n", d, v);
	foreach (f, v; raw_fields)
		fil.formattedWrite("%s %s\n", f, v);
}

void writeGitignore(Path root_path)
{
	write((root_path ~ ".gitignore").toNativeString(),
		".dub\ndocs.json\n__dummy.html\n*.o\n*.obj\n");
}
