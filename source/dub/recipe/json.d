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


void parseJson(ref PackageRecipe recipe, Json json, PackageName parent_package_name)
{
	foreach (string field, value; json) {
		switch (field) {
			default: break;
			case "name": recipe.name = PackageName(value.get!string); break;
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
					bs.parseJson(settings, PackageName.init);
					recipe.buildTypes[name] = bs;
				}
				break;
			case "toolchainRequirements":
				recipe.toolchainRequirements.parseJson(value);
				break;
			case "-ddoxFilterArgs": recipe.ddoxFilterArgs = deserializeJson!(string[])(value); break;
			case "-ddoxTool": recipe.ddoxTool = value.get!string; break;
		}
	}

	enforce(recipe.name.length > 0, "The package \"name\" field is missing or empty.");

	auto fullname = parent_package_name.length ? PackageName(parent_package_name[] ~ ":" ~ recipe.name[]) : recipe.name;

	// parse build settings
	recipe.buildSettings.parseJson(json, fullname);

	if (auto pv = "configurations" in json) {
		foreach (settings; *pv) {
			ConfigurationInfo ci;
			ci.parseJson(settings, recipe.name);
			recipe.configurations ~= ci;
		}
	}

	// parse any sub packages after the main package has been fully parsed
	if (auto ps = "subPackages" in json)
		recipe.parseSubPackages(fullname, ps.opt!(Json[]));
}

Json toJson(const scope ref PackageRecipe recipe)
{
	auto ret = recipe.buildSettings.toJson();
	ret["name"] = recipe.name[];
	if (!recipe.version_.empty) ret["version"] = recipe.version_;
	if (!recipe.description.empty) ret["description"] = recipe.description;
	if (!recipe.homepage.empty) ret["homepage"] = recipe.homepage;
	if (!recipe.authors.empty) ret["authors"] = serializeToJson(recipe.authors);
	if (!recipe.copyright.empty) ret["copyright"] = recipe.copyright;
	if (!recipe.license.empty) ret["license"] = recipe.license;
	if (!recipe.subPackages.empty) {
		Json[] jsonSubPackages = new Json[recipe.subPackages.length];
		foreach (i, subPackage; recipe.subPackages) {
			if (subPackage.path !is null) {
				jsonSubPackages[i] = Json(subPackage.path);
			} else {
				jsonSubPackages[i] = subPackage.recipe.toJson();
			}
		}
		ret["subPackages"] = jsonSubPackages;
	}
	if (recipe.configurations.length) {
		Json[] configs;
		foreach(config; recipe.configurations)
			configs ~= config.toJson();
		ret["configurations"] = configs;
	}
	if (recipe.buildTypes.length) {
		Json[string] types;
		foreach (name, settings; recipe.buildTypes)
			types[name] = settings.toJson();
		ret["buildTypes"] = types;
	}
	if (!recipe.toolchainRequirements.empty) {
		ret["toolchainRequirements"] = recipe.toolchainRequirements.toJson();
	}
	if (!recipe.ddoxFilterArgs.empty) ret["-ddoxFilterArgs"] = recipe.ddoxFilterArgs.serializeToJson();
	if (!recipe.ddoxTool.empty) ret["-ddoxTool"] = recipe.ddoxTool;
	return ret;
}

private void parseSubPackages(ref PackageRecipe recipe, PackageName parent_package_name, Json[] subPackagesJson)
{
	enforce(!parent_package_name[].canFind(":"), format("'subPackages' found in '%s'. This is only supported in the main package file for '%s'.",
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

private void parseJson(ref ConfigurationInfo config, Json json, PackageName package_name)
{
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
	config.buildSettings.parseJson(json, package_name);
}

private Json toJson(const scope ref ConfigurationInfo config)
{
	auto ret = config.buildSettings.toJson();
	ret["name"] = config.name;
	if (config.platforms.length) ret["platforms"] = serializeToJson(config.platforms);
	return ret;
}

private void parseJson(ref BuildSettingsTemplate bs, Json json, PackageName package_name)
{
	foreach(string name, value; json)
	{
		auto idx = indexOf(name, "-");
		string basename, suffix;
		if( idx >= 0 ) { basename = name[0 .. idx]; suffix = name[idx + 1 .. $]; }
		else basename = name;
		switch(basename){
			default: break;
			case "dependencies":
				foreach (string pkgString, verspec; value) {
                    auto pkg = PackageName(pkgString);
					if (pkg[].startsWith(":")) {
						enforce(!package_name[].canFind(':'), format("Short-hand packages syntax not allowed within sub packages: %s -> %s", package_name, pkg));
						pkg = PackageName(package_name[] ~ pkg[]);
					}
					enforce(pkg !in bs.dependencies, "The dependency '"~pkg[]~"' is specified more than once." );
					bs.dependencies[pkg] = Dependency.fromJson(verspec);
					if (verspec.type == Json.Type.object)
					{
						BuildSettingsTemplate dbs;
						dbs.parseJson(verspec, package_name);
						// Only create an entry if there's an actual BuildSetting
						// defined by the user.
						if (dbs !is BuildSettingsTemplate.init)
							bs.dependencyBuildSettings[pkg] = dbs;
					}
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
				bs.subConfigurations = deserializeJson!(string[PackageName])(value);
				break;
			case "dflags": bs.dflags[suffix] = deserializeJson!(string[])(value); break;
			case "lflags": bs.lflags[suffix] = deserializeJson!(string[])(value); break;
			case "libs": bs.libs[suffix] = deserializeJson!(string[])(value); break;
			case "files":
			case "sourceFiles": bs.sourceFiles[suffix] = deserializeJson!(string[])(value); break;
			case "sourcePaths": bs.sourcePaths[suffix] = deserializeJson!(string[])(value); break;
			case "sourcePath": bs.sourcePaths[suffix] ~= [value.get!string]; break; // deprecated
			case "excludedSourceFiles": bs.excludedSourceFiles[suffix] = deserializeJson!(string[])(value); break;
			case "injectSourceFiles": bs.injectSourceFiles[suffix] = deserializeJson!(string[])(value); break;
			case "copyFiles": bs.copyFiles[suffix] = deserializeJson!(string[])(value); break;
			case "extraDependencyFiles": bs.extraDependencyFiles[suffix] = deserializeJson!(string[])(value); break;
			case "versions": bs.versions[suffix] = deserializeJson!(string[])(value); break;
			case "debugVersions": bs.debugVersions[suffix] = deserializeJson!(string[])(value); break;
			case "-versionFilters": bs.versionFilters[suffix] = deserializeJson!(string[])(value); break;
			case "-debugVersionFilters": bs.debugVersionFilters[suffix] = deserializeJson!(string[])(value); break;
			case "importPaths": bs.importPaths[suffix] = deserializeJson!(string[])(value); break;
			case "stringImportPaths": bs.stringImportPaths[suffix] = deserializeJson!(string[])(value); break;
			case "preGenerateCommands": bs.preGenerateCommands[suffix] = deserializeJson!(string[])(value); break;
			case "postGenerateCommands": bs.postGenerateCommands[suffix] = deserializeJson!(string[])(value); break;
			case "preBuildCommands": bs.preBuildCommands[suffix] = deserializeJson!(string[])(value); break;
			case "postBuildCommands": bs.postBuildCommands[suffix] = deserializeJson!(string[])(value); break;
			case "preRunCommands": bs.preRunCommands[suffix] = deserializeJson!(string[])(value); break;
			case "postRunCommands": bs.postRunCommands[suffix] = deserializeJson!(string[])(value); break;
			case "environments": bs.environments[suffix] = deserializeJson!(string[string])(value); break;
			case "buildEnvironments": bs.buildEnvironments[suffix] = deserializeJson!(string[string])(value); break;
			case "runEnvironments": bs.runEnvironments[suffix] = deserializeJson!(string[string])(value); break;
			case "preGenerateEnvironments": bs.preGenerateEnvironments[suffix] = deserializeJson!(string[string])(value); break;
			case "postGenerateEnvironments": bs.postGenerateEnvironments[suffix] = deserializeJson!(string[string])(value); break;
			case "preBuildEnvironments": bs.preBuildEnvironments[suffix] = deserializeJson!(string[string])(value); break;
			case "postBuildEnvironments": bs.postBuildEnvironments[suffix] = deserializeJson!(string[string])(value); break;
			case "preRunEnvironments": bs.preRunEnvironments[suffix] = deserializeJson!(string[string])(value); break;
			case "postRunEnvironments": bs.postRunEnvironments[suffix] = deserializeJson!(string[string])(value); break;
			case "buildRequirements":
				Flags!BuildRequirement reqs;
				foreach (req; deserializeJson!(string[])(value))
					reqs |= to!BuildRequirement(req);
				bs.buildRequirements[suffix] = reqs;
				break;
			case "buildOptions":
				Flags!BuildOption options;
				foreach (opt; deserializeJson!(string[])(value))
					options |= to!BuildOption(opt);
				bs.buildOptions[suffix] = options;
				break;
		}
	}
}

private Json toJson(const scope ref BuildSettingsTemplate bs)
{
	static string withSuffix (string pre, string post)
	{
		if (!post.length)
			return pre;
		return pre ~ "-" ~ post;
	}

	auto ret = Json.emptyObject;
	if( bs.dependencies !is null ){
		auto deps = Json.emptyObject;
		foreach( pack, d; bs.dependencies )
			deps[pack[]] = d.toJson();
		ret["dependencies"] = deps;
	}
	if (bs.systemDependencies !is null) ret["systemDependencies"] = bs.systemDependencies;
	if (bs.targetType != TargetType.autodetect) ret["targetType"] = bs.targetType.to!string();
	if (!bs.targetPath.empty) ret["targetPath"] = bs.targetPath;
	if (!bs.targetName.empty) ret["targetName"] = bs.targetName;
	if (!bs.workingDirectory.empty) ret["workingDirectory"] = bs.workingDirectory;
	if (!bs.mainSourceFile.empty) ret["mainSourceFile"] = bs.mainSourceFile;
	if (bs.subConfigurations.length > 0) ret["subConfigurations"] = serializeToJson(bs.subConfigurations);
	foreach (suffix, arr; bs.dflags) ret[withSuffix("dflags", suffix)] = serializeToJson(arr);
	foreach (suffix, arr; bs.lflags) ret[withSuffix("lflags", suffix)] = serializeToJson(arr);
	foreach (suffix, arr; bs.libs) ret[withSuffix("libs", suffix)] = serializeToJson(arr);
	foreach (suffix, arr; bs.sourceFiles) ret[withSuffix("sourceFiles", suffix)] = serializeToJson(arr);
	foreach (suffix, arr; bs.sourcePaths) ret[withSuffix("sourcePaths", suffix)] = serializeToJson(arr);
	foreach (suffix, arr; bs.excludedSourceFiles) ret[withSuffix("excludedSourceFiles", suffix)] = serializeToJson(arr);
	foreach (suffix, arr; bs.injectSourceFiles) ret[withSuffix("injectSourceFiles", suffix)] = serializeToJson(arr);
	foreach (suffix, arr; bs.copyFiles) ret[withSuffix("copyFiles", suffix)] = serializeToJson(arr);
	foreach (suffix, arr; bs.extraDependencyFiles) ret[withSuffix("extraDependencyFiles", suffix)] = serializeToJson(arr);
	foreach (suffix, arr; bs.versions) ret[withSuffix("versions", suffix)] = serializeToJson(arr);
	foreach (suffix, arr; bs.debugVersions) ret[withSuffix("debugVersions", suffix)] = serializeToJson(arr);
	foreach (suffix, arr; bs.versionFilters) ret[withSuffix("-versionFilters", suffix)] = serializeToJson(arr);
	foreach (suffix, arr; bs.debugVersionFilters) ret[withSuffix("-debugVersionFilters", suffix)] = serializeToJson(arr);
	foreach (suffix, arr; bs.importPaths) ret[withSuffix("importPaths", suffix)] = serializeToJson(arr);
	foreach (suffix, arr; bs.stringImportPaths) ret[withSuffix("stringImportPaths", suffix)] = serializeToJson(arr);
	foreach (suffix, arr; bs.preGenerateCommands) ret[withSuffix("preGenerateCommands", suffix)] = serializeToJson(arr);
	foreach (suffix, arr; bs.postGenerateCommands) ret[withSuffix("postGenerateCommands", suffix)] = serializeToJson(arr);
	foreach (suffix, arr; bs.preBuildCommands) ret[withSuffix("preBuildCommands", suffix)] = serializeToJson(arr);
	foreach (suffix, arr; bs.postBuildCommands) ret[withSuffix("postBuildCommands", suffix)] = serializeToJson(arr);
	foreach (suffix, arr; bs.preRunCommands) ret[withSuffix("preRunCommands", suffix)] = serializeToJson(arr);
	foreach (suffix, arr; bs.postRunCommands) ret[withSuffix("postRunCommands", suffix)] = serializeToJson(arr);
	foreach (suffix, aa; bs.environments) ret[withSuffix("environments", suffix)] = serializeToJson(aa);
	foreach (suffix, aa; bs.buildEnvironments) ret[withSuffix("buildEnvironments", suffix)] = serializeToJson(aa);
	foreach (suffix, aa; bs.runEnvironments) ret[withSuffix("runEnvironments", suffix)] = serializeToJson(aa);
	foreach (suffix, aa; bs.preGenerateEnvironments) ret[withSuffix("preGenerateEnvironments", suffix)] = serializeToJson(aa);
	foreach (suffix, aa; bs.postGenerateEnvironments) ret[withSuffix("postGenerateEnvironments", suffix)] = serializeToJson(aa);
	foreach (suffix, aa; bs.preBuildEnvironments) ret[withSuffix("preBuildEnvironments", suffix)] = serializeToJson(aa);
	foreach (suffix, aa; bs.postBuildEnvironments) ret[withSuffix("postBuildEnvironments", suffix)] = serializeToJson(aa);
	foreach (suffix, aa; bs.preRunEnvironments) ret[withSuffix("preRunEnvironments", suffix)] = serializeToJson(aa);
	foreach (suffix, aa; bs.postRunEnvironments) ret[withSuffix("postRunEnvironments", suffix)] = serializeToJson(aa);
	foreach (suffix, arr; bs.buildRequirements) {
		string[] val;
		foreach (i; [EnumMembers!BuildRequirement])
			if (arr & i) val ~= to!string(i);
		ret[withSuffix("buildRequirements", suffix)] = serializeToJson(val);
	}
	foreach (suffix, arr; bs.buildOptions) {
		string[] val;
		foreach (i; [EnumMembers!BuildOption])
			if (arr & i) val ~= to!string(i);
		ret[withSuffix("buildOptions", suffix)] = serializeToJson(val);
	}
	return ret;
}

private void parseJson(ref ToolchainRequirements tr, Json json)
{
	foreach (string name, value; json)
		tr.addRequirement(name, value.get!string);
}

private Json toJson(const scope ref ToolchainRequirements tr)
{
	auto ret = Json.emptyObject;
	if (tr.dub != Dependency.any) ret["dub"] = serializeToJson(tr.dub);
	if (tr.frontend != Dependency.any) ret["frontend"] = serializeToJson(tr.frontend);
	if (tr.dmd != Dependency.any) ret["dmd"] = serializeToJson(tr.dmd);
	if (tr.ldc != Dependency.any) ret["ldc"] = serializeToJson(tr.ldc);
	if (tr.gdc != Dependency.any) ret["gdc"] = serializeToJson(tr.gdc);
	return ret;
}

unittest {
	import std.string: strip, outdent;
	static immutable json = `
		{
			"name": "projectname",
			"environments": {
				"Var1": "env"
			},
			"buildEnvironments": {
				"Var2": "buildEnv"
			},
			"runEnvironments": {
				"Var3": "runEnv"
			},
			"preGenerateEnvironments": {
				"Var4": "preGenEnv"
			},
			"postGenerateEnvironments": {
				"Var5": "postGenEnv"
			},
			"preBuildEnvironments": {
				"Var6": "preBuildEnv"
			},
			"postBuildEnvironments": {
				"Var7": "postBuildEnv"
			},
			"preRunEnvironments": {
				"Var8": "preRunEnv"
			},
			"postRunEnvironments": {
				"Var9": "postRunEnv"
			}
		}
	`.strip.outdent;
	auto jsonValue = parseJsonString(json);
	PackageRecipe rec1;
	parseJson(rec1, jsonValue, PackageName.init);
	PackageRecipe rec;
	parseJson(rec, rec1.toJson(), PackageName.init); // verify that all fields are serialized properly

	assert(rec.name == "projectname");
	assert(rec.buildSettings.environments == ["": ["Var1": "env"]]);
	assert(rec.buildSettings.buildEnvironments == ["": ["Var2": "buildEnv"]]);
	assert(rec.buildSettings.runEnvironments == ["": ["Var3": "runEnv"]]);
	assert(rec.buildSettings.preGenerateEnvironments == ["": ["Var4": "preGenEnv"]]);
	assert(rec.buildSettings.postGenerateEnvironments == ["": ["Var5": "postGenEnv"]]);
	assert(rec.buildSettings.preBuildEnvironments == ["": ["Var6": "preBuildEnv"]]);
	assert(rec.buildSettings.postBuildEnvironments == ["": ["Var7": "postBuildEnv"]]);
	assert(rec.buildSettings.preRunEnvironments == ["": ["Var8": "preRunEnv"]]);
	assert(rec.buildSettings.postRunEnvironments == ["": ["Var9": "postRunEnv"]]);
}
