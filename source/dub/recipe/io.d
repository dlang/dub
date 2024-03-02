/**
	Package recipe reading/writing facilities.

	Copyright: © 2015-2016, Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.recipe.io;

import dub.dependency : PackageName;
import dub.recipe.packagerecipe;
import dub.internal.logging;
import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.inet.path;
import dub.internal.configy.Read;

/** Reads a package recipe from a file.

	The file format (JSON/SDLang) will be determined from the file extension.

	Params:
		filename = NativePath of the package recipe file
		parent = Optional name of the parent package (if this is a sub package)
		mode = Whether to issue errors, warning, or ignore unknown keys in dub.json

	Returns: Returns the package recipe contents
	Throws: Throws an exception if an I/O or syntax error occurs
*/
deprecated("Use the overload that accepts a `NativePath` as first argument")
PackageRecipe readPackageRecipe(
	string filename, string parent = null, StrictMode mode = StrictMode.Ignore)
{
	return readPackageRecipe(NativePath(filename), parent, mode);
}

/// ditto
deprecated("Use the overload that accepts a `PackageName` as second argument")
PackageRecipe readPackageRecipe(
	NativePath filename, string parent, StrictMode mode = StrictMode.Ignore)
{
	return readPackageRecipe(filename, parent.length ? PackageName(parent) : PackageName.init, mode);
}


/// ditto
PackageRecipe readPackageRecipe(NativePath filename,
	in PackageName parent = PackageName.init, StrictMode mode = StrictMode.Ignore)
{
	string text = readText(filename);
	return parsePackageRecipe(text, filename.toNativeString(), parent, null, mode);
}

/** Parses an in-memory package recipe.

	The file format (JSON/SDLang) will be determined from the file extension.

	Params:
		contents = The contents of the recipe file
		filename = Name associated with the package recipe - this is only used
			to determine the file format from the file extension
		parent = Optional name of the parent package (if this is a sub
		package)
		default_package_name = Optional default package name (if no package name
		is found in the recipe this value will be used)
		mode = Whether to issue errors, warning, or ignore unknown keys in dub.json

	Returns: Returns the package recipe contents
	Throws: Throws an exception if an I/O or syntax error occurs
*/
deprecated("Use the overload that accepts a `PackageName` as 3rd argument")
PackageRecipe parsePackageRecipe(string contents, string filename, string parent,
	string default_package_name = null, StrictMode mode = StrictMode.Ignore)
{
    return parsePackageRecipe(contents, filename, parent.length ?
        PackageName(parent) : PackageName.init,
        default_package_name, mode);
}

/// Ditto
PackageRecipe parsePackageRecipe(string contents, string filename,
    in PackageName parent = PackageName.init,
	string default_package_name = null, StrictMode mode = StrictMode.Ignore)
{
	import std.algorithm : endsWith;
	import dub.compilers.buildsettings : TargetType;
	import dub.internal.vibecompat.data.json;
	import dub.recipe.json : parseJson;
	import dub.recipe.sdl : parseSDL;

	PackageRecipe ret;

	ret.name = default_package_name;

	if (filename.endsWith(".json"))
	{
		try {
			ret = parseConfigString!PackageRecipe(contents, filename, mode);
			fixDependenciesNames(ret.name, ret);
		} catch (ConfigException exc) {
			logWarn("Your `dub.json` file use non-conventional features that are deprecated");
			logWarn("Please adjust your `dub.json` file as those warnings will turn into errors in dub v1.40.0");
			logWarn("Error was: %s", exc);
			// Fallback to JSON parser
			ret = PackageRecipe.init;
			parseJson(ret, parseJsonString(contents, filename), parent);
		} catch (Exception exc) {
			logWarn("Your `dub.json` file use non-conventional features that are deprecated");
			logWarn("This is most likely due to duplicated keys.");
			logWarn("Please adjust your `dub.json` file as those warnings will turn into errors in dub v1.40.0");
			logWarn("Error was: %s", exc);
			// Fallback to JSON parser
			ret = PackageRecipe.init;
			parseJson(ret, parseJsonString(contents, filename), parent);
		}
		// `debug = ConfigFillerDebug` also enables verbose parser output
		debug (ConfigFillerDebug)
		{
			import std.stdio;

			PackageRecipe jsonret;
			parseJson(jsonret, parseJsonString(contents, filename), parent_name);
			if (ret != jsonret)
			{
				writeln("Content of JSON and YAML parsing differ for file: ", filename);
				writeln("-------------------------------------------------------------------");
				writeln("JSON (excepted): ", jsonret);
				writeln("-------------------------------------------------------------------");
				writeln("YAML (actual  ): ", ret);
				writeln("========================================");
				ret = jsonret;
			}
		}
	}
	else if (filename.endsWith(".sdl")) parseSDL(ret, contents, parent, filename);
	else assert(false, "readPackageRecipe called with filename with unknown extension: "~filename);

	// Fix for issue #711: `targetType` should be inherited, or default to library
	static void sanitizeTargetType(ref PackageRecipe r) {
		TargetType defaultTT = (r.buildSettings.targetType == TargetType.autodetect) ?
			TargetType.library : r.buildSettings.targetType;
		foreach (ref conf; r.configurations)
			if (conf.buildSettings.targetType == TargetType.autodetect)
				conf.buildSettings.targetType = defaultTT;

		// recurse into sub packages
		foreach (ref subPackage; r.subPackages)
			sanitizeTargetType(subPackage.recipe);
	}

	sanitizeTargetType(ret);

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

unittest { // make sure targetType of sub packages are sanitized too
	import dub.compilers.buildsettings : TargetType;
	auto inputs = [
		"dub.sdl": "name \"test\"\nsubPackage {\nname \"sub\"\ntargetType \"sourceLibrary\"\nconfiguration \"a\" {\n}\n}",
		"dub.json": "{\"name\": \"test\", \"subPackages\": [ { \"name\": \"sub\", \"targetType\": \"sourceLibrary\", \"configurations\": [{\"name\": \"a\"}] } ] }"
	];
	foreach (file, content; inputs) {
		auto pr = parsePackageRecipe(content, file);
		assert(pr.name == "test");
		const spr = pr.subPackages[0].recipe;
		assert(spr.name == "sub");
		assert(spr.configurations.length == 1);
		assert(spr.configurations[0].name == "a");
		assert(spr.configurations[0].buildSettings.targetType == TargetType.sourceLibrary);
	}
}


/** Writes the textual representation of a package recipe to a file.

	Note that the file extension must be either "json" or "sdl".
*/
void writePackageRecipe(string filename, const scope ref PackageRecipe recipe)
{
	writePackageRecipe(NativePath(filename), recipe);
}

/// ditto
void writePackageRecipe(NativePath filename, const scope ref PackageRecipe recipe)
{
	import std.array;
	auto app = appender!string();
	serializePackageRecipe(app, recipe, filename.toNativeString());
	writeFile(filename, app.data);
}

/** Converts a package recipe to its textual representation.

	The extension of the supplied `filename` must be either "json" or "sdl".
	The output format is chosen accordingly.
*/
void serializePackageRecipe(R)(ref R dst, const scope ref PackageRecipe recipe, string filename)
{
	import std.algorithm : endsWith;
	import dub.internal.vibecompat.data.json : writeJsonString;
	import dub.recipe.json : toJson;
	import dub.recipe.sdl : toSDL;

	if (filename.endsWith(".json"))
		dst.writeJsonString!(R, true)(toJson(recipe));
	else if (filename.endsWith(".sdl"))
		toSDL(recipe).toSDLDocument(dst);
	else assert(false, "writePackageRecipe called with filename with unknown extension: "~filename);
}

unittest {
	import std.format;
	import dub.dependency;
	import dub.internal.utils : deepCompare;

	static void success (string source, in PackageRecipe expected, size_t line = __LINE__) {
		const result = parseConfigString!PackageRecipe(source, "dub.json");
		deepCompare(result, expected, __FILE__, line);
	}

	static void error (string source, string expected, size_t line = __LINE__) {
		try
		{
			auto result = parseConfigString!PackageRecipe(source, "dub.json");
			assert(0,
				   format("[%s:%d] Exception should have been thrown but wasn't: %s",
						  __FILE__, line, result));
		}
		catch (Exception exc)
			assert(exc.toString() == expected,
				   format("[%s:%s] result != expected: '%s' != '%s'",
						  __FILE__, line, exc.toString(), expected));
	}

	alias YAMLDep = typeof(BuildSettingsTemplate.dependencies[string.init]);
	const PackageRecipe expected1 =
	{
		name: "foo",
		buildSettings: {
		dependencies: RecipeDependencyAA([
			"repo": YAMLDep(Dependency(Repository(
				"git+https://github.com/dlang/dmd",
				"09d04945bdbc0cba36f7bb1e19d5bd009d4b0ff2",
			))),
			"path": YAMLDep(Dependency(NativePath("/foo/bar/jar/"))),
			"version": YAMLDep(Dependency(VersionRange.fromString("~>1.0"))),
			"version2": YAMLDep(Dependency(Version("4.2.0"))),
		])},
	};
	success(
		`{ "name": "foo", "dependencies": {
	"repo": { "repository": "git+https://github.com/dlang/dmd",
			  "version": "09d04945bdbc0cba36f7bb1e19d5bd009d4b0ff2" },
	"path":    { "path": "/foo/bar/jar/" },
	"version": { "version": "~>1.0" },
	"version2": "4.2.0"
}}`, expected1);


	error(`{ "name": "bar", "dependencies": {"bad": { "repository": "git+https://github.com/dlang/dmd" }}}`,
		"dub.json(0:41): dependencies[bad]: Need to provide a commit hash in 'version' field with 'repository' dependency");
}
