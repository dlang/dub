/**
	Package skeleton initialization code.

	Copyright: © 2013-2016 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.init;

import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.core.log;
import dub.package_ : PackageFormat, packageInfoFiles, defaultPackageFilename;
import dub.recipe.packagerecipe;
import dub.dependency;

import std.datetime;
import std.exception;
import std.file;
import std.format;
import std.process;
import std.string;


/** Intializes a new package in the given directory.

	The given `root_path` will be checked for any of the files that will be
	created	by this function. If any exist, an exception will be thrown before
	altering the directory.

	Params:
		root_path = Directory in which to create the new package. If the
			directory doesn't exist, a new one will be created.
		deps = A set of extra dependencies to add to the package recipe. The
			associative array is expected to map from package name to package
			version.
		type = The type of package skeleton to create. Can currently be
			"minimal", "vibe.d" or "deimos"
		recipe_callback = Optional callback that can be used to customize the
			package recipe and the file format used to store it prior to
			writing it to disk.
*/
void initPackage(Path root_path, string[string] deps, string type,
	PackageFormat format, scope void delegate(ref PackageRecipe, ref PackageFormat) recipe_callback = null)
{
	import std.conv : to;
	import dub.recipe.io : writePackageRecipe;

	void enforceDoesNotExist(string filename) {
		enforce(!existsFile(root_path ~ filename), "The target directory already contains a '"~filename~"' file. Aborting.");
	}

	string username = getUserName();

	PackageRecipe p;
	p.name = root_path.head.toString().toLower();
	p.authors ~= username;
	p.license = "proprietary";
	p.copyright = .format("Copyright © %s, %s", Clock.currTime().year, username);
	foreach (pack, v; deps) {
		import std.ascii : isDigit;
		p.buildSettings.dependencies[pack] = Dependency(v);
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
		case "minimal": initMinimalPackage(root_path, p); break;
		case "vibe.d": initVibeDPackage(root_path, p); break;
		case "deimos": initDeimosPackage(root_path, p); break;
	}

	if (recipe_callback) recipe_callback(p, format);
	writePackageRecipe(root_path ~ ("dub."~format.to!string), p);
	writeGitignore(root_path);
}

private void initMinimalPackage(Path root_path, ref PackageRecipe p)
{
	p.description = "A minimal D application.";
	createDirectory(root_path ~ "source");
	write((root_path ~ "source/app.d").toNativeString(),
q{import std.stdio;

void main()
{
	writeln("Edit source/app.d to start your project.");
}
});
}

private void initVibeDPackage(Path root_path, ref PackageRecipe p)
{
	if ("vibe-d" !in p.buildSettings.dependencies)
		p.buildSettings.dependencies["vibe-d"] = Dependency("~>0.7.26");
	p.description = "A simple vibe.d server application.";
	p.buildSettings.versions[""] ~= "VibeDefaultMain";

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

private void initDeimosPackage(Path root_path, ref PackageRecipe p)
{
	import dub.compilers.buildsettings : TargetType;

	auto name = root_path.head.toString().toLower();
	p.description = format("Deimos Bindings for "~p.name~".");
	p.buildSettings.importPaths[""] ~= ".";
	p.buildSettings.targetType = TargetType.sourceLibrary;
	createDirectory(root_path ~ "C");
	createDirectory(root_path ~ "deimos");
}

private void writeGitignore(Path root_path)
{
	write((root_path ~ ".gitignore").toNativeString(),
		".dub\ndocs.json\n__dummy.html\n*.o\n*.obj\n");
}

private string getUserName()
{
	version (Windows)
		return environment.get("USERNAME", "Peter Parker");
	else version (Posix)
	{
		import core.sys.posix.pwd, core.sys.posix.unistd, core.stdc.string : strlen;
		import std.algorithm : splitter;

		if (auto pw = getpwuid(getuid))
		{
			auto uinfo = pw.pw_gecos[0 .. strlen(pw.pw_gecos)].splitter(',');
			if (!uinfo.empty && uinfo.front.length)
				return uinfo.front.idup;
		}
		return environment.get("USER", "Peter Parker");
	}
	else
		static assert(0);
}
