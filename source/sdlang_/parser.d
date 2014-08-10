// SDLang-D
// Written in the D programming language.

module sdlang_.parser;

import std.file;

import sdlang_.ast;
import sdlang_.exception;
import sdlang_.lexer;
import sdlang_.symbol;
import sdlang_.token;
import sdlang_.util;

/// Returns root tag.
Tag parseFile(string filename)
{
	auto source = cast(string)read(filename);
	return parseSource(source, filename);
}

/// Returns root tag. The optional 'filename' parameter can be included
/// so that the SDL document's filename (if any) can be displayed with
/// any syntax error messages.
Tag parseSource(string source, string filename=null)
{
	auto lexer = new Lexer(source, filename);
	auto parser = Parser(lexer);
	return parser.parseRoot();
}

private struct Parser
{
	Lexer lexer;
	
	private struct IDFull
	{
		string namespace;
		string name;
	}
	
	private void error(string msg)
	{
		error(lexer.front.location, msg);
	}

	private void error(Location loc, string msg)
	{
		throw new SDLangParseException(loc, "Error: "~msg);
	}

	/// <Root> ::= <Tags>  (Lookaheads: Anything)
	Tag parseRoot()
	{
		//trace("Starting parse of file: ", lexer.filename);

		auto root = new Tag(null, null, "root");
		root.location = Location(lexer.filename, 0, 0, 0);

		parseTags(root);
		return root;
	}

	/// <Tags> ::= <Tag> <Tags>  (Lookaheads: Ident Value)
	///        |   EOL   <Tags>  (Lookaheads: EOL)
	///        |   {empty}       (Lookaheads: Anything else)
	void parseTags(ref Tag parent)
	{
		while(true)
		{
			auto token = lexer.front;
			if(token.matches!"Ident"() || token.matches!"Value"())
			{
				parseTag(parent);
				continue;
			}
			else if(token.matches!"EOL"())
			{
				lexer.popFront();
				continue;
			}
			else
				break;
		}
	}

	/// <Tag>
	///     ::= <IDFull> <Values> <Attributes> <OptChild> <TagTerminator>  (Lookaheads: Ident)
	///     |   <Value>  <Values> <Attributes> <OptChild> <TagTerminator>  (Lookaheads: Value)
	void parseTag(ref Tag parent)
	{
		auto token = lexer.front;
		Tag tag;
		
		if(token.matches!"Ident"())
		{
			auto id = parseIDFull();
			tag = new Tag(parent, id.namespace, id.name);

			//trace("Found tag named: ", tag.fullName);
		}
		else if(token.matches!"Value"())
		{
			tag = new Tag(parent);
			parseValue(tag);

			//trace("Found anonymous tag.");
		}
		else
			error("Expected tag name or value, not " ~ token.symbol.name);

		tag.location = token.location;
		parseValues(tag);
		parseAttributes(tag);
		parseOptChild(tag);
		parseTagTerminator(tag);
	}

	/// <IDFull> ::= Ident <IDSuffix>  (Lookaheads: Ident)
	IDFull parseIDFull()
	{
		auto token = lexer.front;
		if(token.matches!"Ident"())
		{
			lexer.popFront();
			return parseIDSuffix(token.data);
		}
		else
		{
			error("Expected namespace or identifier, not " ~ token.symbol.name);
			assert(0);
		}
	}

	/// <IDSuffix>
	///     ::= ':' Ident  (Lookaheads: ':')
	///     ::= {empty}    (Lookaheads: Anything else)
	IDFull parseIDSuffix(string firstIdent)
	{
		auto token = lexer.front;
		if(token.matches!":"())
		{
			lexer.popFront();
			token = lexer.front;
			if(token.matches!"Ident"())
			{
				lexer.popFront();
				return IDFull(firstIdent, token.data);
			}
			else
			{
				error("Expected name, not " ~ token.symbol.name);
				assert(0);
			}
		}
		else
			return IDFull("", firstIdent);
	}

	/// <Values>
	///     ::= Value <Values>  (Lookaheads: Value)
	///     |   {empty}         (Lookaheads: Anything else)
	void parseValues(ref Tag parent)
	{
		while(true)
		{
			auto token = lexer.front;
			if(token.matches!"Value"())
			{
				parseValue(parent);
				continue;
			}
			else
				break;
		}
	}

	/// Handle Value terminals that aren't part of an attribute
	void parseValue(ref Tag parent)
	{
		auto token = lexer.front;
		if(token.matches!"Value"())
		{
			auto value = token.value;
			//trace("In tag '", parent.fullName, "', found value: ", value);
			parent.add(value);
			
			lexer.popFront();
		}
		else
			error("Expected value, not "~token.symbol.name);
	}

	/// <Attributes>
	///     ::= <Attribute> <Attributes>  (Lookaheads: Ident)
	///     |   {empty}                   (Lookaheads: Anything else)
	void parseAttributes(ref Tag parent)
	{
		while(true)
		{
			auto token = lexer.front;
			if(token.matches!"Ident"())
			{
				parseAttribute(parent);
				continue;
			}
			else
				break;
		}
	}

	/// <Attribute> ::= <IDFull> '=' Value  (Lookaheads: Ident)
	void parseAttribute(ref Tag parent)
	{
		auto token = lexer.front;
		if(!token.matches!"Ident"())
			error("Expected attribute name, not "~token.symbol.name);
		
		auto id = parseIDFull();
		
		token = lexer.front;
		if(!token.matches!"="())
			error("Expected '=' after attribute name, not "~token.symbol.name);
		
		lexer.popFront();
		token = lexer.front;
		if(!token.matches!"Value"())
			error("Expected attribute value, not "~token.symbol.name);
		
		auto attr = new Attribute(id.namespace, id.name, token.value, token.location);
		parent.add(attr);
		//trace("In tag '", parent.fullName, "', found attribute '", attr.fullName, "'");
		
		lexer.popFront();
	}

	/// <OptChild>
	///      ::= '{' EOL <Tags> '}'  (Lookaheads: '{')
	///      |   {empty}             (Lookaheads: Anything else)
	void parseOptChild(ref Tag parent)
	{
		auto token = lexer.front;
		if(token.matches!"{")
		{
			lexer.popFront();
			token = lexer.front;
			if(!token.matches!"EOL"())
				error("Expected newline or semicolon after '{', not "~token.symbol.name);
			
			lexer.popFront();
			parseTags(parent);
			
			token = lexer.front;
			if(!token.matches!"}"())
				error("Expected '}' after child tags, not "~token.symbol.name);
			lexer.popFront();
		}
		else
			{ /+ Do nothing, no error. +/ }
	}
	
	/// <TagTerminator>
	///     ::= EOL  (Lookahead: EOL)
	///     |   EOF  (Lookahead: EOF)
	void parseTagTerminator(ref Tag parent)
	{
		auto token = lexer.front;
		if(token.matches!"EOL" || token.matches!"EOF")
		{
			lexer.popFront();
		}
		else
			error("Expected end of tag (newline, semicolon or end-of-file), not " ~ token.symbol.name);
	}
}
