/**
	Package skeleton initialization code.

	Copyright: © 2013-2016 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.init;

import dub.internal.vibecompat.core.file;
import dub.logging;
import dub.package_ : PackageFormat, packageInfoFiles, defaultPackageFilename;
import dub.recipe.packagerecipe;
import dub.dependency;

import std.exception;
import std.file;
import std.format;
import std.process;
import std.string;


/** Initializes a new package in the given directory.

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
void initPackage(NativePath root_path, string[string] deps, string type,
	PackageFormat format, scope RecipeCallback recipe_callback = null)
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
	foreach (pack, v; deps) {
		import std.ascii : isDigit;
		p.buildSettings.dependencies[pack] = Dependency(v);
	}

	//Check to see if a target directory needs to be created
	if (!root_path.empty) {
		if (!existsFile(root_path))
			createDirectory(root_path);
	}

	//Make sure we do not overwrite anything accidentally
	foreach (fil; packageInfoFiles)
		enforceDoesNotExist(fil.filename);

	auto files = ["source/", "views/", "public/", "dub.json"];
	foreach (fil; files)
		enforceDoesNotExist(fil);

	void processRecipe()
	{
		if (recipe_callback)
			recipe_callback(p, format);
	}

	switch (type) {
		default: throw new Exception("Unknown package init type: "~type);
		case "minimal": initMinimalPackage(root_path, p, &processRecipe); break;
		case "vibe.d": initVibeDPackage(root_path, p, &processRecipe); break;
		case "deimos": initDeimosPackage(root_path, p, &processRecipe); break;
	}

	writePackageRecipe(root_path ~ ("dub."~format.to!string), p);
	writeGitignore(root_path, p.name);
}

alias RecipeCallback = void delegate(ref PackageRecipe, ref PackageFormat);

private void initMinimalPackage(NativePath root_path, ref PackageRecipe p, scope void delegate() pre_write_callback)
{
	p.description = "A minimal D application.";
	pre_write_callback();

	createDirectory(root_path ~ "source");
	write((root_path ~ "source/app.d").toNativeString(),
q{import std.stdio;

void main()
{
	writeln("Edit source/app.d to start your project.");
}
});
}

private void initVibeDPackage(NativePath root_path, ref PackageRecipe p, scope void delegate() pre_write_callback)
{
	if ("vibe-d" !in p.buildSettings.dependencies)
		p.buildSettings.dependencies["vibe-d"] = Dependency("~>0.8.2");
	p.description = "A simple vibe.d server application.";
	pre_write_callback();

	createDirectory(root_path ~ "source");
	createDirectory(root_path ~ "views");
	createDirectory(root_path ~ "public");
	write((root_path ~ "source/app.d").toNativeString(),
q{import vibe.vibe;

void main()
{
	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.bindAddresses = ["::1", "127.0.0.1"];
	listenHTTP(settings, &hello);

	logInfo("Please open http://127.0.0.1:8080/ in your browser.");
	runApplication();
}

void hello(HTTPServerRequest req, HTTPServerResponse res)
{
	res.writeBody("Hello, World!");
}
});
}

private void initDeimosPackage(NativePath root_path, ref PackageRecipe p, scope void delegate() pre_write_callback)
{
	import dub.compilers.buildsettings : TargetType;

	auto name = root_path.head.toString().toLower();
	p.description = format("Deimos Bindings for "~p.name~".");
	p.buildSettings.importPaths[""] ~= ".";
	p.buildSettings.targetType = TargetType.sourceLibrary;
	pre_write_callback();

	createDirectory(root_path ~ "C");
	createDirectory(root_path ~ "deimos");
}

/**
 * Write the `.gitignore` file to the directory, if it does not already exists
 *
 * As `dub` is often used with `git`, adding a `.gitignore` is a nice touch for
 * most users. However, this file is not mandatory for `dub` to do its job,
 * so we do not depend on the content.
 * One important use case we need to support is people running `dub init` on
 * a Github-initialized repository. Those might already contain a `.gitignore`
 * (and a README and a LICENSE), thus we should not bail out if the file already
 * exists, just ignore it.
 *
 * Params:
 *   root_path = The path to the directory hosting the project
 *   pkg_name = Name of the package, to generate a list of binaries to ignore
 */
private void writeGitignore(NativePath root_path, const(char)[] pkg_name)
{
    auto full_path = (root_path ~ ".gitignore").toNativeString();

    if (existsFile(full_path))
        return;

    write(full_path,
q"{.dub
docs.json
__dummy.html
docs/
%1$s.so
%1$s.dylib
%1$s.dll
%1$s.a
%1$s.lib
%1$s-test-*
*.exe
*.o
*.obj
*.lst
}".format(pkg_name));
}

private string getUserName()
{
	version (Windows)
		return environment.get("USERNAME", "Peter Parker");
	else version (Posix)
	{
		import core.sys.posix.pwd, core.sys.posix.unistd, core.stdc.string : strlen;
		import std.algorithm : splitter;

		// Bionic doesn't have pw_gecos on ARM
		version(CRuntime_Bionic) {} else
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
