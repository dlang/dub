/**
	SDL format support for PackageRecipe

	Copyright: © 2014 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.recipe.sdl;

import std.string : format, indexOf;

import dub.internal.vibecompat.core.log;
import dub.recipe.packagerecipe;

import sdlang.parser;
import sdlang.lexer;

// Maybe later it would be useful to implement SDL namespaces
// immutable string dubNamespace = "dub";

void parseError(string msg, string file = __FILE__, size_t line = __LINE__)
{
	throw new Exception(msg, file, line);
}

ValueType getValue(ValueType,T)(ref TagStartEvent tagStart, T pullParser)
{
	pullParser.popFront();
	if(pullParser.empty) {
		parseError(format("tag '%s' is missing a string value at %s", tagStart.name, tagStart.location));
	}
	auto event = pullParser.front;
	
	auto valueEvent = event.peek!ValueEvent();	
	if( !valueEvent ) {
		parseError(format("tag '%s' is missing a string value at %s", tagStart.name, tagStart.location));
	}
	
	return valueEvent.value.get!ValueType;
}

void skipToEndOfTag(T)(ref T pullParser)
{
	while(true) {
		if(pullParser.empty) break;
		pullParser.popFront();
		if(pullParser.front.peek!TagEndEvent()) break;
	}
}

void parseSDL(ref PackageRecipe recipe, string filename, string sdlText, string parent_name)
{
	scope lexer = new Lexer(sdlText, filename);
	auto pullParser = pullParse(lexer);
	
	//
	// First Event should always be FileStart, get rid of it
	//
	assert(!pullParser.empty);
	assert(pullParser.front.peek!FileStartEvent());
	pullParser.popFront();
	
	parseSDLPackage(recipe, pullParser, parent_name);
}

void parseSDLPackage(T)(ref PackageRecipe recipe, T pullParser, string parent_name)
{	
	size_t tagDepth = 0;

	TagStartEvent currentTag;
	
	string fullname = null;
	
	for( ;!pullParser.empty; pullParser.popFront()) {
		auto event = pullParser.front;		
		
		if(auto peekTagStart = event.peek!TagStartEvent()) {
			tagDepth++;
			//logDebug("[SDL] TagStart: %s:%s @ %s", e.namespace, e.name, e.location);
			
			if(peekTagStart.namespace.length > 0) {
				parseError(format("SDL Namespaces not handled: found namespace '%s' at %s", peekTagStart.namespace, peekTagStart.location));
			}
			currentTag = *peekTagStart;
			// TODO: should we check if some of these member variables appear twice in the same SDL file?
			//       for example, before setting the name variable, should it be checked if it has already been set first?
		
			switch (currentTag.name) {
				default: skipToEndOfTag(pullParser); break;
				case "name":
					recipe.name = currentTag.getValue!string(pullParser);
					fullname = parent_name.length ? parent_name ~ ":" ~ recipe.name : recipe.name;
					break;
				case "version": recipe.version_ = currentTag.getValue!string(pullParser); break;
				case "description": recipe.description = currentTag.getValue!string(pullParser); break;
				case "homepage": recipe.homepage = currentTag.getValue!string(pullParser); break;
				case "author": recipe.authors ~= currentTag.getValue!string(pullParser); break;
				case "copyright": recipe.copyright = currentTag.getValue!string(pullParser); break;
				case "license": recipe.license = currentTag.getValue!string(pullParser); break;
				case "configurations":
					throw new Exception("configurations not implemented");
				
					//break;
				case "subPackage":				
				
					if(fullname is null) {
						parseError("the package name must appear before any subPackages");
					}				
					recipe.parseSubPackage(pullParser, fullname);
					break;
				case "buildTypes":
					throw new Exception("buildTypes not implemented");
					/*
					foreach (string name, settings; value) {
						BuildSettingsTemplate bs;
						bs.parseSDL(settings, null);
						recipe.buildTypes[name] = bs;
					}
					break;
					*/
				case "-ddoxFilterArg": recipe.ddoxFilterArgs ~= currentTag.getValue!string(pullParser); break;
				
				/**/
				/**/
				/**/
				/**/
				/**/
				/**/
				/**/
				/**/
				/* BUILD SETTINGS */
				/**/
				/**/
				/**/
				/**/
				/**/
				/**/
				/*
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
				bs.targetType = value.get!string().to!TargetType();
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
			case "sourcePath": bs.sourcePaths[suffix] ~= [value.get!string()]; break; // deprecated
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
					reqs |= to!BuildRequirements(req);
				bs.buildRequirements[suffix] = reqs;
				break;
			case "buildOptions":
				BuildOptions options;
				foreach (opt; deserializeJson!(string[])(value))
					options |= to!BuildOptions(opt);
				bs.buildOptions[suffix] = options;
				break;
				*/
			/**/
				/**/
				/**/
				/**/
				/**/
				/**/
				/**/
				/**/
				/**/
				/**/
				/**/
				/**/
				/**/
				/**/
				/**/
				/**/
				
				
				
				
				
			}
		} else if(event.peek!TagEndEvent()) {
		
			if(tagDepth == 0) break;
			
		} else if(auto e = event.peek!ValueEvent()) {
			parseError(format("tag '%s' has too many values at %s", currentTag.name, currentTag.location));
		} else if(auto e = event.peek!AttributeEvent()) {
			parseError(format("tag '%s' has too many attributes at %s", currentTag.name, currentTag.location));
		} else {
			assert(event.peek!FileEndEvent(), "Unhandled sdl event");
		}
	}
	
	enforce(recipe.name.length > 0, "The package \"name\" field is missing or empty.");	


	// parse build settings
	/*
	recipe.buildSettings.parseSDL(json, fullname);
	if (auto pv = "configurations" in json) {
		TargetType deftargettp = TargetType.library;
		if (recipe.buildSettings.targetType != TargetType.autodetect)
			deftargettp = recipe.buildSettings.targetType;

		foreach (settings; *pv) {
			ConfigurationInfo ci;
			ci.parseSDL(settings, recipe.name, deftargettp);
			recipe.configurations ~= ci;
		}
	}
	*/
}

private void parseSubPackage(T)(ref PackageRecipe recipe, T pullParser, string parent_package_name)
{
	enforce(parent_package_name.indexOf(":") == -1, format("'subPackages' found in '%s'. This is only supported in the main package file for '%s'.",
		parent_package_name, getBasePackageName(parent_package_name)));

	//
	// Check if it is a subpackage reference
	//
	pullParser.popFront();		
	auto valueEvent = pullParser.front.peek!ValueEvent();	
	if( valueEvent ) {
		auto subpath = valueEvent.value.get!string();
		recipe.subPackages ~= SubPackage(subpath, PackageRecipe.init);
	} else {	
		PackageRecipe subinfo;
		subinfo.parseSDLPackage(pullParser, parent_package_name);
		recipe.subPackages ~= SubPackage(null, subinfo);
	}
}
