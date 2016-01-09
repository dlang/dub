/**
	JSON format support for PackageRecipe

	Copyright: © 2012-2014 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Matthias Dondorff
*/
module dub.recipe.json;

import dub.compilers.compiler;
import dub.dependency;
import dub.recipe.packagerecipe;

import dub.internal.vibecompat.data.json;

import std.algorithm : canFind, startsWith;
import std.conv : to;
import std.exception : enforce;
import std.range;
import std.string : format, indexOf;
import std.traits : EnumMembers;


void parseJson(ref PackageRecipe recipe, Json json, string parent_name)
{
	foreach (string field, value; json) {
		switch (field) {
			default: break;
			case "name": recipe.name = value.get!string; break;
			case "version": recipe.version_ = value.get!string; break;
			case "description": recipe.description = value.get!string; break;
			case "homepage": recipe.homepage = value.get!string; break;
			case "authors": recipe.authors = deserializeJson!(string[])(value); break;
			case "copyright": recipe.copyright = value.get!string; break;
			case "license": recipe.license = value.get!string; break;
			case "configurations": break; // handled below, after the global settings have been parsed
			case "buildTypes":
				foreach (string name, settings; value) {
					BuildSettingsTemplate bs;
					bs.parseJson(settings, null);
					recipe.buildTypes[name] = bs;
				}
				break;
			case "-ddoxFilterArgs": recipe.ddoxFilterArgs = deserializeJson!(string[])(value); break;
			case "-ddoxTool": recipe.ddoxTool = value.get!string; break;
		}
	}

	enforce(recipe.name.length > 0, "The package \"name\" field is missing or empty.");

	auto fullname = parent_name.length ? parent_name ~ ":" ~ recipe.name : recipe.name;

	// parse build settings
	recipe.buildSettings.parseJson(json, fullname);

	if (auto pv = "configurations" in json) {
		TargetType deftargettp = TargetType.library;
		if (recipe.buildSettings.targetType != TargetType.autodetect)
			deftargettp = recipe.buildSettings.targetType;

		foreach (settings; *pv) {
			ConfigurationInfo ci;
			ci.parseJson(settings, recipe.name, deftargettp);
			recipe.configurations ~= ci;
		}
	}

	// parse any sub packages after the main package has been fully parsed
	if (auto ps = "subPackages" in json)
		recipe.parseSubPackages(fullname, ps.opt!(Json[]));
}

Json toJson(in ref PackageRecipe recipe)
{
	auto ret = recipe.buildSettings.toJson();
	ret.name = recipe.name;
	if (!recipe.version_.empty) ret["version"] = recipe.version_;
	if (!recipe.description.empty) ret.description = recipe.description;
	if (!recipe.homepage.empty) ret.homepage = recipe.homepage;
	if (!recipe.authors.empty) ret.authors = serializeToJson(recipe.authors);
	if (!recipe.copyright.empty) ret.copyright = recipe.copyright;
	if (!recipe.license.empty) ret.license = recipe.license;
	if (!recipe.subPackages.empty) {
		Json[] jsonSubPackages = new Json[recipe.subPackages.length];
		foreach (i, subPackage; recipe.subPackages) {
			if (subPackage.path !is null) {
				jsonSubPackages[i] = Json(subPackage.path);
			} else {
				jsonSubPackages[i] = subPackage.recipe.toJson();
			}
		}
		ret.subPackages = jsonSubPackages;
	}
	if (recipe.configurations.length) {
		Json[] configs;
		foreach(config; recipe.configurations)
			configs ~= config.toJson();
		ret.configurations = configs;
	}
	if (recipe.buildTypes.length) {
		Json[string] types;
		foreach (name, settings; recipe.buildTypes)
			types[name] = settings.toJson();
		ret.buildTypes = types;
	}
	if (!recipe.ddoxFilterArgs.empty) ret["-ddoxFilterArgs"] = recipe.ddoxFilterArgs.serializeToJson();
	return ret;
}

private void parseSubPackages(ref PackageRecipe recipe, string parent_package_name, Json[] subPackagesJson)
{
	enforce(!parent_package_name.canFind(":"), format("'subPackages' found in '%s'. This is only supported in the main package file for '%s'.",
		parent_package_name, getBasePackageName(parent_package_name)));

	recipe.subPackages = new SubPackage[subPackagesJson.length];
	foreach (i, subPackageJson; subPackagesJson) {
		// Handle referenced Packages
		if(subPackageJson.type == Json.Type.string) {
			string subpath = subPackageJson.get!string;
			recipe.subPackages[i] = SubPackage(subpath, PackageRecipe.init);
		} else {
			PackageRecipe subinfo;
			subinfo.parseJson(subPackageJson, parent_package_name);
			recipe.subPackages[i] = SubPackage(null, subinfo);
		}
	}
}

private void parseJson(ref ConfigurationInfo config, Json json, string package_name, TargetType default_target_type = TargetType.library)
{
	config.buildSettings.targetType = default_target_type;

	foreach (string name, value; json) {
		switch (name) {
			default: break;
			case "name":
				config.name = value.get!string;
				enforce(!config.name.empty, "Configurations must have a non-empty name.");
				break;
			case "platforms": config.platforms = deserializeJson!(string[])(value); break;
		}
	}

	enforce(!config.name.empty, "Configuration is missing a name.");

	BuildSettingsTemplate bs;
	config.buildSettings.parseJson(json, package_name);
}

private Json toJson(in ref ConfigurationInfo config)
{
	auto ret = config.buildSettings.toJson();
	ret.name = config.name;
	if (config.platforms.length) ret.platforms = serializeToJson(config.platforms);
	return ret;
}

private void parseJson(ref BuildSettingsTemplate bs, Json json, string package_name)
{
	foreach(string name, value; json)
	{
		auto idx = indexOf(name, "-");
		string basename, suffix;
		if( idx >= 0 ) { basename = name[0 .. idx]; suffix = name[idx .. $]; }
		else basename = name;
		switch(basename){
			default: break;
			case "dependencies":
				foreach (string pkg, verspec; value) {
					if (pkg.startsWith(":")) {
						enforce(!package_name.canFind(':'), format("Short-hand packages syntax not allowed within sub packages: %s -> %s", package_name, pkg));
						pkg = package_name ~ pkg;
					}
					enforce(pkg !in bs.dependencies, "The dependency '"~pkg~"' is specified more than once." );
					bs.dependencies[pkg] = deserializeJson!Dependency(verspec);
				}
				break;
			case "systemDependencies":
				bs.systemDependencies = value.get!string;
				break;
			case "targetType":
				enforce(suffix.empty, "targetType does not support platform customization.");
				bs.targetType = value.get!string.to!TargetType;
				break;
			case "targetPath":
				enforce(suffix.empty, "targetPath does not support platform customization.");
				bs.targetPath = value.get!string;
				break;
			case "targetName":
				enforce(suffix.empty, "targetName does not support platform customization.");
				bs.targetName = value.get!string;
				break;
			case "workingDirectory":
				enforce(suffix.empty, "workingDirectory does not support platform customization.");
				bs.workingDirectory = value.get!string;
				break;
			case "mainSourceFile":
				enforce(suffix.empty, "mainSourceFile does not support platform customization.");
				bs.mainSourceFile = value.get!string;
				break;
			case "subConfigurations":
				enforce(suffix.empty, "subConfigurations does not support platform customization.");
				bs.subConfigurations = deserializeJson!(string[string])(value);
				break;
			case "dflags": bs.dflags[suffix] = deserializeJson!(string[])(value); break;
			case "lflags": bs.lflags[suffix] = deserializeJson!(string[])(value); break;
			case "libs": bs.libs[suffix] = deserializeJson!(string[])(value); break;
			case "files":
			case "sourceFiles": bs.sourceFiles[suffix] = deserializeJson!(string[])(value); break;
			case "sourcePaths": bs.sourcePaths[suffix] = deserializeJson!(string[])(value); break;
			case "sourcePath": bs.sourcePaths[suffix] ~= [value.get!string]; break; // deprecated
			case "excludedSourceFiles": bs.excludedSourceFiles[suffix] = deserializeJson!(string[])(value); break;
			case "copyFiles": bs.copyFiles[suffix] = deserializeJson!(string[])(value); break;
			case "versions": bs.versions[suffix] = deserializeJson!(string[])(value); break;
			case "debugVersions": bs.debugVersions[suffix] = deserializeJson!(string[])(value); break;
			case "importPaths": bs.importPaths[suffix] = deserializeJson!(string[])(value); break;
			case "stringImportPaths": bs.stringImportPaths[suffix] = deserializeJson!(string[])(value); break;
			case "preGenerateCommands": bs.preGenerateCommands[suffix] = deserializeJson!(string[])(value); break;
			case "postGenerateCommands": bs.postGenerateCommands[suffix] = deserializeJson!(string[])(value); break;
			case "preBuildCommands": bs.preBuildCommands[suffix] = deserializeJson!(string[])(value); break;
			case "postBuildCommands": bs.postBuildCommands[suffix] = deserializeJson!(string[])(value); break;
			case "buildRequirements":
				BuildRequirements reqs;
				foreach (req; deserializeJson!(string[])(value))
					reqs |= to!BuildRequirement(req);
				bs.buildRequirements[suffix] = reqs;
				break;
			case "buildOptions":
				BuildOptions options;
				foreach (opt; deserializeJson!(string[])(value))
					options |= to!BuildOption(opt);
				bs.buildOptions[suffix] = options;
				break;
		}
	}
}

Json toJson(in ref BuildSettingsTemplate bs)
{
	auto ret = Json.emptyObject;
	if( bs.dependencies !is null ){
		auto deps = Json.emptyObject;
		foreach( pack, d; bs.dependencies )
			deps[pack] = serializeToJson(d);
		ret.dependencies = deps;
	}
	if (bs.systemDependencies !is null) ret.systemDependencies = bs.systemDependencies;
	if (bs.targetType != TargetType.autodetect) ret["targetType"] = bs.targetType.to!string();
	if (!bs.targetPath.empty) ret["targetPath"] = bs.targetPath;
	if (!bs.targetName.empty) ret["targetName"] = bs.targetName;
	if (!bs.workingDirectory.empty) ret["workingDirectory"] = bs.workingDirectory;
	if (!bs.mainSourceFile.empty) ret["mainSourceFile"] = bs.mainSourceFile;
	if (bs.subConfigurations.length > 0) ret["subConfigurations"] = serializeToJson(bs.subConfigurations);
	foreach (suffix, arr; bs.dflags) ret["dflags"~suffix] = serializeToJson(arr);
	foreach (suffix, arr; bs.lflags) ret["lflags"~suffix] = serializeToJson(arr);
	foreach (suffix, arr; bs.libs) ret["libs"~suffix] = serializeToJson(arr);
	foreach (suffix, arr; bs.sourceFiles) ret["sourceFiles"~suffix] = serializeToJson(arr);
	foreach (suffix, arr; bs.sourcePaths) ret["sourcePaths"~suffix] = serializeToJson(arr);
	foreach (suffix, arr; bs.excludedSourceFiles) ret["excludedSourceFiles"~suffix] = serializeToJson(arr);
	foreach (suffix, arr; bs.copyFiles) ret["copyFiles"~suffix] = serializeToJson(arr);
	foreach (suffix, arr; bs.versions) ret["versions"~suffix] = serializeToJson(arr);
	foreach (suffix, arr; bs.debugVersions) ret["debugVersions"~suffix] = serializeToJson(arr);
	foreach (suffix, arr; bs.importPaths) ret["importPaths"~suffix] = serializeToJson(arr);
	foreach (suffix, arr; bs.stringImportPaths) ret["stringImportPaths"~suffix] = serializeToJson(arr);
	foreach (suffix, arr; bs.preGenerateCommands) ret["preGenerateCommands"~suffix] = serializeToJson(arr);
	foreach (suffix, arr; bs.postGenerateCommands) ret["postGenerateCommands"~suffix] = serializeToJson(arr);
	foreach (suffix, arr; bs.preBuildCommands) ret["preBuildCommands"~suffix] = serializeToJson(arr);
	foreach (suffix, arr; bs.postBuildCommands) ret["postBuildCommands"~suffix] = serializeToJson(arr);
	foreach (suffix, arr; bs.buildRequirements) {
		string[] val;
		foreach (i; [EnumMembers!BuildRequirement])
			if (arr & i) val ~= to!string(i);
		ret["buildRequirements"~suffix] = serializeToJson(val);
	}
	foreach (suffix, arr; bs.buildOptions) {
		string[] val;
		foreach (i; [EnumMembers!BuildOption])
			if (arr & i) val ~= to!string(i);
		ret["buildOptions"~suffix] = serializeToJson(val);
	}
	return ret;
}
