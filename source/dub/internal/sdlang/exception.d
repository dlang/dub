// SDLang-D
// Written in the D programming language.

module dub.internal.sdlang.exception;

version (Have_sdlang_d) public import sdlang.exception;
else:

import std.exception;
import std.string;

import dub.internal.sdlang.util;

abstract class SDLangException : Exception
{
	this(string msg) { super(msg); }
}

class SDLangParseException : SDLangException
{
	Location location;
	bool hasLocation;

	this(string msg)
	{
		hasLocation = false;
		super(msg);
	}

	this(Location location, string msg)
	{
		hasLocation = true;
		super("%s: %s".format(location.toString(), msg));
	}
}

class SDLangValidationException : SDLangException
{
	this(string msg) { super(msg); }
}

class SDLangRangeException : SDLangException
{
	this(string msg) { super(msg); }
}
