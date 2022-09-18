/**
 * Authors: ponce
 * Date: July 28, 2014
 * License: Licensed under the MIT license. See LICENSE for more information
 * Version: 1.0.2
 */
module dub.internal.colorize.cwrite;

import std.stdio : File, stdout;

import dub.internal.colorize.winterm;

/// Coloured write.
void cwrite(T...)(T args) if (!is(T[0] : File))
{
	stdout.cwrite(args);
}

/// Coloured writef.
void cwritef(Char, T...)(in Char[] fmt, T args) if (!is(T[0] : File))
{
	stdout.cwritef(fmt, args);
}

/// Coloured writefln.
void cwritefln(Char, T...)(in Char[] fmt, T args)
{
	stdout.cwritef(fmt ~ "\n", args);
}

/// Coloured writeln.
void cwriteln(T...)(T args)
{
	// Most general instance
	stdout.cwrite(args, '\n');
}

/// Coloured writef to a File.
void cwritef(Char, A...)(File f, in Char[] fmt, A args)
{
	import std.string : format;
	auto s = format(fmt, args);
	f.cwrite(s);
}

/// Coloured writef to a File.
void cwrite(S...)(File f, S args)
{
	import std.conv : to;

	string s = "";
	foreach(arg; args)
	s ~= to!string(arg);

	version(Windows)
	{
		WinTermEmulation winterm;
		winterm.initialize();
		foreach(dchar c ; s)
		{
			auto charAction = winterm.feed(c);
			final switch(charAction) with (WinTermEmulation.CharAction)
			{
				case drop: break;
				case write: f.write(c); break;
				case flush: f.flush(); break;
			}
		}
	}
	else
	{
		f.write(s);
	}
}
