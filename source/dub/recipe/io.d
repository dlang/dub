/**
	Package recipe reading/writing facilities.

	Copyright: © 2015-2016, Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.recipe.io;

import dub.recipe.packagerecipe;
import vibe.inet.path;


/** Reads a package recipe from a file.

	The file format (JSON/SDLang) will be determined from the file extension.

	Params:
		filename = NativePath of the package recipe file
		parent_name = Optional name of the parent package (if this is a sub package)

	Returns: Returns the package recipe contents
	Throws: Throws an exception if an I/O or syntax error occurs
*/
PackageRecipe readPackageRecipe(string filename, string parent_name = null)
{
	return readPackageRecipe(NativePath(filename), parent_name);
}
/// ditto
PackageRecipe readPackageRecipe(NativePath filename, string parent_name = null)
{
	import dub.internal.utils : stripUTF8Bom;
	import dub.internal.vibecompat.core.file : openFile, FileMode;

	string text;

	{
		auto f = openFile(filename.toNativeString(), FileMode.read);
		scope(exit) f.close();
		text = stripUTF8Bom(cast(string)f.readAll());
	}

	return parsePackageRecipe(text, filename.toNativeString(), parent_name);
}

/** Parses an in-memory package recipe.

	The file format (JSON/SDLang) will be determined from the file extension.

	Params:
		contents = The contents of the recipe file
		filename = Name associated with the package recipe - this is only used
			to determine the file format from the file extension
		parent_name = Optional name of the parent package (if this is a sub
		package)
		default_package_name = Optional default package name (if no package name
		is found in the recipe this value will be used)

	Returns: Returns the package recipe contents
	Throws: Throws an exception if an I/O or syntax error occurs
*/
PackageRecipe parsePackageRecipe(string contents, string filename, string parent_name = null,
								 string default_package_name = null)
{
	import std.algorithm : endsWith;
	import vibe.data.json;
	import dub.recipe.json : parseJson;
	import dub.recipe.sdl : parseSDL;

	PackageRecipe ret;

	ret.name = default_package_name;

	if (filename.endsWith(".json")) parseJson(ret, parseJsonString(contents, filename), parent_name);
	else if (filename.endsWith(".sdl")) parseSDL(ret, contents, parent_name, filename);
	else assert(false, "readPackageRecipe called with filename with unknown extension: "~filename);
	return ret;
}


unittest { // issue #711 - configuration default target type not correct for SDL
	import dub.compilers.buildsettings : TargetType;
	auto inputs = [
		"dub.sdl": "name \"test\"\nconfiguration \"a\" {\n}",
		"dub.json": "{\"name\": \"test\", \"configurations\": [{\"name\": \"a\"}]}"
	];
	foreach (file, content; inputs) {
		auto pr = parsePackageRecipe(content, file);
		assert(pr.name == "test");
		assert(pr.configurations.length == 1);
		assert(pr.configurations[0].name == "a");
		assert(pr.configurations[0].buildSettings.targetType == TargetType.library);
	}
}

unittest { // issue #711 - configuration default target type not correct for SDL
	import dub.compilers.buildsettings : TargetType;
	auto inputs = [
		"dub.sdl": "name \"test\"\ntargetType \"autodetect\"\nconfiguration \"a\" {\n}",
		"dub.json": "{\"name\": \"test\", \"targetType\": \"autodetect\", \"configurations\": [{\"name\": \"a\"}]}"
	];
	foreach (file, content; inputs) {
		auto pr = parsePackageRecipe(content, file);
		assert(pr.name == "test");
		assert(pr.configurations.length == 1);
		assert(pr.configurations[0].name == "a");
		assert(pr.configurations[0].buildSettings.targetType == TargetType.library);
	}
}

unittest { // issue #711 - configuration default target type not correct for SDL
	import dub.compilers.buildsettings : TargetType;
	auto inputs = [
		"dub.sdl": "name \"test\"\ntargetType \"executable\"\nconfiguration \"a\" {\n}",
		"dub.json": "{\"name\": \"test\", \"targetType\": \"executable\", \"configurations\": [{\"name\": \"a\"}]}"
	];
	foreach (file, content; inputs) {
		auto pr = parsePackageRecipe(content, file);
		assert(pr.name == "test");
		assert(pr.configurations.length == 1);
		assert(pr.configurations[0].name == "a");
		assert(pr.configurations[0].buildSettings.targetType == TargetType.executable);
	}
}


/** Writes the textual representation of a package recipe to a file.

	Note that the file extension must be either "json" or "sdl".
*/
void writePackageRecipe(string filename, const scope ref PackageRecipe recipe)
{
	import dub.internal.vibecompat.core.file : openFile, FileMode;
	auto f = openFile(filename, FileMode.createTrunc);
	scope(exit) f.close();
	serializePackageRecipe(f, recipe, filename);
}

/// ditto
void writePackageRecipe(NativePath filename, const scope ref PackageRecipe recipe)
{
	writePackageRecipe(filename.toNativeString, recipe);
}

/** Converts a package recipe to its textual representation.

	The extension of the supplied `filename` must be either "json" or "sdl".
	The output format is chosen accordingly.
*/
void serializePackageRecipe(R)(ref R dst, const scope ref PackageRecipe recipe, string filename)
{
	import std.algorithm : endsWith;
	import vibe.data.json : writeJsonString;
	import dub.recipe.json : toJson;
	import dub.recipe.sdl : toSDL;

	if (filename.endsWith(".json"))
		dst.writeJsonString!(R, true)(toJson(recipe));
	else if (filename.endsWith(".sdl"))
		toSDL(recipe).toSDLDocument(dst);
	else assert(false, "writePackageRecipe called with filename with unknown extension: "~filename);
}
