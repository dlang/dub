// SDLang-D
// Written in the D programming language.

module dub.internal.sdlang.parser;

version (Have_sdlang_d) public import sdlang.parser;
else:

import std.file;

import dub.internal.libInputVisitor;
import dub.internal.taggedalgebraic;

import dub.internal.sdlang.ast;
import dub.internal.sdlang.exception;
import dub.internal.sdlang.lexer;
import dub.internal.sdlang.symbol;
import dub.internal.sdlang.token;
import dub.internal.sdlang.util;

/// Returns root tag.
Tag parseFile(string filename)
{
	auto source = cast(string)read(filename);
	return parseSource(source, filename);
}

/// Returns root tag. The optional `filename` parameter can be included
/// so that the SDLang document's filename (if any) can be displayed with
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
parses a string passed in. The optional `filename` parameter in pullParseSource
can be included so that the SDLang document's filename (if any) can be displayed
with any syntax error messages.

Note: The old FileStartEvent and FileEndEvent events
$(LINK2 https://github.com/Abscissa/SDLang-D/issues/17, were deemed unnessecary)
and removed as of SDLang-D v0.10.0.

Note: Previously, in SDLang-D v0.9.x, ParserEvent was a
$(LINK2 http://dlang.org/phobos/std_variant.html#.Algebraic, std.variant.Algebraic).
As of SDLang-D v0.10.0, it is now a
$(LINK2 https://github.com/s-ludwig/taggedalgebraic, TaggedAlgebraic),
so usage has changed somewhat.

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
TagStartEvent (lastTag)
TagEndEvent
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
	auto parser = PullParser(lexer);
	return inputVisitor!ParserEvent( parser );
}

///
@("pullParseFile/pullParseSource example")
unittest
{
	// stuff.sdl
	immutable stuffSdl = `
		name "sdlang-d"
		description "An SDL (Simple Declarative Language) library for D."
		homepage "http://github.com/Abscissa/SDLang-D"
		
		configuration "library" {
			targetType "library"
		}
	`;
	
	import std.stdio;

	foreach(event; pullParseSource(stuffSdl))
	final switch(event.kind)
	{
	case ParserEvent.Kind.tagStart:
		auto e = cast(TagStartEvent) event;
		//writeln("TagStartEvent: ", e.namespace, ":", e.name, " @ ", e.location);
		break;

	case ParserEvent.Kind.tagEnd:
		auto e = cast(TagEndEvent) event;
		//writeln("TagEndEvent");
		break;

	case ParserEvent.Kind.value:
		auto e = cast(ValueEvent) event;
		//writeln("ValueEvent: ", e.value);
		break;

	case ParserEvent.Kind.attribute:
		auto e = cast(AttributeEvent) event;
		//writeln("AttributeEvent: ", e.namespace, ":", e.name, "=", e.value);
		break;
	}
}

private union ParserEventUnion
{
	TagStartEvent  tagStart;
	TagEndEvent    tagEnd;
	ValueEvent     value;
	AttributeEvent attribute;
}

/++
The element of the InputRange returned by pullParseFile and pullParseSource.

This is a tagged union, built from the following:
-------
alias ParserEvent = TaggedAlgebraic!ParserEventUnion;
private union ParserEventUnion
{
	TagStartEvent  tagStart;
	TagEndEvent    tagEnd;
	ValueEvent     value;
	AttributeEvent attribute;
}
-------

Note: The old FileStartEvent and FileEndEvent events
$(LINK2 https://github.com/Abscissa/SDLang-D/issues/17, were deemed unnessecary)
and removed as of SDLang-D v0.10.0.

Note: Previously, in SDLang-D v0.9.x, ParserEvent was a
$(LINK2 http://dlang.org/phobos/std_variant.html#.Algebraic, std.variant.Algebraic).
As of SDLang-D v0.10.0, it is now a
$(LINK2 https://github.com/s-ludwig/taggedalgebraic, TaggedAlgebraic),
so usage has changed somewhat.
+/
alias ParserEvent = TaggedAlgebraic!ParserEventUnion;

///
@("ParserEvent example")
unittest
{
	// Create
	ParserEvent event1 = TagStartEvent();
	ParserEvent event2 = TagEndEvent();
	ParserEvent event3 = ValueEvent();
	ParserEvent event4 = AttributeEvent();

	// Check type
	assert(event1.kind == ParserEvent.Kind.tagStart);
	assert(event2.kind == ParserEvent.Kind.tagEnd);
	assert(event3.kind == ParserEvent.Kind.value);
	assert(event4.kind == ParserEvent.Kind.attribute);

	// Cast to base type
	auto e1 = cast(TagStartEvent) event1;
	auto e2 = cast(TagEndEvent) event2;
	auto e3 = cast(ValueEvent) event3;
	auto e4 = cast(AttributeEvent) event4;
	//auto noGood = cast(AttributeEvent) event1; // AssertError: event1 is a TagStartEvent, not AttributeEvent.

	// Use as base type.
	// In many cases, no casting is even needed.
	event1.name = "foo";  
	//auto noGood = event3.name; // AssertError: ValueEvent doesn't have a member 'name'.

	// Final switch is supported:
	final switch(event1.kind)
	{
		case ParserEvent.Kind.tagStart:  break;
		case ParserEvent.Kind.tagEnd:    break;
		case ParserEvent.Kind.value:     break;
		case ParserEvent.Kind.attribute: break;
	}
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
private struct PullParser
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
		throw new ParseException(loc, "Error: "~msg);
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

		parseTags();
		
		auto token = lexer.front;
		if(token.matches!":"())
		{
			lexer.popFront();
			token = lexer.front;
			if(token.matches!"Ident"())
			{
				error("Missing namespace. If you don't wish to use a namespace, then say '"~token.data~"', not ':"~token.data~"'");
				assert(0);
			}
			else
			{
				error("Missing namespace. If you don't wish to use a namespace, then omit the ':'");
				assert(0);
			}
		}
		else if(!token.matches!"EOF"())
			error("Expected a tag or end-of-file, not " ~ token.symbol.name);
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
				error("Found start of child block, but no tag name. If you intended an anonymous "~
				"tag, you must have at least one value before any attributes or child tags.");
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
			error("Found attribute, but no tag name. If you intended an anonymous "~
			"tag, you must have at least one value before any attributes.");

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
		final switch(event.kind)
		{
		case ParserEvent.Kind.tagStart:
			auto newTag = new Tag(currTag, event.namespace, event.name);
			newTag.location = event.location;
			
			currTag = newTag;
			break;

		case ParserEvent.Kind.tagEnd:
			currTag = currTag.parent;

			if(!currTag)
				parser.error("Internal Error: Received an extra TagEndEvent");
			break;

		case ParserEvent.Kind.value:
			currTag.add((cast(ValueEvent)event).value);
			break;

		case ParserEvent.Kind.attribute:
			auto e = cast(AttributeEvent) event;
			auto attr = new Attribute(e.namespace, e.name, e.value, e.location);
			currTag.add(attr);
			break;
		}
		
		return currTag;
	}
}

// Other parser tests are part of the AST's tests over in the ast module.

// Regression test, issue #13: https://github.com/Abscissa/SDLang-D/issues/13
// "Incorrectly accepts ":tagname" (blank namespace, tagname prefixed with colon)"
@("parser: Regression test issue #13")
unittest
{
	import std.exception;
	assertThrown!ParseException(parseSource(`:test`));
	assertThrown!ParseException(parseSource(`:4`));
}

// Regression test, issue #16: https://github.com/Abscissa/SDLang-D/issues/16
@("parser: Regression test issue #16")
unittest
{
	// Shouldn't crash
	foreach(event; pullParseSource(`tag "data"`))
	{
		if(event.kind == ParserEvent.Kind.tagStart)
			auto e = cast(TagStartEvent) event;
	}
}

// Regression test, issue #31: https://github.com/Abscissa/SDLang-D/issues/31
// "Escape sequence results in range violation error"
@("parser: Regression test issue #31")
unittest
{
	// Shouldn't get a Range violation
	parseSource(`test "\"foo\""`);
}
