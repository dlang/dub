// SDLang-D
// Written in the D programming language.

module dub.internal.sdlang.symbol;

version (Have_sdlang_d) public import sdlang.symbol;
else:

import std.algorithm;

static immutable validSymbolNames = [
	"Error",
	"EOF",
	"EOL",

	":",
	"=",
	"{",
	"}",

	"Ident",
	"Value",
];

/// Use this to create a Symbol. Ex: symbol!"Value" or symbol!"="
/// Invalid names (such as symbol!"FooBar") are rejected at compile-time.
template symbol(string name)
{
	static assert(validSymbolNames.find(name), "Invalid Symbol: '"~name~"'");
	immutable symbol = _symbol(name);
}

private Symbol _symbol(string name)
{
	return Symbol(name);
}

/// Symbol is essentially the "type" of a Token.
/// Token is like an instance of a Symbol.
///
/// This only represents terminals. Non-terminal tokens aren't
/// constructed since the AST is built directly during parsing.
///
/// You can't create a Symbol directly. Instead, use the 'symbol'
/// template.
struct Symbol
{
	private string _name;
	@property string name()
	{
		return _name;
	}

	@disable this();
	private this(string name)
	{
		this._name = name;
	}

	string toString()
	{
		return _name;
	}
}
