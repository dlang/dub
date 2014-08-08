module dub.internal.vibecompat.data.sdl;

//version (Have_vibe_d) public import vibe.data.sdl;
//else:

import dub.internal.vibecompat.data.utils;
import dub.internal.vibecompat.data.json;

import sdlang_.ast;
import sdlang_.parser;
import sdlang_.token : Value;
import sdlang_.exception : SDLangParseException;

import std.array;
import std.conv;
import std.datetime;
import std.exception;
import std.format;
import std.string;
import std.range;
import std.traits;

version(unittest) import std.stdio;

version = JsonLineNumbers;

version(JsonLineNumbers){
	import dub.internal.vibecompat.core.log;
}

Json sdlValueToJson(Value value)
{
	void* ptr;
	ptr = value.peek!(string);
	if(ptr) {
		//writefln("[DEBUG] sdlValueToJson: string \"%s\"", *(cast(string*)ptr));
		return Json(*(cast(string*)ptr));
	}
	
	else throw new Exception("Unknown SDL Value type");
}

/+
void printDebutAtLevel(args...)(int level)
{
	writef("[DEBUG]");
	foreach(i; 0..level) write(' ');
}
+/
Json sdlToJson(Tag rootTag)
{
	static int level = 0;

	Json[string] jsonMap;

	if(rootTag.attributes.empty && rootTag.tags.empty) {
		if(rootTag.values.empty) return Json();
		
		if(rootTag.values.length == 1) {
			//printDebutAtLevel(level);writefln("%s \"%s\"", rootTag.name, rootTag.values[0]);
			return sdlValueToJson(rootTag.values[0]);
		}
		
		//printDebutAtLevel(level);writefln("%s %s", rootTag.name, rootTag.values);
		Json[] jsonValues = new Json[rootTag.values.length];
		foreach(i, value; rootTag.values) {
			jsonValues[i] = sdlValueToJson(value);
		}
		return Json(jsonValues);
	}
	
	level += 2;
	foreach(value; rootTag.values) {
		//printDebutAtLevel(level);writefln("%s", value);
		jsonMap[sdlValueToJson(value).toString()] = Json();	
	}
	foreach(attr; rootTag.attributes) {
		//printDebutAtLevel(level);writefln("%s=%s", attr.name, attr.value);
		jsonMap[attr.name] = sdlValueToJson(attr.value);
	}
	foreach(subTag; rootTag.tags) {
		level += 2;
		jsonMap[subTag.name] = sdlToJson(subTag);
		level -= 2;
	}
	level -= 2;
	
	if(jsonMap.length > 0) return Json(jsonMap);
	return Json();
}


/**
	Parses the given JSON string and returns the corresponding Json object.

	Throws an Exception if any parsing error occurs.
*/
Json parseSdlString(string str)
{
	
	Tag tag;
	try {
		tag = parseSource(str);
	} catch(SDLangParseException e) {
		logError("Error at line: %s: %s", e.line, e.msg);
		throw e;
	} catch(Exception e) {
		logError("Error: %s", e.msg);
		throw e;
	}
	return sdlToJson(tag);
}




unittest {
	Json json;
	
	 json = parseSdlString(`
name "my-package"
description "A package for demonstration purposes"

dependency "vibe-d" version=">=0.7.13"
dependency "sub-package" version="~master" path="./sub-package"

# command line version
configuration "console" {
	targetType "executable"
	versions "ConsoleApp"
	libs-windows "gdi32" "user32"
}

# Win32 based GUI version
configuration "gui" {
	targetType "executable"
	versions "UseWinMain"
	libs-windows "gdi32" "user32"
}`);

writeln(json);


	json = parseSdlString(`
name "my-package"
description "A package for demonstration purposes"

dependencies {
	sub-package {
		version "~master"
		path "./sub-package"
	}
	vibe-d version=">=0.7.13"
}

# command line version
configuration "console" {
	targetType "executable"
	versions "ConsoleApp"
	libs-windows "gdi32" "user32"
}

# Win32 based GUI version
configuration "gui" {
	targetType "executable"
	versions "UseWinMain"
	libs-windows "gdi32" "user32"
}`);

writeln(json);

}

alias writeJsonString writeSdlString;
alias writePrettyJsonString writePrettySdlString;
