/**
	SDL format support for PackageRecipe

	Copyright: © 2014-2015 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.recipe.sdl;

import dub.compilers.compiler;
import dub.dependency;
import dub.internal.sdlang;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.inet.path;
import dub.recipe.packagerecipe;

import std.algorithm : map;
import std.array : array;
import std.conv;
import std.string : startsWith;


void parseSDL(ref PackageRecipe recipe, string sdl, string parent_name, string filename)
{
	parseSDL(recipe, parseSource(sdl, filename), parent_name);
}

void parseSDL(ref PackageRecipe recipe, Tag sdl, string parent_name)
{
	Tag[] subpacks;
	Tag[] configs;

	// parse top-level fields
	foreach (n; sdl.all.tags) {
		enforceSDL(n.name.length > 0, "Anonymous tags are not allowed at the root level.", n);
		switch (n.fullName) {
			default: break;
			case "name": recipe.name = n.stringTagValue; break;
			case "version": recipe.version_ = n.stringTagValue; break;
			case "description": recipe.description = n.stringTagValue; break;
			case "homepage": recipe.homepage = n.stringTagValue; break;
			case "authors": recipe.authors ~= n.stringArrayTagValue; break;
			case "copyright": recipe.copyright = n.stringTagValue; break;
			case "license": recipe.license = n.stringTagValue; break;
			case "subPackage": subpacks ~= n; break;
			case "configuration": configs ~= n; break;
			case "buildType":
				auto name = n.stringTagValue(true);
				BuildSettingsTemplate bt;
				parseBuildSettings(n, bt, parent_name);
				recipe.buildTypes[name] = bt;
				break;
			case "x:ddoxFilterArgs": recipe.ddoxFilterArgs ~= n.stringArrayTagValue; break;
			case "x:ddoxTool": recipe.ddoxTool = n.stringTagValue; break;
		}
	}

	enforceSDL(recipe.name.length > 0, "The package \"name\" field is missing or empty.", sdl);
	string full_name = parent_name.length ? parent_name ~ ":" ~ recipe.name : recipe.name;

	// parse general build settings
	parseBuildSettings(sdl, recipe.buildSettings, full_name);

	// determine default target type for configurations
	auto defttype = recipe.buildSettings.targetType;
	if (defttype == TargetType.autodetect)
		defttype = TargetType.library;

	// parse configurations
	recipe.configurations.length = configs.length;
	foreach (i, n; configs) {
		recipe.configurations[i].buildSettings.targetType = defttype;
		parseConfiguration(n, recipe.configurations[i], full_name);
	}

	// finally parse all sub packages
	recipe.subPackages.length = subpacks.length;
	foreach (i, n; subpacks) {
		if (n.values.length) {
			recipe.subPackages[i].path = n.stringTagValue;
		} else {
			enforceSDL(n.attributes.length == 0, "No attributes allowed for inline sub package definitions.", n);
			parseSDL(recipe.subPackages[i].recipe, n, full_name);
		}
	}
}

Tag toSDL(in ref PackageRecipe recipe)
{
	Tag ret = new Tag;
	void add(T)(string field, T value) { ret.add(new Tag(null, field, [Value(value)])); }
	add("name", recipe.name);
	if (recipe.version_.length) add("version", recipe.version_);
	if (recipe.description.length) add("description", recipe.description);
	if (recipe.homepage.length) add("homepage", recipe.homepage);
	if (recipe.authors.length) ret.add(new Tag(null, "authors", recipe.authors.map!(a => Value(a)).array));
	if (recipe.copyright.length) add("copyright", recipe.copyright);
	if (recipe.license.length) add("license", recipe.license);
	foreach (name, settings; recipe.buildTypes) {
		auto t = new Tag(null, "buildType", [Value(name)]);
		t.add(settings.toSDL());
		ret.add(t);
	}
	if (recipe.ddoxFilterArgs.length)
		ret.add(new Tag("x", "ddoxFilterArgs", recipe.ddoxFilterArgs.map!(a => Value(a)).array));
	if (recipe.ddoxTool.length) ret.add(new Tag("x", "ddoxTool", [Value(recipe.ddoxTool)]));
	ret.add(recipe.buildSettings.toSDL());
	foreach(config; recipe.configurations)
		ret.add(config.toSDL());
	foreach (i, subPackage; recipe.subPackages) {
		if (subPackage.path !is null) {
			add("subPackage", subPackage.path);
		} else {
			auto t = subPackage.recipe.toSDL();
			t.name = "subPackage";
			ret.add(t);
		}
	}
	return ret;
}

private void parseBuildSettings(Tag settings, ref BuildSettingsTemplate bs, string package_name)
{
	foreach (setting; settings.tags)
		parseBuildSetting(setting, bs, package_name);
}

private void parseBuildSetting(Tag setting, ref BuildSettingsTemplate bs, string package_name)
{
	switch (setting.fullName) {
		default: break;
		case "dependency": parseDependency(setting, bs, package_name); break;
		case "systemDependencies": bs.systemDependencies = setting.stringTagValue; break;
		case "targetType": bs.targetType = setting.stringTagValue.to!TargetType; break;
		case "targetName": bs.targetName = setting.stringTagValue; break;
		case "targetPath": bs.targetPath = setting.stringTagValue; break;
		case "workingDirectory": bs.workingDirectory = setting.stringTagValue; break;
		case "subConfiguration":
			auto args = setting.stringArrayTagValue;
			enforceSDL(args.length == 2, "Expecting package and configuration names as arguments.", setting);
			bs.subConfigurations[expandPackageName(args[0], package_name, setting)] = args[1];
			break;
		case "dflags": setting.parsePlatformStringArray(bs.dflags); break;
		case "lflags": setting.parsePlatformStringArray(bs.lflags); break;
		case "libs": setting.parsePlatformStringArray(bs.libs); break;
		case "sourceFiles": setting.parsePlatformStringArray(bs.sourceFiles); break;
		case "sourcePaths": setting.parsePlatformStringArray(bs.sourcePaths); break;
		case "excludedSourceFiles": setting.parsePlatformStringArray(bs.excludedSourceFiles); break;
		case "mainSourceFile": bs.mainSourceFile = setting.stringTagValue; break;
		case "copyFiles": setting.parsePlatformStringArray(bs.copyFiles); break;
		case "versions": setting.parsePlatformStringArray(bs.versions); break;
		case "debugVersions": setting.parsePlatformStringArray(bs.debugVersions); break;
		case "importPaths": setting.parsePlatformStringArray(bs.importPaths); break;
		case "stringImportPaths": setting.parsePlatformStringArray(bs.stringImportPaths); break;
		case "preGenerateCommands": setting.parsePlatformStringArray(bs.preGenerateCommands); break;
		case "postGenerateCommands": setting.parsePlatformStringArray(bs.postGenerateCommands); break;
		case "preBuildCommands": setting.parsePlatformStringArray(bs.preBuildCommands); break;
		case "postBuildCommands": setting.parsePlatformStringArray(bs.postBuildCommands); break;
		case "buildRequirements": setting.parsePlatformEnumArray!BuildRequirement(bs.buildRequirements); break;
		case "buildOptions": setting.parsePlatformEnumArray!BuildOption(bs.buildOptions); break;
	}
}

private void parseDependency(Tag t, ref BuildSettingsTemplate bs, string package_name)
{
	enforceSDL(t.values.length != 0, "Missing dependency name.", t);
	enforceSDL(t.values.length == 1, "Multiple dependency names.", t);
	auto pkg = expandPackageName(t.values[0].get!string, package_name, t);
	enforceSDL(pkg !in bs.dependencies, "The dependency '"~pkg~"' is specified more than once.", t);

	Dependency dep = Dependency.any;
	auto attrs = t.attributes;

	auto pv = "version" in attrs;

	if ("path" in attrs) {
		if ("version" in attrs)
			logDiagnostic("Ignoring version specification (%s) for path based dependency %s", attrs["version"][0].value.get!string, attrs["path"][0].value.get!string);
		dep.versionSpec = "*";
		dep.path = Path(attrs["path"][0].value.get!string);
	} else {
		enforceSDL("version" in attrs, "Missing version specification.", t);
		dep.versionSpec = attrs["version"][0].value.get!string;
	}

	if ("optional" in attrs)
		dep.optional = attrs["optional"][0].value.get!bool;

	if ("default" in attrs)
		dep.default_ = attrs["default"][0].value.get!bool;

	if ("config" in attrs)
		bs.subConfigurations[pkg] = attrs["config"][0].value.get!string;

	bs.dependencies[pkg] = dep;
}

private void parseConfiguration(Tag t, ref ConfigurationInfo ret, string package_name)
{
	ret.name = t.stringTagValue(true);
	foreach (f; t.tags) {
		switch (f.fullName) {
			default: parseBuildSetting(f, ret.buildSettings, package_name); break;
			case "platforms": ret.platforms ~= f.stringArrayTagValue; break;
		}
	}
}

private Tag toSDL(in ref ConfigurationInfo config)
{
	auto ret = new Tag(null, "configuration", [Value(config.name)]);
	if (config.platforms.length) ret.add(new Tag(null, "platforms", config.platforms[].map!(p => Value(p)).array));
	ret.add(config.buildSettings.toSDL());
	return ret;
}

private Tag[] toSDL(in ref BuildSettingsTemplate bs)
{
	Tag[] ret;
	void add(string name, string value) { ret ~= new Tag(null, name, [Value(value)]); }
	void adda(string name, string suffix, in string[] values) {
		ret ~= new Tag(null, name, values[].map!(v => Value(v)).array,
			suffix.length ? [new Attribute(null, "platform", Value(suffix[1 .. $]))] : null);
	}

	string[] toNameArray(T, U)(U bits) if(is(T == enum)) {
		string[] ret;
		foreach (m; __traits(allMembers, T))
			if (bits & __traits(getMember, T, m))
				ret ~= m;
		return ret;
	}

	foreach (pack, d; bs.dependencies) {
		Attribute[] attribs;
		if (d.path.length) attribs ~= new Attribute(null, "path", Value(d.path.toString()));
		else attribs ~= new Attribute(null, "version", Value(d.versionSpec));
		if (d.optional) attribs ~= new Attribute(null, "optional", Value(true));
		ret ~= new Tag(null, "dependency", [Value(pack)], attribs);
	}
	if (bs.systemDependencies !is null) add("systemDependencies", bs.systemDependencies);
	if (bs.targetType != TargetType.autodetect) add("targetType", bs.targetType.to!string());
	if (bs.targetPath.length) add("targetPath", bs.targetPath);
	if (bs.targetName.length) add("targetName", bs.targetName);
	if (bs.workingDirectory.length) add("workingDirectory", bs.workingDirectory);
	if (bs.mainSourceFile.length) add("mainSourceFile", bs.mainSourceFile);
	foreach (pack, conf; bs.subConfigurations) ret ~= new Tag(null, "subConfiguration", [Value(pack), Value(conf)]);
	foreach (suffix, arr; bs.dflags) adda("dflags", suffix, arr);
	foreach (suffix, arr; bs.lflags) adda("lflags", suffix, arr);
	foreach (suffix, arr; bs.libs) adda("libs", suffix, arr);
	foreach (suffix, arr; bs.sourceFiles) adda("sourceFiles", suffix, arr);
	foreach (suffix, arr; bs.sourcePaths) adda("sourcePaths", suffix, arr);
	foreach (suffix, arr; bs.excludedSourceFiles) adda("excludedSourceFiles", suffix, arr);
	foreach (suffix, arr; bs.copyFiles) adda("copyFiles", suffix, arr);
	foreach (suffix, arr; bs.versions) adda("versions", suffix, arr);
	foreach (suffix, arr; bs.debugVersions) adda("debugVersions", suffix, arr);
	foreach (suffix, arr; bs.importPaths) adda("importPaths", suffix, arr);
	foreach (suffix, arr; bs.stringImportPaths) adda("stringImportPaths", suffix, arr);
	foreach (suffix, arr; bs.preGenerateCommands) adda("preGenerateCommands", suffix, arr);
	foreach (suffix, arr; bs.postGenerateCommands) adda("postGenerateCommands", suffix, arr);
	foreach (suffix, arr; bs.preBuildCommands) adda("preBuildCommands", suffix, arr);
	foreach (suffix, arr; bs.postBuildCommands) adda("postBuildCommands", suffix, arr);
	foreach (suffix, bits; bs.buildRequirements) adda("buildRequirements", suffix, toNameArray!BuildRequirement(bits));
	foreach (suffix, bits; bs.buildOptions) adda("buildOptions", suffix, toNameArray!BuildOption(bits));
	return ret;
}

private string expandPackageName(string name, string parent_name, Tag tag)
{
	import std.algorithm : canFind;
	import std.string : format;
	if (name.startsWith(":")) {
		enforceSDL(!parent_name.canFind(':'), format("Short-hand packages syntax not allowed within sub packages: %s -> %s", parent_name, name), tag);
		return parent_name ~ name;
	} else return name;
}

private string stringTagValue(Tag t, bool allow_child_tags = false)
{
	import std.string : format;
	enforceSDL(t.values.length > 0, format("Missing string value for '%s'.", t.fullName), t);
	enforceSDL(t.values.length == 1, format("Expected only one value for '%s'.", t.fullName), t);
	enforceSDL(t.values[0].peek!string !is null, format("Expected value of type string for '%s'.", t.fullName), t);
	enforceSDL(allow_child_tags || t.tags.length == 0, format("No child tags allowed for '%s'.", t.fullName), t);
	// Q: should attributes be disallowed, or just ignored for forward compatibility reasons?
	//enforceSDL(t.attributes.length == 0, format("No attributes allowed for '%s'.", t.fullName), t);
	return t.values[0].get!string;
}

private string[] stringArrayTagValue(Tag t, bool allow_child_tags = false)
{
	import std.string : format;
	enforceSDL(allow_child_tags || t.tags.length == 0, format("No child tags allowed for '%s'.", t.fullName), t);
	// Q: should attributes be disallowed, or just ignored for forward compatibility reasons?
	//enforceSDL(t.attributes.length == 0, format("No attributes allowed for '%s'.", t.fullName), t);

	string[] ret;
	foreach (v; t.values) {
		enforceSDL(t.values[0].peek!string !is null, format("Values for '%s' must be strings.", t.fullName), t);
		ret ~= v.get!string;
	}
	return ret;
}

private void parsePlatformStringArray(Tag t, ref string[][string] dst)
{
	string platform;
	if ("platform" in t.attributes)
		platform = "-" ~ t.attributes["platform"][0].value.get!string;
	dst[platform] ~= t.values.map!(v => v.get!string).array;
}

private void parsePlatformEnumArray(E, Es)(Tag t, ref Es[string] dst)
{
	string platform;
	if ("platform" in t.attributes)
		platform = "-" ~ t.attributes["platform"][0].value.get!string;
	foreach (v; t.values) {
		if (platform !in dst) dst[platform] = Es.init;
		dst[platform] |= v.get!string.to!E;
	}
}

private void enforceSDL(bool condition, lazy string message, Tag tag, string file = __FILE__, int line = __LINE__)
{
	import std.string : format;
	if (!condition) {
		throw new Exception(format("%s(%s): Error: %s", tag.location.file, tag.location.line, message), file, line);
	}
}


unittest { // test all possible fields
	auto sdl =
`name "projectname";
description "project description";
homepage "http://example.com"
authors "author 1" "author 2"
authors "author 3"
copyright "copyright string"
license "license string"
version "1.0.0"
subPackage {
	name "subpackage1"
}
subPackage {
	name "subpackage2"
	dependency "projectname:subpackage1" version="*"
}
subPackage "pathsp3"
configuration "config1" {
	platforms "windows" "linux"
	targetType "library"
}
configuration "config2" {
	platforms "windows-x86"
	targetType "executable"
}
buildType "debug" {
	dflags "-g" "-debug"
}
buildType "release" {
	dflags "-release" "-O"
}
x:ddoxFilterArgs "-arg1" "-arg2"
x:ddoxFilterArgs "-arg3"
x:ddoxTool "ddoxtool"

dependency ":subpackage1" optional=false path="."
dependency "somedep" version="1.0.0" optional=true
systemDependencies "system dependencies"
targetType "executable"
targetName "target name"
targetPath "target path"
workingDirectory "working directory"
subConfiguration ":subpackage2" "library"
buildRequirements "allowWarnings" "silenceDeprecations"
buildOptions "verbose" "ignoreUnknownPragmas"
libs "lib1" "lib2"
libs "lib3"
sourceFiles "source1" "source2"
sourceFiles "source3"
sourcePaths "sourcepath1" "sourcepath2"
sourcePaths "sourcepath3"
excludedSourceFiles "excluded1" "excluded2"
excludedSourceFiles "excluded3"
mainSourceFile "main source"
copyFiles "copy1" "copy2"
copyFiles "copy3"
versions "version1" "version2"
versions "version3"
debugVersions "debug1" "debug2"
debugVersions "debug3"
importPaths "import1" "import2"
importPaths "import3"
stringImportPaths "string1" "string2"
stringImportPaths "string3"
preGenerateCommands "preg1" "preg2"
preGenerateCommands "preg3"
postGenerateCommands "postg1" "postg2"
postGenerateCommands "postg3"
preBuildCommands "preb1" "preb2"
preBuildCommands "preb3"
postBuildCommands "postb1" "postb2"
postBuildCommands "postb3"
dflags "df1" "df2"
dflags "df3"
lflags "lf1" "lf2"
lflags "lf3"
`;
	PackageRecipe rec1;
	parseSDL(rec1, sdl, null, "testfile");
	PackageRecipe rec;
	parseSDL(rec, rec1.toSDL(), null); // verify that all fields are serialized properly

	assert(rec.name == "projectname");
	assert(rec.description == "project description");
	assert(rec.homepage == "http://example.com");
	assert(rec.authors == ["author 1", "author 2", "author 3"]);
	assert(rec.copyright == "copyright string");
	assert(rec.license == "license string");
	assert(rec.version_ == "1.0.0");
	assert(rec.subPackages.length == 3);
	assert(rec.subPackages[0].path == "");
	assert(rec.subPackages[0].recipe.name == "subpackage1");
	assert(rec.subPackages[1].path == "");
	assert(rec.subPackages[1].recipe.name == "subpackage2");
	assert(rec.subPackages[1].recipe.buildSettings.dependencies.length == 1);
	assert("projectname:subpackage1" in rec.subPackages[1].recipe.buildSettings.dependencies);
	assert(rec.subPackages[2].path == "pathsp3");
	assert(rec.configurations.length == 2);
	assert(rec.configurations[0].name == "config1");
	assert(rec.configurations[0].platforms == ["windows", "linux"]);
	assert(rec.configurations[0].buildSettings.targetType == TargetType.library);
	assert(rec.configurations[1].name == "config2");
	assert(rec.configurations[1].platforms == ["windows-x86"]);
	assert(rec.configurations[1].buildSettings.targetType == TargetType.executable);
	assert(rec.buildTypes.length == 2);
	assert(rec.buildTypes["debug"].dflags == ["": ["-g", "-debug"]]);
	assert(rec.buildTypes["release"].dflags == ["": ["-release", "-O"]]);
	assert(rec.ddoxFilterArgs == ["-arg1", "-arg2", "-arg3"], rec.ddoxFilterArgs.to!string);
	assert(rec.ddoxTool == "ddoxtool");
	assert(rec.buildSettings.dependencies.length == 2);
	assert(rec.buildSettings.dependencies["projectname:subpackage1"].optional == false);
	assert(rec.buildSettings.dependencies["projectname:subpackage1"].path == Path("."));
	assert(rec.buildSettings.dependencies["somedep"].versionSpec == "1.0.0");
	assert(rec.buildSettings.dependencies["somedep"].optional == true);
	assert(rec.buildSettings.dependencies["somedep"].path.empty);
	assert(rec.buildSettings.systemDependencies == "system dependencies");
	assert(rec.buildSettings.targetType == TargetType.executable);
	assert(rec.buildSettings.targetName == "target name");
	assert(rec.buildSettings.targetPath == "target path");
	assert(rec.buildSettings.workingDirectory == "working directory");
	assert(rec.buildSettings.subConfigurations.length == 1);
	assert(rec.buildSettings.subConfigurations["projectname:subpackage2"] == "library");
	assert(rec.buildSettings.buildRequirements == ["": cast(BuildRequirements)(BuildRequirement.allowWarnings | BuildRequirement.silenceDeprecations)]);
	assert(rec.buildSettings.buildOptions == ["": cast(BuildOptions)(BuildOption.verbose | BuildOption.ignoreUnknownPragmas)]);
	assert(rec.buildSettings.libs == ["": ["lib1", "lib2", "lib3"]]);
	assert(rec.buildSettings.sourceFiles == ["": ["source1", "source2", "source3"]]);
	assert(rec.buildSettings.sourcePaths == ["": ["sourcepath1", "sourcepath2", "sourcepath3"]]);
	assert(rec.buildSettings.excludedSourceFiles == ["": ["excluded1", "excluded2", "excluded3"]]);
	assert(rec.buildSettings.mainSourceFile == "main source");
	assert(rec.buildSettings.copyFiles == ["": ["copy1", "copy2", "copy3"]]);
	assert(rec.buildSettings.versions == ["": ["version1", "version2", "version3"]]);
	assert(rec.buildSettings.debugVersions == ["": ["debug1", "debug2", "debug3"]]);
	assert(rec.buildSettings.importPaths == ["": ["import1", "import2", "import3"]]);
	assert(rec.buildSettings.stringImportPaths == ["": ["string1", "string2", "string3"]]);
	assert(rec.buildSettings.preGenerateCommands == ["": ["preg1", "preg2", "preg3"]]);
	assert(rec.buildSettings.postGenerateCommands == ["": ["postg1", "postg2", "postg3"]]);
	assert(rec.buildSettings.preBuildCommands == ["": ["preb1", "preb2", "preb3"]]);
	assert(rec.buildSettings.postBuildCommands == ["": ["postb1", "postb2", "postb3"]]);
	assert(rec.buildSettings.dflags == ["": ["df1", "df2", "df3"]]);
	assert(rec.buildSettings.lflags == ["": ["lf1", "lf2", "lf3"]]);
}

unittest { // test platform identifiers
	auto sdl =
`name "testproject"
dflags "-a" "-b" platform="windows-x86"
dflags "-c" platform="windows-x86"
dflags "-e" "-f"
dflags "-g"
dflags "-h" "-i" platform="linux"
dflags "-j" platform="linux"
`;
	PackageRecipe rec;
	parseSDL(rec, sdl, null, "testfile");
	assert(rec.buildSettings.dflags.length == 3);
	assert(rec.buildSettings.dflags["-windows-x86"] == ["-a", "-b", "-c"]);
	assert(rec.buildSettings.dflags[""] == ["-e", "-f", "-g"]);
	assert(rec.buildSettings.dflags["-linux"] == ["-h", "-i", "-j"]);
}

unittest { // test for missing name field
	import std.exception;
	auto sdl = `description "missing name"`;
	PackageRecipe rec;
	assertThrown(parseSDL(rec, sdl, null, "testfile"));
}

unittest { // test single value fields
	import std.exception;
	PackageRecipe rec;
	assertThrown!Exception(parseSDL(rec, `name "hello" "world"`, null, "testfile"));
	assertThrown!Exception(parseSDL(rec, `name`, null, "testfile"));
	assertThrown!Exception(parseSDL(rec, `name 10`, null, "testfile"));
	assertThrown!Exception(parseSDL(rec,
		`name "hello" {
			world
		}`, null, "testfile"));
	assertThrown!Exception(parseSDL(rec,
		`name ""
		versions "hello" 10`
		, null, "testfile"));
}

unittest { // test basic serialization
	PackageRecipe p;
	p.name = "test";
	p.authors = ["foo", "bar"];
	p.buildSettings.dflags["-windows"] = ["-a"];
	p.buildSettings.lflags[""] = ["-b", "-c"];
	auto sdl = toSDL(p).toSDLDocument();
	assert(sdl ==
`name "test"
authors "foo" "bar"
dflags "-a" platform="windows"
lflags "-b" "-c"
`);
}

unittest {
	auto sdl = "name \"test\"\nsourcePaths";
	PackageRecipe rec;
	parseSDL(rec, sdl, null, "testfile");
	assert("" in rec.buildSettings.sourcePaths);
}
