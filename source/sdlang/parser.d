// SDLang-D
// Written in the D programming language.

module sdlang.parser;

import std.file;

import libInputVisitor;

import sdlang.ast;
import sdlang.exception;
import sdlang.lexer;
import sdlang.symbol;
import sdlang.token;
import sdlang.util;

import std.stdio;

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
	auto parser = DOMParser(lexer);
	return parser.parseRoot();
}

/++
Parses an SDL document using StAX/Pull-style. Returns an InputRange with
element type ParserEvent.

The pullParseFile version reads a file and parses it, while pullParseSource
parses a string passed in. The optional 'filename' parameter in pullParseSource
can be included so that the SDL document's filename (if any) can be displayed
with any syntax error messages.

Example:
------------------
parent 12 attr="q" {
	childA 34
	childB 56
}
lastTag
------------------

The ParserEvent sequence emitted for that SDL document would be as
follows (indented for readability):
------------------
FileStartEvent
	TagStartEvent (parent)
		ValueEvent (12)
		AttributeEvent (attr, "q")
		TagStartEvent (childA)
			ValueEvent (34)
		TagEndEvent
		TagStartEvent (childB)
			ValueEvent (56)
		TagEndEvent
	TagEndEvent
	TagStartEvent  (lastTag)
	TagEndEvent
FileEndEvent
------------------

Example:
------------------
foreach(event; pullParseFile("stuff.sdl"))
{
	import std.stdio;

	if(event.peek!FileStartEvent())
		writeln("FileStartEvent, starting! ");

	else if(event.peek!FileEndEvent())
		writeln("FileEndEvent, done! ");

	else if(auto e = event.peek!TagStartEvent())
		writeln("TagStartEvent: ", e.namespace, ":", e.name, " @ ", e.location);

	else if(event.peek!TagEndEvent())
		writeln("TagEndEvent");

	else if(auto e = event.peek!ValueEvent())
		writeln("ValueEvent: ", e.value);

	else if(auto e = event.peek!AttributeEvent())
		writeln("AttributeEvent: ", e.namespace, ":", e.name, "=", e.value);

	else // Shouldn't happen
		throw new Exception("Received unknown parser event");
}
------------------
+/
auto pullParseFile(string filename)
{
	auto source = cast(string)read(filename);
	return parseSource(source, filename);
}

///ditto
auto pullParseSource(string source, string filename=null)
{
	auto lexer = new Lexer(source, filename);
	auto parser = new PullParser(lexer);
	return inputVisitor!ParserEvent( *parser );
}

///ditto
auto pullParse(scope Lexer lexer)
{
	auto parser = new PullParser(lexer);
	return inputVisitor!ParserEvent( *parser );
}

/// The element of the InputRange returned by pullParseFile and pullParseSource:
alias ParserEvent = std.variant.Algebraic!(
	FileStartEvent,
	FileEndEvent,
	TagStartEvent,
	TagEndEvent,
	ValueEvent,
	AttributeEvent,
);

/// Event: Start of file
struct FileStartEvent
{
	Location location;
}

/// Event: End of file
struct FileEndEvent
{
	Location location;
}

/// Event: Start of tag
struct TagStartEvent
{
	Location location;
	string namespace;
	string name;
}

/// Event: End of tag
struct TagEndEvent
{
	//Location location;
}

/// Event: Found a Value in the current tag
struct ValueEvent
{
	Location location;
	Value value;
}

/// Event: Found an Attribute in the current tag
struct AttributeEvent
{
	Location location;
	string namespace;
	string name;
	Value value;
}

// The actual pull parser
struct PullParser
{
	private Lexer lexer;
	
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
	
	private InputVisitor!(PullParser, ParserEvent) v;
	
	void visit(InputVisitor!(PullParser, ParserEvent) v)
	{
		this.v = v;
		parseRoot();
	}
	
	private void emit(Event)(Event event)
	{
		v.yield( ParserEvent(event) );
	}
	
	/// <Root> ::= <Tags> EOF  (Lookaheads: Anything)
	private void parseRoot()
	{
		//trace("Starting parse of file: ", lexer.filename);
		//trace(__FUNCTION__, ": <Root> ::= <Tags> EOF  (Lookaheads: Anything)");	
		
		
		auto startLocation = Location(lexer.filename, 0, 0, 0);
		emit( FileStartEvent(startLocation) );

		parseTags();
		
		auto token = lexer.front;
		if(!token.matches!"EOF"())
			error("Expected end-of-file, not " ~ token.symbol.name);
		
		emit( FileEndEvent(token.location) );
	}

	/// <Tags> ::= <Tag> <Tags>  (Lookaheads: Ident Value)
	///        |   EOL   <Tags>  (Lookaheads: EOL)
	///        |   {empty}       (Lookaheads: Anything else, except '{')
	void parseTags()
	{
		//trace("Enter ", __FUNCTION__);
		while(true)
		{
			auto token = lexer.front;
			if(token.matches!"Ident"() || token.matches!"Value"())
			{
				//trace(__FUNCTION__, ": <Tags> ::= <Tag> <Tags>  (Lookaheads: Ident Value)");
				parseTag();
				continue;
			}
			else if(token.matches!"EOL"())
			{
				//trace(__FUNCTION__, ": <Tags> ::= EOL <Tags>  (Lookaheads: EOL)");
				lexer.popFront();
				continue;
			}
			else if(token.matches!"{"())
			{
				error("Anonymous tags must have at least one value. They cannot just have children and attributes only.");
			}
			else
			{
				//trace(__FUNCTION__, ": <Tags> ::= {empty}  (Lookaheads: Anything else, except '{')");
				break;
			}
		}
	}

	/// <Tag>
	///     ::= <IDFull> <Values> <Attributes> <OptChild> <TagTerminator>  (Lookaheads: Ident)
	///     |   <Value>  <Values> <Attributes> <OptChild> <TagTerminator>  (Lookaheads: Value)
	void parseTag()
	{
		auto token = lexer.front;
		if(token.matches!"Ident"())
		{
			//trace(__FUNCTION__, ": <Tag> ::= <IDFull> <Values> <Attributes> <OptChild> <TagTerminator>  (Lookaheads: Ident)");
			//trace("Found tag named: ", tag.fullName);
			auto id = parseIDFull();
			emit( TagStartEvent(token.location, id.namespace, id.name) );
		}
		else if(token.matches!"Value"())
		{
			//trace(__FUNCTION__, ": <Tag> ::= <Value>  <Values> <Attributes> <OptChild> <TagTerminator>  (Lookaheads: Value)");
			//trace("Found anonymous tag.");
			emit( TagStartEvent(token.location, null, null) );
		}
		else
			error("Expected tag name or value, not " ~ token.symbol.name);

		if(lexer.front.matches!"="())
			error("Anonymous tags must have at least one value. They cannot just have attributes and children only.");

		parseValues();
		parseAttributes();
		parseOptChild();
		parseTagTerminator();
		
		emit( TagEndEvent() );
	}

	/// <IDFull> ::= Ident <IDSuffix>  (Lookaheads: Ident)
	IDFull parseIDFull()
	{
		auto token = lexer.front;
		if(token.matches!"Ident"())
		{
			//trace(__FUNCTION__, ": <IDFull> ::= Ident <IDSuffix>  (Lookaheads: Ident)");
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
			//trace(__FUNCTION__, ": <IDSuffix> ::= ':' Ident  (Lookaheads: ':')");
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
		{
			//trace(__FUNCTION__, ": <IDSuffix> ::= {empty}  (Lookaheads: Anything else)");
			return IDFull("", firstIdent);
		}
	}

	/// <Values>
	///     ::= Value <Values>  (Lookaheads: Value)
	///     |   {empty}         (Lookaheads: Anything else)
	void parseValues()
	{
		while(true)
		{
			auto token = lexer.front;
			if(token.matches!"Value"())
			{
				//trace(__FUNCTION__, ": <Values> ::= Value <Values>  (Lookaheads: Value)");
				parseValue();
				continue;
			}
			else
			{
				//trace(__FUNCTION__, ": <Values> ::= {empty}  (Lookaheads: Anything else)");
				break;
			}
		}
	}

	/// Handle Value terminals that aren't part of an attribute
	void parseValue()
	{
		auto token = lexer.front;
		if(token.matches!"Value"())
		{
			//trace(__FUNCTION__, ": (Handle Value terminals that aren't part of an attribute)");
			auto value = token.value;
			//trace("In tag '", parent.fullName, "', found value: ", value);
			emit( ValueEvent(token.location, value) );
			
			lexer.popFront();
		}
		else
			error("Expected value, not "~token.symbol.name);
	}

	/// <Attributes>
	///     ::= <Attribute> <Attributes>  (Lookaheads: Ident)
	///     |   {empty}                   (Lookaheads: Anything else)
	void parseAttributes()
	{
		while(true)
		{
			auto token = lexer.front;
			if(token.matches!"Ident"())
			{
				//trace(__FUNCTION__, ": <Attributes> ::= <Attribute> <Attributes>  (Lookaheads: Ident)");
				parseAttribute();
				continue;
			}
			else
			{
				//trace(__FUNCTION__, ": <Attributes> ::= {empty}  (Lookaheads: Anything else)");
				break;
			}
		}
	}

	/// <Attribute> ::= <IDFull> '=' Value  (Lookaheads: Ident)
	void parseAttribute()
	{
		//trace(__FUNCTION__, ": <Attribute> ::= <IDFull> '=' Value  (Lookaheads: Ident)");
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
		
		//trace("In tag '", parent.fullName, "', found attribute '", attr.fullName, "'");
		emit( AttributeEvent(token.location, id.namespace, id.name, token.value) );
		
		lexer.popFront();
	}

	/// <OptChild>
	///      ::= '{' EOL <Tags> '}'  (Lookaheads: '{')
	///      |   {empty}             (Lookaheads: Anything else)
	void parseOptChild()
	{
		auto token = lexer.front;
		if(token.matches!"{")
		{
			//trace(__FUNCTION__, ": <OptChild> ::= '{' EOL <Tags> '}'  (Lookaheads: '{')");
			lexer.popFront();
			token = lexer.front;
			if(!token.matches!"EOL"())
				error("Expected newline or semicolon after '{', not "~token.symbol.name);
			
			lexer.popFront();
			parseTags();
			
			token = lexer.front;
			if(!token.matches!"}"())
				error("Expected '}' after child tags, not "~token.symbol.name);
			lexer.popFront();
		}
		else
		{
			//trace(__FUNCTION__, ": <OptChild> ::= {empty}  (Lookaheads: Anything else)");
			// Do nothing, no error.
		}
	}
	
	/// <TagTerminator>
	///     ::= EOL      (Lookahead: EOL)
	///     |   {empty}  (Lookahead: EOF)
	void parseTagTerminator()
	{
		auto token = lexer.front;
		if(token.matches!"EOL")
		{
			//trace(__FUNCTION__, ": <TagTerminator> ::= EOL  (Lookahead: EOL)");
			lexer.popFront();
		}
		else if(token.matches!"EOF")
		{
			//trace(__FUNCTION__, ": <TagTerminator> ::= {empty}  (Lookahead: EOF)");
			// Do nothing
		}
		else
			error("Expected end of tag (newline, semicolon or end-of-file), not " ~ token.symbol.name);
	}
}

private struct DOMParser
{
	Lexer lexer;
	
	Tag parseRoot()
	{
		auto currTag = new Tag(null, null, "root");
		currTag.location = Location(lexer.filename, 0, 0, 0);
		
		auto parser = PullParser(lexer);
		auto eventRange = inputVisitor!ParserEvent( parser );
		foreach(event; eventRange)
		{
			if(auto e = event.peek!TagStartEvent())
			{
				auto newTag = new Tag(currTag, e.namespace, e.name);
				newTag.location = e.location;
				
				currTag = newTag;
			}
			else if(event.peek!TagEndEvent())
			{
				currTag = currTag.parent;

				if(!currTag)
					parser.error("Internal Error: Received an extra TagEndEvent");
			}
			else if(auto e = event.peek!ValueEvent())
			{
				currTag.add(e.value);
			}
			else if(auto e = event.peek!AttributeEvent())
			{
				auto attr = new Attribute(e.namespace, e.name, e.value, e.location);
				currTag.add(attr);
			}
			else if(event.peek!FileStartEvent())
			{
				// Do nothing
			}
			else if(event.peek!FileEndEvent())
			{
				// There shouldn't be another parent.
				if(currTag.parent)
					parser.error("Internal Error: Unexpected end of file, not enough TagEndEvent");
			}
			else
				parser.error("Internal Error: Received unknown parser event");
		}
		
		return currTag;
	}
}

// Parser tests are part of the AST's tests over in the ast module.
