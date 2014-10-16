// SDLang-D
// Written in the D programming language.

module sdlang.exception;

import std.exception;
import std.string;

import sdlang.util;

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
