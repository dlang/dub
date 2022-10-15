/**
 * Authors: Pedro Tacla Yamada
 * Date: June 9, 2014
 * License: Licensed under the MIT license. See LICENSE for more information
 * Version: 1.0.2
 */
module dub.internal.colorize.colors;

import std.string : format;

private template color_type(int offset)
{
	enum type : int
	{
		init = 39 + offset,

		black   = 30 + offset,
		red     = 31 + offset,
		green   = 32 + offset,
		yellow  = 33 + offset,
		blue    = 34 + offset,
		magenta = 35 + offset,
		cyan    = 36 + offset,
		white   = 37 + offset,

		light_black   = 90 + offset,
		light_red     = 91 + offset,
		light_green   = 92 + offset,
		light_yellow  = 93 + offset,
		light_blue    = 94 + offset,
		light_magenta = 95 + offset,
		light_cyan    = 96 + offset,
		light_white   = 97 + offset
	}
}

alias color_type!0 .type fg;
alias color_type!10 .type bg;

// Text modes
enum mode : int
{
	init      = 0,
	bold      = 1,
	underline = 4,
	blink     = 5,
	swap      = 7,
	hide      = 8
}

/**
 * Wraps a string around color escape sequences.
 *
 * Params:
 *   str = The string to wrap with colors and modes
 *   c   = The foreground color (see the fg enum type)
 *   b   = The background color (see the bg enum type)
 *   m   = The text mode        (see the mode enum type)
 * Example:
 * ---
 * writeln("This is blue".color(fg.blue));
 * writeln(
 *   color("This is red over green blinking", fg.blue, bg.green, mode.blink)
 * );
 * ---
 */
string color(
	const string str,
	const fg c=fg.init,
	const bg b=bg.init,
	const mode m=mode.init
) pure
{
	return format("\033[%d;%d;%dm%s\033[0m", m, c, b, str);
}

unittest
{
	import std.string : representation;

	string ret;

	ret = "This is yellow".color(fg.yellow);
	assert(ret.representation == "\033[0;33;49mThis is yellow\033[0m".representation);

	ret = "This is light green".color(fg.light_green);
	assert(ret.representation == "\033[0;92;49mThis is light green\033[0m".representation);

	ret = "This is light blue with red background".color(fg.light_blue, bg.red);
	assert(ret.representation == "\033[0;94;41mThis is light blue with red background\033[0m".representation);

	ret = "This is red on blue blinking".color(fg.red, bg.blue, mode.blink);
	assert(ret.representation == "\033[5;31;44mThis is red on blue blinking\033[0m".representation);
}

string colorHelper(T)(const string str, const T t=T.init) pure
	if(is(T : fg) || is(T : bg) || is(T : mode))
{
	return format("\033[%dm%s\033[0m", t, str);
}

alias background = colorHelper!bg;
alias foreground = colorHelper!fg;
alias style = colorHelper!mode;
alias color = colorHelper;

unittest
{
	import std.string : representation;

	string ret;

	ret = "This is red on blue blinking"
		.foreground(fg.red)
		.background(bg.blue)
		.style(mode.blink);
	assert(ret.representation == "\033[5m\033[44m\033[31mThis is red on blue blinking\033[0m\033[0m\033[0m".representation);
}
