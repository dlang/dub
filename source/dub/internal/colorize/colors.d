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
  static enum type : int
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
static enum mode : int
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
  string ret;

  ret = "This is yellow".color(fg.yellow);
  assert(ret == "\033[33mThis is yellow\033[0m");

  ret = "This is light green".color(fg.light_green);
  assert(ret == "\033[92mThis is light green\033[0m");

  ret = "This is light blue with red background".color(fg.light_blue, bg.red);
  assert(ret == "\033[0;94;41mThis is light blue with red background\033[0m");

  ret = "This is red on blue blinking".color(fg.red, bg.blue, mode.blink);
  assert(ret == "\033[5;31;44mThis is red on blue blinking\033[0m");

  ret = color("This is magenta", "magenta");
  assert(ret == "\033[35mThis is magenta\033[0m");
}

string colorHelper(const string str, const string name) pure
{
  int code;

  switch(name)
  {
    case "init": code = 39; break;

    case "black"  : code = 30; break;
    case "red"    : code = 31; break;
    case "green"  : code = 32; break;
    case "yellow" : code = 33; break;
    case "blue"   : code = 34; break;
    case "magenta": code = 35; break;
    case "cyan"   : code = 36; break;
    case "white"  : code = 37; break;

    case "light_black"  : code = 90; break;
    case "light_red"    : code = 91; break;
    case "light_green"  : code = 92; break;
    case "light_yellow" : code = 93; break;
    case "light_blue"   : code = 94; break;
    case "light_magenta": code = 95; break;
    case "light_cyan"   : code = 96; break;
    case "light_white"  : code = 97; break;

    case "bg_init": code = 49; break;

    case "bg_black"  : code = 40; break;
    case "bg_red"    : code = 41; break;
    case "bg_green"  : code = 42; break;
    case "bg_yellow" : code = 43; break;
    case "bg_blue"   : code = 44; break;
    case "bg_magenta": code = 45; break;
    case "bg_cyan"   : code = 46; break;
    case "bg_white"  : code = 47; break;

    case "bg_light_black"  : code = 100; break;
    case "bg_light_red"    : code = 101; break;
    case "bg_light_green"  : code = 102; break;
    case "bg_light_yellow" : code = 103; break;
    case "bg_light_blue"   : code = 104; break;
    case "bg_light_magenta": code = 105; break;
    case "bg_light_cyan"   : code = 106; break;
    case "bg_light_white"  : code = 107; break;

    case "mode_init": code = 0; break;
    case "mode_bold"     : code = 1; break;
    case "mode_underline": code = 4; break;
    case "mode_blink"    : code = 5; break;
    case "mode_swap"     : code = 7; break;
    case "mode_hide"     : code = 8; break;

    default:
      throw new Exception(
        "Unknown fg color, bg color or mode \"" ~ name ~ "\""
      );
  }

  return format("\033[%dm%s\033[0m", code, str);
}

string colorHelper(T)(const string str, const T t=T.init) pure
  if(is(T : fg) || is(T : bg) || is(T : mode))
{
  return format("\033[%dm%s\033[0m", t, str);
}

alias colorHelper!bg background;
alias colorHelper!fg foreground;
alias colorHelper!mode style;

alias background color;
alias foreground color;
alias style color;
alias colorHelper color;

unittest
{
  string ret;

  ret = "This is red on blue blinking"
    .foreground(fg.red)
    .background(bg.blue)
    .style(mode.blink);

  assert(ret == "\033[5m\033[44m\033[31mThis is red on blue blinking\033[0m\033[0m\033[0m");
}
