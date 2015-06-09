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
	foreach (n; sdl.tags) {
		enforceSDL(n.name.length > 0, "Anonymous tags are not allowed at the root level.", n);
		switch (n.fullName) {
			default: break;
			case "name": recipe.name = n.stringTagValue; break;
			case "description": recipe.description = n.stringTagValue; break;
			case "homepage": recipe.homepage = n.stringTagValue; break;
			case "authors": recipe.authors = n.stringArrayTagValue; break;
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
			case "x:ddoxFilterArgs": recipe.ddoxFilterArgs = n.stringArrayTagValue; break;
		}
	}

	enforce(recipe.name.length > 0, "The package \"name\" field is missing or empty.");
	string full_name = parent_name.length ? parent_name ~ ":" ~ recipe.name : recipe.name;

	// parse general build settings
	parseBuildSettings(sdl, recipe.buildSettings, full_name);

	// parse configurations
	recipe.configurations.length = configs.length;
	foreach (i, n; configs)
		parseConfiguration(n, recipe.configurations[i], full_name);

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

private void parseBuildSettings(Tag settings, ref BuildSettingsTemplate bs, string package_name)
{
	foreach (setting; settings.tags) {
		parseBuildSetting(setting, bs, package_name);
	}
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
			bs.subConfigurations[args[0]] = args[1];
			break;
		case "dflags": setting.parsePlatformStringArray(bs.dflags); break;
		case "lflags": setting.parsePlatformStringArray(bs.lflags); break;
		case "libs": setting.parsePlatformStringArray(bs.libs); break;
		case "sourceFiles": setting.parsePlatformStringArray(bs.sourceFiles); break;
		case "sourcePaths": setting.parsePlatformStringArray(bs.sourcePaths); break;
		case "excludedSourceFiles": setting.parsePlatformStringArray(bs.excludedSourceFiles); break;
		case "copyFiles": setting.parsePlatformStringArray(bs.copyFiles); break;
		case "versions": setting.parsePlatformStringArray(bs.versions); break;
		case "importPaths": setting.parsePlatformStringArray(bs.importPaths); break;
		case "stringImportPaths": setting.parsePlatformStringArray(bs.stringImportPaths); break;
		case "preGenerateCommands": setting.parsePlatformStringArray(bs.preGenerateCommands); break;
		case "postGenerateCommands": setting.parsePlatformStringArray(bs.postGenerateCommands); break;
		case "preBuildCommands": setting.parsePlatformStringArray(bs.preBuildCommands); break;
		case "postBuildCommands": setting.parsePlatformStringArray(bs.postBuildCommands); break;
		case "buildRequirements": setting.parsePlatformEnumArray!BuildRequirements(bs.buildRequirements); break;
		case "buildOptions": setting.parsePlatformEnumArray!BuildOptions(bs.buildOptions); break;
	}
}

private void parseDependency(Tag t, ref BuildSettingsTemplate bs, string package_name)
{
	import std.algorithm : canFind;
	import std.string : format;

	auto pkg = t.values[0].get!string;
	if (pkg.startsWith(":")) {
		enforce(!package_name.canFind(':'), format("Short-hand packages syntax not allowed within sub packages: %s -> %s", package_name, pkg));
		pkg = package_name ~ pkg;
	}
	enforce(pkg !in bs.dependencies, "The dependency '"~pkg~"' is specified more than once." );

	Dependency dep = Dependency.ANY;
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

	bs.dependencies[pkg] = dep;
}

private void parseConfiguration(Tag t, ref ConfigurationInfo ret, string package_name)
{
	ret.name = t.stringTagValue(true);
	foreach (f; t.tags) {
		switch (f.fullName) {
			default: parseBuildSetting(f, ret.buildSettings, package_name); break;
			case "platforms": ret.platforms = f.stringArrayTagValue; break;
		}
	}
}

private string stringTagValue(Tag t, bool allow_child_tags = false)
{
	// TODO: check for additional values or attributes
	return t.values[0].get!string;
}

private string[] stringArrayTagValue(Tag t, bool allow_child_tags = false)
{
	string[] ret;
	// TODO: check for additional attributes
	foreach (v; t.values)
		ret ~= v.get!string;
	return ret;
}

private void parsePlatformStringArray(Tag t, ref string[][string] dst)
{
	string platform;
	if ("platform" in t.attributes)
		platform = t.attributes["platform"][0].value.get!string;
	foreach (v; t.values)
		dst[platform] ~= v.get!string;
}

private void parsePlatformEnumArray(E, Es)(Tag t, ref Es[string] dst)
{
	string platform;
	if ("platform" in t.attributes)
		platform = t.attributes["platform"][0].value.get!string;
	foreach (v; t.values)
		dst[platform] |= v.get!string.to!E;
}

private void enforceSDL(bool condition, lazy string message, Tag tag, string file = __FILE__, int line = __LINE__)
{
	import std.string : format;
	if (!condition) {
		throw new Exception(format("%s(%s): Error: %s", tag.location.file, tag.location.line, message), file, line);
	}
}
