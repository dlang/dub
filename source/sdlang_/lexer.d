// SDLang-D
// Written in the D programming language.

module sdlang_.lexer;

import std.algorithm;
import std.array;
import std.base64;
import std.bigint;
import std.conv;
import std.datetime;
import std.file;
import std.stream : ByteOrderMarks, BOM;
import std.traits;
import std.typecons;
import std.uni;
import std.utf;
import std.variant;

import sdlang_.exception;
import sdlang_.symbol;
import sdlang_.token;
import sdlang_.util;

alias sdlang_.util.startsWith startsWith;

Token[] lexFile(string filename)
{
	auto source = cast(string)read(filename);
	return lexSource(source, filename);
}

Token[] lexSource(string source, string filename=null)
{
	auto lexer = scoped!Lexer(source, filename);
	
	// Can't use 'std.array.array(Range)' because 'lexer' is scoped
	// and therefore cannot have its reference copied.
	Appender!(Token[]) tokens;
	foreach(tok; lexer)
		tokens.put(tok);

	return tokens.data;
}

// Kind of a poor-man's yield, but fast.
// Only to be used inside Lexer.popFront (and Lexer.this).
private template accept(string symbolName)
{
	static assert(symbolName != "Value", "Value symbols must also take a value.");
	enum accept = acceptImpl!(symbolName, "null");
}
private template accept(string symbolName, string value)
{
	static assert(symbolName == "Value", "Only a Value symbol can take a value.");
	enum accept = acceptImpl!(symbolName, value);
}
private template accept(string symbolName, string value, string startLocation, string endLocation)
{
	static assert(symbolName == "Value", "Only a Value symbol can take a value.");
	enum accept = ("
		{
			_front = makeToken!"~symbolName.stringof~";
			_front.value = "~value~";
			_front.location = "~(startLocation==""? "tokenStart" : startLocation)~";
			_front.data = source[
				"~(startLocation==""? "tokenStart.index" : startLocation)~"
				..
				"~(endLocation==""? "location.index" : endLocation)~"
			];
			return;
		}
	").replace("\n", "");
}
private template acceptImpl(string symbolName, string value)
{
	enum acceptImpl = ("
		{
			_front = makeToken!"~symbolName.stringof~";
			_front.value = "~value~";
			return;
		}
	").replace("\n", "");
}

class Lexer
{
	string source;
	string filename;
	Location location; /// Location of current character in source

	private dchar  ch;         // Current character
	private dchar  nextCh;     // Lookahead character
	private size_t nextPos;    // Position of lookahead character (an index into source)
	private bool   hasNextCh;  // If false, then there's no more lookahead, just EOF
	private size_t posAfterLookahead; // Position after lookahead character (an index into source)

	private Location tokenStart;    // The starting location of the token being lexed
	
	// Length so far of the token being lexed, not including current char
	private size_t tokenLength;   // Length in UTF-8 code units
	private size_t tokenLength32; // Length in UTF-32 code units
	
	// Slight kludge:
	// If a numeric fragment is found after a Date (separated by arbitrary
	// whitespace), it could be the "hours" part of a DateTime, or it could
	// be a separate numeric literal that simply follows a plain Date. If the
	// latter, then the Date must be emitted, but numeric fragment that was
	// found after it needs to be saved for the the lexer's next iteration.
	// 
	// It's a slight kludge, and could instead be implemented as a slightly
	// kludgey parser hack, but it's the only situation where SDL's lexing
	// needs to lookahead more than one character, so this is good enough.
	private struct LookaheadTokenInfo
	{
		bool     exists          = false;
		string   numericFragment = "";
		bool     isNegative      = false;
		Location tokenStart;
	}
	private LookaheadTokenInfo lookaheadTokenInfo;
	
	this(string source=null, string filename=null)
	{
		this.filename = filename;
		this.source = source;
		
		_front = Token(symbol!"Error", Location());
		lookaheadTokenInfo = LookaheadTokenInfo.init;

		if( source.startsWith( ByteOrderMarks[BOM.UTF8] ) )
		{
			source = source[ ByteOrderMarks[BOM.UTF8].length .. $ ];
			this.source = source;
		}
		
		foreach(bom; ByteOrderMarks)
		if( source.startsWith(bom) )
			error(Location(filename,0,0,0), "SDL spec only supports UTF-8, not UTF-16 or UTF-32");
		
		if(source == "")
			mixin(accept!"EOF");
		
		// Prime everything
		hasNextCh = true;
		nextCh = source.decode(posAfterLookahead);
		advanceChar(ErrorOnEOF.Yes);
		location = Location(filename, 0, 0, 0);
		popFront();
	}
	
	@property bool empty()
	{
		return _front.symbol == symbol!"EOF";
	}
	
	Token _front;
	@property Token front()
	{
		return _front;
	}

	@property bool isEOF()
	{
		return location.index == source.length && !lookaheadTokenInfo.exists;
	}

	private void error(string msg)
	{
		error(location, msg);
	}

	private void error(Location loc, string msg)
	{
		throw new SDLangParseException(loc, "Error: "~msg);
	}

	private Token makeToken(string symbolName)()
	{
		auto tok = Token(symbol!symbolName, tokenStart);
		tok.data = tokenData;
		return tok;
	}
	
	private @property string tokenData()
	{
		return source[ tokenStart.index .. location.index ];
	}
	
	/// Check the lookahead character
	private bool lookahead(dchar ch)
	{
		return hasNextCh && nextCh == ch;
	}

	private bool isNewline(dchar ch)
	{
		return ch == '\n' || ch == '\r' || ch == lineSep || ch == paraSep;
	}

	private bool isAtNewline()
	{
		return
			ch == '\n' || ch == lineSep || ch == paraSep ||
			(ch == '\r' && lookahead('\n'));
	}

	/// Is 'ch' a valid base 64 character?
	private bool isBase64(dchar ch)
	{
		if(ch >= 'A' && ch <= 'Z')
			return true;

		if(ch >= 'a' && ch <= 'z')
			return true;

		if(ch >= '0' && ch <= '9')
			return true;
		
		return ch == '+' || ch == '/' || ch == '=';
	}
	
	/// Is the current character one that's allowed
	/// immediately *after* an int/float literal?
	private bool isEndOfNumber()
	{
		if(isEOF)
			return true;
		
		return !isDigit(ch) && ch != ':' && ch != '_' && !isAlpha(ch);
	}
	
	/// Is current character the last one in an ident?
	private bool isEndOfIdentCached = false;
	private bool _isEndOfIdent;
	private bool isEndOfIdent()
	{
		if(!isEndOfIdentCached)
		{
			if(!hasNextCh)
				_isEndOfIdent = true;
			else
				_isEndOfIdent = !isIdentChar(nextCh);
			
			isEndOfIdentCached = true;
		}
		
		return _isEndOfIdent;
	}

	/// Is 'ch' a character that's allowed *somewhere* in an identifier?
	private bool isIdentChar(dchar ch)
	{
		if(isAlpha(ch))
			return true;
		
		else if(isNumber(ch))
			return true;
		
		else
			return 
				ch == '-' ||
				ch == '_' ||
				ch == '.' ||
				ch == '$';
	}

	private bool isDigit(dchar ch)
	{
		return ch >= '0' && ch <= '9';
	}
	
	private enum KeywordResult
	{
		Accept,   // Keyword is matched
		Continue, // Keyword is not matched *yet*
		Failed,   // Keyword doesn't match
	}
	private KeywordResult checkKeyword(dstring keyword32)
	{
		// Still within length of keyword
		if(tokenLength32 < keyword32.length)
		{
			if(ch == keyword32[tokenLength32])
				return KeywordResult.Continue;
			else
				return KeywordResult.Failed;
		}

		// At position after keyword
		else if(tokenLength32 == keyword32.length)
		{
			if(isEOF || !isIdentChar(ch))
			{
				debug assert(tokenData == to!string(keyword32));
				return KeywordResult.Accept;
			}
			else
				return KeywordResult.Failed;
		}

		assert(0, "Fell off end of keyword to check");
	}

	enum ErrorOnEOF { No, Yes }

	/// Advance one code point.
	/// Returns false if EOF was reached
	private void advanceChar(ErrorOnEOF errorOnEOF)
	{
		if(isAtNewline())
		{
			location.line++;
			location.col = 0;
		}
		else
			location.col++;

		location.index = nextPos;

		nextPos = posAfterLookahead;
		ch      = nextCh;

		if(!hasNextCh)
		{
			if(errorOnEOF == ErrorOnEOF.Yes)
				error("Unexpected end of file");

			return;
		}

		tokenLength32++;
		tokenLength = location.index - tokenStart.index;

		if(nextPos == source.length)
		{
			nextCh = dchar.init;
			hasNextCh = false;
			return;
		}
		
		nextCh = source.decode(posAfterLookahead);
		isEndOfIdentCached = false;
	}

	void popFront()
	{
		// -- Main Lexer -------------

		eatWhite();

		if(isEOF)
			mixin(accept!"EOF");
		
		tokenStart    = location;
		tokenLength   = 0;
		tokenLength32 = 0;
		isEndOfIdentCached = false;
		
		if(lookaheadTokenInfo.exists)
		{
			tokenStart = lookaheadTokenInfo.tokenStart;

			auto prevLATokenInfo = lookaheadTokenInfo;
			lookaheadTokenInfo = LookaheadTokenInfo.init;
			lexNumeric(prevLATokenInfo);
			return;
		}
		
		if(ch == '=')
		{
			advanceChar(ErrorOnEOF.No);
			mixin(accept!"=");
		}
		
		else if(ch == '{')
		{
			advanceChar(ErrorOnEOF.No);
			mixin(accept!"{");
		}
		
		else if(ch == '}')
		{
			advanceChar(ErrorOnEOF.No);
			mixin(accept!"}");
		}
		
		else if(ch == ':')
		{
			advanceChar(ErrorOnEOF.No);
			mixin(accept!":");
		}
		
		else if(ch == ';' || isAtNewline())
		{
			advanceChar(ErrorOnEOF.No);
			mixin(accept!"EOL");
		}
		
		else if(isAlpha(ch) || ch == '_')
			lexIdentKeyword();

		else if(ch == '"')
			lexRegularString();

		else if(ch == '`')
			lexRawString();
		
		else if(ch == '\'')
			lexCharacter();

		else if(ch == '[')
			lexBinary();

		else if(ch == '-' || ch == '.' || isDigit(ch))
			lexNumeric();

		else
		{
			advanceChar(ErrorOnEOF.No);
			error("Syntax error");
		}
	}

	/// Lex Ident or Keyword
	private void lexIdentKeyword()
	{
		assert(isAlpha(ch) || ch == '_');
		
		// Keyword
		struct Key
		{
			dstring name;
			Value value;
			bool failed = false;
		}
		static Key[5] keywords;
		static keywordsInited = false;
		if(!keywordsInited)
		{
			// Value (as a std.variant-based type) can't be statically inited
			keywords[0] = Key("true",  Value(true ));
			keywords[1] = Key("false", Value(false));
			keywords[2] = Key("on",    Value(true ));
			keywords[3] = Key("off",   Value(false));
			keywords[4] = Key("null",  Value(null ));
			keywordsInited = true;
		}
		
		foreach(ref key; keywords)
			key.failed = false;
		
		auto numKeys = keywords.length;

		do
		{
			foreach(ref key; keywords)
			if(!key.failed)
			{
				final switch(checkKeyword(key.name))
				{
				case KeywordResult.Accept:
					mixin(accept!("Value", "key.value"));
				
				case KeywordResult.Continue:
					break;
				
				case KeywordResult.Failed:
					key.failed = true;
					numKeys--;
					break;
				}
			}

			if(numKeys == 0)
			{
				lexIdent();
				return;
			}

			advanceChar(ErrorOnEOF.No);

		} while(!isEOF);

		foreach(ref key; keywords)
		if(!key.failed)
		if(key.name.length == tokenLength32+1)
			mixin(accept!("Value", "key.value"));

		mixin(accept!"Ident");
	}

	/// Lex Ident
	private void lexIdent()
	{
		if(tokenLength == 0)
			assert(isAlpha(ch) || ch == '_');
		
		while(!isEOF && isIdentChar(ch))
			advanceChar(ErrorOnEOF.No);

		mixin(accept!"Ident");
	}
	
	/// Lex regular string
	private void lexRegularString()
	{
		assert(ch == '"');

		Appender!string buf;
		size_t spanStart = nextPos;
		
		// Doesn't include current character
		void updateBuf()
		{
			if(location.index == spanStart)
				return;

			buf.put( source[spanStart..location.index] );
		}
		
		do
		{
			advanceChar(ErrorOnEOF.Yes);

			if(ch == '\\')
			{
				updateBuf();

				bool wasEscSequence = true;
				if(hasNextCh)
				{
					switch(nextCh)
					{
					case 'n':  buf.put('\n'); break;
					case 'r':  buf.put('\r'); break;
					case 't':  buf.put('\t'); break;
					case '"':  buf.put('\"'); break;
					case '\\': buf.put('\\'); break;
					default: wasEscSequence = false; break;
					}
				}
				
				if(wasEscSequence)
				{
					advanceChar(ErrorOnEOF.Yes);
					advanceChar(ErrorOnEOF.Yes);
				}
				else
					eatWhite(false);

				spanStart = location.index;
			}

			else if(isNewline(ch))
				error("Unescaped newlines are only allowed in raw strings, not regular strings.");

		} while(ch != '"');
		
		updateBuf();
		advanceChar(ErrorOnEOF.No); // Skip closing double-quote
		mixin(accept!("Value", "buf.data"));
	}

	/// Lex raw string
	private void lexRawString()
	{
		assert(ch == '`');
		
		do
			advanceChar(ErrorOnEOF.Yes);
		while(ch != '`');
		
		advanceChar(ErrorOnEOF.No); // Skip closing back-tick
		mixin(accept!("Value", "tokenData[1..$-1]"));
	}
	
	/// Lex character literal
	private void lexCharacter()
	{
		assert(ch == '\'');
		advanceChar(ErrorOnEOF.Yes); // Skip opening single-quote
		
		dchar value;
		if(ch == '\\')
		{
			advanceChar(ErrorOnEOF.Yes); // Skip escape backslash
			switch(ch)
			{
			case 'n':  value = '\n'; break;
			case 'r':  value = '\r'; break;
			case 't':  value = '\t'; break;
			case '\'': value = '\''; break;
			case '\\': value = '\\'; break;
			default: error("Invalid escape sequence.");
			}
		}
		else if(isNewline(ch))
			error("Newline not alowed in character literal.");
		else
			value = ch;
		advanceChar(ErrorOnEOF.Yes); // Skip the character itself

		if(ch == '\'')
			advanceChar(ErrorOnEOF.No); // Skip closing single-quote
		else
			error("Expected closing single-quote.");

		mixin(accept!("Value", "value"));
	}
	
	/// Lex base64 binary literal
	private void lexBinary()
	{
		assert(ch == '[');
		advanceChar(ErrorOnEOF.Yes);
		
		void eatBase64Whitespace()
		{
			while(!isEOF && isWhite(ch))
			{
				if(isNewline(ch))
					advanceChar(ErrorOnEOF.Yes);
				
				if(!isEOF && isWhite(ch))
					eatWhite();
			}
		}
		
		eatBase64Whitespace();

		// Iterates all valid base64 characters, ending at ']'.
		// Skips all whitespace. Throws on invalid chars.
		struct Base64InputRange
		{
			Lexer *lexer;
			private bool isInited = false;
			private int numInputCharsMod4 = 0;
			
			@property bool empty()
			{
				if(lexer.ch == ']')
				{
					if(numInputCharsMod4 != 0)
						lexer.error("Length of Base64 encoding must be a multiple of 4. ("~to!string(numInputCharsMod4)~")");
					
					return true;
				}
				
				return false;
			}

			@property dchar front()
			{
				return lexer.ch;
			}
			
			void popFront()
			{
				auto lex = lexer;

				if(!isInited)
				{
					if(lexer.isBase64(lexer.ch))
					{
						numInputCharsMod4++;
						numInputCharsMod4 %= 4;
					}
					
					isInited = true;
				}
				
				lex.advanceChar(lex.ErrorOnEOF.Yes);

				eatBase64Whitespace();
				
				if(lex.isEOF)
					lex.error("Unexpected end of file.");

				if(lex.ch != ']')
				{
					if(!lex.isBase64(lex.ch))
						lex.error("Invalid character in base64 binary literal.");
					
					numInputCharsMod4++;
					numInputCharsMod4 %= 4;
				}
			}
		}
		
		// This is a slow ugly hack. It's necessary because Base64.decode
		// currently requires the source to have known length.
		//TODO: Remove this when DMD issue #9543 is fixed.
		dchar[] tmpBuf = array(Base64InputRange(&this));

		Appender!(ubyte[]) outputBuf;
		// Ugly workaround for DMD issue #9102
		//TODO: Remove this when DMD #9102 is fixed
		struct OutputBuf
		{
			void put(ubyte ch)
			{
				outputBuf.put(ch);
			}
		}
		
		try
			//Base64.decode(Base64InputRange(&this), OutputBuf());
			Base64.decode(tmpBuf, OutputBuf());

		//TODO: Starting with dmd 2.062, this should be a Base64Exception
		catch(Exception e)
			error("Invalid character in base64 binary literal.");
		
		advanceChar(ErrorOnEOF.No); // Skip ']'
		mixin(accept!("Value", "outputBuf.data"));
	}
	
	private BigInt toBigInt(bool isNegative, string absValue)
	{
		auto num = BigInt(absValue);
		assert(num >= 0);

		if(isNegative)
			num = -num;

		return num;
	}

	/// Lex [0-9]+, but without emitting a token.
	/// This is used by the other numeric parsing functions.
	private string lexNumericFragment()
	{
		if(!isDigit(ch))
			error("Expected a digit 0-9.");
		
		auto spanStart = location.index;
		
		do
		{
			advanceChar(ErrorOnEOF.No);
		} while(!isEOF && isDigit(ch));
		
		return source[spanStart..location.index];
	}

	/// Lex anything that starts with 0-9 or '-'. Ints, floats, dates, etc.
	private void lexNumeric(LookaheadTokenInfo laTokenInfo = LookaheadTokenInfo.init)
	{
		bool isNegative;
		string firstFragment;
		if(laTokenInfo.exists)
		{
			firstFragment = laTokenInfo.numericFragment;
			isNegative    = laTokenInfo.isNegative;
		}
		else
		{
			assert(ch == '-' || ch == '.' || isDigit(ch));

			// Check for negative
			isNegative = ch == '-';
			if(isNegative)
				advanceChar(ErrorOnEOF.Yes);

			// Some floating point with omitted leading zero?
			if(ch == '.')
			{
				lexFloatingPoint("");
				return;
			}

			firstFragment = lexNumericFragment();
		}

		// Long integer (64-bit signed)?
		if(ch == 'L' || ch == 'l')
		{
			advanceChar(ErrorOnEOF.No);

			// BigInt(long.min) is a workaround for DMD issue #9548
			auto num = toBigInt(isNegative, firstFragment);
			if(num < BigInt(long.min) || num > long.max)
				error(tokenStart, "Value doesn't fit in 64-bit signed long integer: "~to!string(num));

			mixin(accept!("Value", "num.toLong()"));
		}
		
		// Float (32-bit signed)?
		else if(ch == 'F' || ch == 'f')
		{
			auto value = to!float(tokenData);
			advanceChar(ErrorOnEOF.No);
			mixin(accept!("Value", "value"));
		}
		
		// Double float (64-bit signed) with suffix?
		else if((ch == 'D' || ch == 'd') && !lookahead(':')
		)
		{
			auto value = to!double(tokenData);
			advanceChar(ErrorOnEOF.No);
			mixin(accept!("Value", "value"));
		}
		
		// Decimal (128+ bits signed)?
		else if(
			(ch == 'B' || ch == 'b') &&
			(lookahead('D') || lookahead('d'))
		)
		{
			auto value = to!real(tokenData);
			advanceChar(ErrorOnEOF.No);
			advanceChar(ErrorOnEOF.No);
			mixin(accept!("Value", "value"));
		}
		
		// Some floating point?
		else if(ch == '.')
			lexFloatingPoint(firstFragment);
		
		// Some date?
		else if(ch == '/' && hasNextCh && isDigit(nextCh))
			lexDate(isNegative, firstFragment);
		
		// Some time span?
		else if(ch == ':' || ch == 'd')
			lexTimeSpan(isNegative, firstFragment);

		// Integer (32-bit signed)?
		else if(isEndOfNumber())
		{
			auto num = toBigInt(isNegative, firstFragment);
			if(num < int.min || num > int.max)
				error(tokenStart, "Value doesn't fit in 32-bit signed integer: "~to!string(num));

			mixin(accept!("Value", "num.toInt()"));
		}

		// Invalid suffix
		else
			error("Invalid integer suffix.");
	}
	
	/// Lex any floating-point literal (after the initial numeric fragment was lexed)
	private void lexFloatingPoint(string firstPart)
	{
		assert(ch == '.');
		advanceChar(ErrorOnEOF.No);
		
		auto secondPart = lexNumericFragment();
		
		try
		{
			// Double float (64-bit signed) with suffix?
			if(ch == 'D' || ch == 'd')
			{
				auto value = to!double(tokenData);
				advanceChar(ErrorOnEOF.No);
				mixin(accept!("Value", "value"));
			}

			// Float (32-bit signed)?
			else if(ch == 'F' || ch == 'f')
			{
				auto value = to!float(tokenData);
				advanceChar(ErrorOnEOF.No);
				mixin(accept!("Value", "value"));
			}

			// Decimal (128+ bits signed)?
			else if(ch == 'B' || ch == 'b')
			{
				auto value = to!real(tokenData);
				advanceChar(ErrorOnEOF.Yes);

				if(!isEOF && (ch == 'D' || ch == 'd'))
				{
					advanceChar(ErrorOnEOF.No);
					if(isEndOfNumber())
						mixin(accept!("Value", "value"));
				}

				error("Invalid floating point suffix.");
			}

			// Double float (64-bit signed) without suffix?
			else if(isEOF || !isIdentChar(ch))
			{
				auto value = to!double(tokenData);
				mixin(accept!("Value", "value"));
			}

			// Invalid suffix
			else
				error("Invalid floating point suffix.");
		}
		catch(ConvException e)
			error("Invalid floating point literal.");
	}

	private Date makeDate(bool isNegative, string yearStr, string monthStr, string dayStr)
	{
		BigInt biTmp;
		
		biTmp = BigInt(yearStr);
		if(isNegative)
			biTmp = -biTmp;
		if(biTmp < int.min || biTmp > int.max)
			error(tokenStart, "Date's year is out of range. (Must fit within a 32-bit signed int.)");
		auto year = biTmp.toInt();

		biTmp = BigInt(monthStr);
		if(biTmp < 1 || biTmp > 12)
			error(tokenStart, "Date's month is out of range.");
		auto month = biTmp.toInt();
		
		biTmp = BigInt(dayStr);
		if(biTmp < 1 || biTmp > 31)
			error(tokenStart, "Date's month is out of range.");
		auto day = biTmp.toInt();
		
		return Date(year, month, day);
	}
	
	private DateTimeFrac makeDateTimeFrac(
		bool isNegative, Date date, string hourStr, string minuteStr,
		string secondStr, string millisecondStr
	)
	{
		BigInt biTmp;

		biTmp = BigInt(hourStr);
		if(biTmp < int.min || biTmp > int.max)
			error(tokenStart, "Datetime's hour is out of range.");
		auto numHours = biTmp.toInt();
		
		biTmp = BigInt(minuteStr);
		if(biTmp < 0 || biTmp > int.max)
			error(tokenStart, "Datetime's minute is out of range.");
		auto numMinutes = biTmp.toInt();
		
		int numSeconds = 0;
		if(secondStr != "")
		{
			biTmp = BigInt(secondStr);
			if(biTmp < 0 || biTmp > int.max)
				error(tokenStart, "Datetime's second is out of range.");
			numSeconds = biTmp.toInt();
		}
		
		int millisecond = 0;
		if(millisecondStr != "")
		{
			biTmp = BigInt(millisecondStr);
			if(biTmp < 0 || biTmp > int.max)
				error(tokenStart, "Datetime's millisecond is out of range.");
			millisecond = biTmp.toInt();

			if(millisecondStr.length == 1)
				millisecond *= 100;
			else if(millisecondStr.length == 2)
				millisecond *= 10;
		}

		FracSec fracSecs;
		fracSecs.msecs = millisecond;
		
		auto offset = hours(numHours) + minutes(numMinutes) + seconds(numSeconds);

		if(isNegative)
		{
			offset   = -offset;
			fracSecs = -fracSecs;
		}
		
		return DateTimeFrac(DateTime(date) + offset, fracSecs);
	}

	private Duration makeDuration(
		bool isNegative, string dayStr,
		string hourStr, string minuteStr, string secondStr,
		string millisecondStr
	)
	{
		BigInt biTmp;

		long day = 0;
		if(dayStr != "")
		{
			biTmp = BigInt(dayStr);
			if(biTmp < long.min || biTmp > long.max)
				error(tokenStart, "Time span's day is out of range.");
			day = biTmp.toLong();
		}

		biTmp = BigInt(hourStr);
		if(biTmp < long.min || biTmp > long.max)
			error(tokenStart, "Time span's hour is out of range.");
		auto hour = biTmp.toLong();

		biTmp = BigInt(minuteStr);
		if(biTmp < long.min || biTmp > long.max)
			error(tokenStart, "Time span's minute is out of range.");
		auto minute = biTmp.toLong();

		biTmp = BigInt(secondStr);
		if(biTmp < long.min || biTmp > long.max)
			error(tokenStart, "Time span's second is out of range.");
		auto second = biTmp.toLong();

		long millisecond = 0;
		if(millisecondStr != "")
		{
			biTmp = BigInt(millisecondStr);
			if(biTmp < long.min || biTmp > long.max)
				error(tokenStart, "Time span's millisecond is out of range.");
			millisecond = biTmp.toLong();

			if(millisecondStr.length == 1)
				millisecond *= 100;
			else if(millisecondStr.length == 2)
				millisecond *= 10;
		}
		
		auto duration =
			dur!"days"   (day)    +
			dur!"hours"  (hour)   +
			dur!"minutes"(minute) +
			dur!"seconds"(second) +
			dur!"msecs"  (millisecond);

		if(isNegative)
			duration = -duration;
		
		return duration;
	}

	// This has to reproduce some weird corner case behaviors from the
	// original Java version of SDL. So some of this may seem weird.
	private Nullable!Duration getTimeZoneOffset(string str)
	{
		if(str.length < 2)
			return Nullable!Duration(); // Unknown timezone
		
		if(str[0] != '+' && str[0] != '-')
			return Nullable!Duration(); // Unknown timezone

		auto isNegative = str[0] == '-';

		string numHoursStr;
		string numMinutesStr;
		if(str[1] == ':')
		{
			numMinutesStr = str[1..$];
			numHoursStr = "";
		}
		else
		{
			numMinutesStr = str.find(':');
			numHoursStr = str[1 .. $-numMinutesStr.length];
		}
		
		long numHours = 0;
		long numMinutes = 0;
		bool isUnknown = false;
		try
		{
			switch(numHoursStr.length)
			{
			case 0:
				if(numMinutesStr.length == 3)
				{
					numHours   = 0;
					numMinutes = to!long(numMinutesStr[1..$]);
				}
				else
					isUnknown = true;
				break;

			case 1:
			case 2:
				if(numMinutesStr.length == 0)
				{
					numHours   = to!long(numHoursStr);
					numMinutes = 0;
				}
				else if(numMinutesStr.length == 3)
				{
					numHours   = to!long(numHoursStr);
					numMinutes = to!long(numMinutesStr[1..$]);
				}
				else
					isUnknown = true;
				break;

			default:
				if(numMinutesStr.length == 0)
				{
					// Yes, this is correct
					numHours   = 0;
					numMinutes = to!long(numHoursStr[1..$]);
				}
				else
					isUnknown = true;
				break;
			}
		}
		catch(ConvException e)
			isUnknown = true;
		
		if(isUnknown)
			return Nullable!Duration(); // Unknown timezone

		auto timeZoneOffset = hours(numHours) + minutes(numMinutes);
		if(isNegative)
			timeZoneOffset = -timeZoneOffset;

		// Timezone valid
		return Nullable!Duration(timeZoneOffset);
	}
	
	/// Lex date or datetime (after the initial numeric fragment was lexed)
	private void lexDate(bool isDateNegative, string yearStr)
	{
		assert(ch == '/');
		
		// Lex months
		advanceChar(ErrorOnEOF.Yes); // Skip '/'
		auto monthStr = lexNumericFragment();

		// Lex days
		if(ch != '/')
			error("Invalid date format: Missing days.");
		advanceChar(ErrorOnEOF.Yes); // Skip '/'
		auto dayStr = lexNumericFragment();
		
		auto date = makeDate(isDateNegative, yearStr, monthStr, dayStr);

		if(!isEndOfNumber() && ch != '/')
			error("Dates cannot have suffixes.");
		
		// Date?
		if(isEOF)
			mixin(accept!("Value", "date"));
		
		auto endOfDate = location;
		
		while(
			!isEOF &&
			( ch == '\\' || ch == '/' || (isWhite(ch) && !isNewline(ch)) )
		)
		{
			if(ch == '\\' && hasNextCh && isNewline(nextCh))
			{
				advanceChar(ErrorOnEOF.Yes);
				if(isAtNewline())
					advanceChar(ErrorOnEOF.Yes);
				advanceChar(ErrorOnEOF.No);
			}

			eatWhite();
		}

		// Date?
		if(isEOF || (!isDigit(ch) && ch != '-'))
			mixin(accept!("Value", "date", "", "endOfDate.index"));
		
		auto startOfTime = location;

		// Is time negative?
		bool isTimeNegative = ch == '-';
		if(isTimeNegative)
			advanceChar(ErrorOnEOF.Yes);

		// Lex hours
		auto hourStr = ch == '.'? "" : lexNumericFragment();
		
		// Lex minutes
		if(ch != ':')
		{
			// No minutes found. Therefore we had a plain Date followed
			// by a numeric literal, not a DateTime.
			lookaheadTokenInfo.exists          = true;
			lookaheadTokenInfo.numericFragment = hourStr;
			lookaheadTokenInfo.isNegative      = isTimeNegative;
			lookaheadTokenInfo.tokenStart      = startOfTime;
			mixin(accept!("Value", "date", "", "endOfDate.index"));
		}
		advanceChar(ErrorOnEOF.Yes); // Skip ':'
		auto minuteStr = lexNumericFragment();
		
		// Lex seconds, if exists
		string secondStr;
		if(ch == ':')
		{
			advanceChar(ErrorOnEOF.Yes); // Skip ':'
			secondStr = lexNumericFragment();
		}
		
		// Lex milliseconds, if exists
		string millisecondStr;
		if(ch == '.')
		{
			advanceChar(ErrorOnEOF.Yes); // Skip '.'
			millisecondStr = lexNumericFragment();
		}

		auto dateTimeFrac = makeDateTimeFrac(isTimeNegative, date, hourStr, minuteStr, secondStr, millisecondStr);
		
		// Lex zone, if exists
		if(ch == '-')
		{
			advanceChar(ErrorOnEOF.Yes); // Skip '-'
			auto timezoneStart = location;
			
			if(!isAlpha(ch))
				error("Invalid timezone format.");
			
			while(!isEOF && !isWhite(ch))
				advanceChar(ErrorOnEOF.No);
			
			auto timezoneStr = source[timezoneStart.index..location.index];
			if(timezoneStr.startsWith("GMT"))
			{
				auto isoPart = timezoneStr["GMT".length..$];
				auto offset = getTimeZoneOffset(isoPart);
				
				if(offset.isNull())
				{
					// Unknown time zone
					mixin(accept!("Value", "DateTimeFracUnknownZone(dateTimeFrac.dateTime, dateTimeFrac.fracSec, timezoneStr)"));
				}
				else
				{
					auto timezone = new immutable SimpleTimeZone(offset.get());
					mixin(accept!("Value", "SysTime(dateTimeFrac.dateTime, dateTimeFrac.fracSec, timezone)"));
				}
			}
			
			try
			{
				auto timezone = TimeZone.getTimeZone(timezoneStr);
				if(timezone)
					mixin(accept!("Value", "SysTime(dateTimeFrac.dateTime, dateTimeFrac.fracSec, timezone)"));
			}
			catch(TimeException e)
			{
				// Time zone not found. So just move along to "Unknown time zone" below.
			}

			// Unknown time zone
			mixin(accept!("Value", "DateTimeFracUnknownZone(dateTimeFrac.dateTime, dateTimeFrac.fracSec, timezoneStr)"));
		}

		if(!isEndOfNumber())
			error("Date-Times cannot have suffixes.");

		mixin(accept!("Value", "dateTimeFrac"));
	}

	/// Lex time span (after the initial numeric fragment was lexed)
	private void lexTimeSpan(bool isNegative, string firstPart)
	{
		assert(ch == ':' || ch == 'd');
		
		string dayStr = "";
		string hourStr;

		// Lexed days?
		bool hasDays = ch == 'd';
		if(hasDays)
		{
			dayStr = firstPart;
			advanceChar(ErrorOnEOF.Yes); // Skip 'd'

			// Lex hours
			if(ch != ':')
				error("Invalid time span format: Missing hours.");
			advanceChar(ErrorOnEOF.Yes); // Skip ':'
			hourStr = lexNumericFragment();
		}
		else
			hourStr = firstPart;

		// Lex minutes
		if(ch != ':')
			error("Invalid time span format: Missing minutes.");
		advanceChar(ErrorOnEOF.Yes); // Skip ':'
		auto minuteStr = lexNumericFragment();

		// Lex seconds
		if(ch != ':')
			error("Invalid time span format: Missing seconds.");
		advanceChar(ErrorOnEOF.Yes); // Skip ':'
		auto secondStr = lexNumericFragment();
		
		// Lex milliseconds, if exists
		string millisecondStr = "";
		if(ch == '.')
		{
			advanceChar(ErrorOnEOF.Yes); // Skip '.'
			millisecondStr = lexNumericFragment();
		}

		if(!isEndOfNumber())
			error("Time spans cannot have suffixes.");
		
		auto duration = makeDuration(isNegative, dayStr, hourStr, minuteStr, secondStr, millisecondStr);
		mixin(accept!("Value", "duration"));
	}

	/// Advances past whitespace and comments
	private void eatWhite(bool allowComments=true)
	{
		// -- Comment/Whitepace Lexer -------------

		enum State
		{
			normal,
			lineComment,  // Got "#" or "//" or "--", Eating everything until newline
			blockComment, // Got "/*", Eating everything until "*/"
		}

		if(isEOF)
			return;
		
		Location commentStart;
		State state = State.normal;
		bool consumeNewlines = false;
		bool hasConsumedNewline = false;
		while(true)
		{
			final switch(state)
			{
			case State.normal:

				if(ch == '\\')
				{
					commentStart = location;
					consumeNewlines = true;
					hasConsumedNewline = false;
				}

				else if(ch == '#')
				{
					if(!allowComments)
						return;

					commentStart = location;
					state = State.lineComment;
				}

				else if(ch == '/' || ch == '-')
				{
					commentStart = location;
					if(lookahead(ch))
					{
						if(!allowComments)
							return;

						advanceChar(ErrorOnEOF.No);
						state = State.lineComment;
					}
					else if(ch == '/' && lookahead('*'))
					{
						if(!allowComments)
							return;

						advanceChar(ErrorOnEOF.No);
						state = State.blockComment;
					}
					else
						return; // Done
				}
				else if(isAtNewline())
				{
					if(consumeNewlines)
						hasConsumedNewline = true;
					else
						return; // Done
				}
				else if(!isWhite(ch))
				{
					if(consumeNewlines)
					{
						if(hasConsumedNewline)
							return; // Done
						else
							error("Only whitespace can come between a line-continuation backslash and the following newline.");
					}
					else
						return; // Done
				}

				break;
			
			case State.lineComment:
				if(!hasNextCh || isNewline(nextCh))
					state = State.normal;
				break;
			
			case State.blockComment:
				if(ch == '*' && lookahead('/'))
				{
					advanceChar(ErrorOnEOF.No);
					state = State.normal;
				}
				break;
			}
			
			advanceChar(ErrorOnEOF.No);
			if(isEOF)
			{
				// Reached EOF

				if(consumeNewlines && !hasConsumedNewline)
					error("Missing newline after line-continuation backslash.");

				else if(state == State.blockComment)
					error(commentStart, "Unterminated block comment.");

				else
					return; // Done, reached EOF
			}
		}
	}
}

version(SDLang_Unittest)
unittest
{
	import std.stdio;
	writeln("Unittesting sdlang lexer...");
	stdout.flush();
	
	auto loc  = Location("filename", 0, 0, 0);
	auto loc2 = Location("a", 1, 1, 1);
	assert([Token(symbol!"EOL",loc)             ] == [Token(symbol!"EOL",loc)              ] );
	assert([Token(symbol!"EOL",loc,Value(7),"A")] == [Token(symbol!"EOL",loc2,Value(7),"B")] );

	int numErrors = 0;
	void testLex(string file=__FILE__, size_t line=__LINE__)(string source, Token[] expected)
	{
		Token[] actual;
		try
			actual = lexSource(source, "filename");
		catch(SDLangParseException e)
		{
			numErrors++;
			stderr.writeln(file, "(", line, "): testLex failed on: ", source);
			stderr.writeln("    Expected:");
			stderr.writeln("        ", expected);
			stderr.writeln("    Actual: SDLangParseException thrown:");
			stderr.writeln("        ", e.msg);
			return;
		}
		
		if(actual != expected)
		{
			numErrors++;
			stderr.writeln(file, "(", line, "): testLex failed on: ", source);
			stderr.writeln("    Expected:");
			stderr.writeln("        ", expected);
			stderr.writeln("    Actual:");
			stderr.writeln("        ", actual);

			if(expected.length > 1 || actual.length > 1)
			{
				stderr.writeln("    expected.length: ", expected.length);
				stderr.writeln("    actual.length:   ", actual.length);

				if(actual.length == expected.length)
				foreach(i; 0..actual.length)
				if(actual[i] != expected[i])
				{
					stderr.writeln("    Unequal at index #", i, ":");
					stderr.writeln("        Expected:");
					stderr.writeln("            ", expected[i]);
					stderr.writeln("        Actual:");
					stderr.writeln("            ", actual[i]);
				}
			}
		}
	}

	void testLexThrows(string file=__FILE__, size_t line=__LINE__)(string source)
	{
		bool hadException = false;
		Token[] actual;
		try
			actual = lexSource(source, "filename");
		catch(SDLangParseException e)
			hadException = true;

		if(!hadException)
		{
			numErrors++;
			stderr.writeln(file, "(", line, "): testLex failed on: ", source);
			stderr.writeln("    Expected SDLangParseException");
			stderr.writeln("    Actual:");
			stderr.writeln("        ", actual);
		}
	}

	testLex("",        []);
	testLex(" ",       []);
	testLex("\\\n",    []);
	testLex("/*foo*/", []);
	testLex("/* multiline \n comment */", []);
	testLex("/* * */", []);
	testLexThrows("/* ");

	testLex(":",  [ Token(symbol!":",  loc) ]);
	testLex("=",  [ Token(symbol!"=",  loc) ]);
	testLex("{",  [ Token(symbol!"{",  loc) ]);
	testLex("}",  [ Token(symbol!"}",  loc) ]);
	testLex(";",  [ Token(symbol!"EOL",loc) ]);
	testLex("\n", [ Token(symbol!"EOL",loc) ]);

	testLex("foo",     [ Token(symbol!"Ident",loc,Value(null),"foo")     ]);
	testLex("_foo",    [ Token(symbol!"Ident",loc,Value(null),"_foo")    ]);
	testLex("foo.bar", [ Token(symbol!"Ident",loc,Value(null),"foo.bar") ]);
	testLex("foo-bar", [ Token(symbol!"Ident",loc,Value(null),"foo-bar") ]);
	testLex("foo.",    [ Token(symbol!"Ident",loc,Value(null),"foo.")    ]);
	testLex("foo-",    [ Token(symbol!"Ident",loc,Value(null),"foo-")    ]);
	testLexThrows(".foo");

	testLex("foo bar", [
		Token(symbol!"Ident",loc,Value(null),"foo"),
		Token(symbol!"Ident",loc,Value(null),"bar"),
	]);
	testLex("foo \\  \n  \n  bar", [
		Token(symbol!"Ident",loc,Value(null),"foo"),
		Token(symbol!"Ident",loc,Value(null),"bar"),
	]);
	testLex("foo \\  \n \\ \n  bar", [
		Token(symbol!"Ident",loc,Value(null),"foo"),
		Token(symbol!"Ident",loc,Value(null),"bar"),
	]);
	testLexThrows("foo \\ ");
	testLexThrows("foo \\ bar");
	testLexThrows("foo \\  \n  \\ ");
	testLexThrows("foo \\  \n  \\ bar");

	testLex("foo : = { } ; \n bar \n", [
		Token(symbol!"Ident",loc,Value(null),"foo"),
		Token(symbol!":",loc),
		Token(symbol!"=",loc),
		Token(symbol!"{",loc),
		Token(symbol!"}",loc),
		Token(symbol!"EOL",loc),
		Token(symbol!"EOL",loc),
		Token(symbol!"Ident",loc,Value(null),"bar"),
		Token(symbol!"EOL",loc),
	]);

	testLexThrows("<");
	testLexThrows("*");
	testLexThrows(`\`);
	
	// Integers
	testLex(  "7", [ Token(symbol!"Value",loc,Value(cast( int) 7)) ]);
	testLex( "-7", [ Token(symbol!"Value",loc,Value(cast( int)-7)) ]);
	testLex( "7L", [ Token(symbol!"Value",loc,Value(cast(long) 7)) ]);
	testLex( "7l", [ Token(symbol!"Value",loc,Value(cast(long) 7)) ]);
	testLex("-7L", [ Token(symbol!"Value",loc,Value(cast(long)-7)) ]);
	testLex(  "0", [ Token(symbol!"Value",loc,Value(cast( int) 0)) ]);
	testLex( "-0", [ Token(symbol!"Value",loc,Value(cast( int) 0)) ]);

	testLex("7/**/", [ Token(symbol!"Value",loc,Value(cast( int) 7)) ]);
	testLex("7#",    [ Token(symbol!"Value",loc,Value(cast( int) 7)) ]);

	testLex("7 A", [
		Token(symbol!"Value",loc,Value(cast(int)7)),
		Token(symbol!"Ident",loc,Value(      null),"A"),
	]);
	testLexThrows("7A");
	testLexThrows("-A");
	testLexThrows(`-""`);
	
	testLex("7;", [
		Token(symbol!"Value",loc,Value(cast(int)7)),
		Token(symbol!"EOL",loc),
	]);
	
	// Floats
	testLex("1.2F" , [ Token(symbol!"Value",loc,Value(cast( float)1.2)) ]);
	testLex("1.2f" , [ Token(symbol!"Value",loc,Value(cast( float)1.2)) ]);
	testLex("1.2"  , [ Token(symbol!"Value",loc,Value(cast(double)1.2)) ]);
	testLex("1.2D" , [ Token(symbol!"Value",loc,Value(cast(double)1.2)) ]);
	testLex("1.2d" , [ Token(symbol!"Value",loc,Value(cast(double)1.2)) ]);
	testLex("1.2BD", [ Token(symbol!"Value",loc,Value(cast(  real)1.2)) ]);
	testLex("1.2bd", [ Token(symbol!"Value",loc,Value(cast(  real)1.2)) ]);
	testLex("1.2Bd", [ Token(symbol!"Value",loc,Value(cast(  real)1.2)) ]);
	testLex("1.2bD", [ Token(symbol!"Value",loc,Value(cast(  real)1.2)) ]);

	testLex(".2F" , [ Token(symbol!"Value",loc,Value(cast( float)0.2)) ]);
	testLex(".2"  , [ Token(symbol!"Value",loc,Value(cast(double)0.2)) ]);
	testLex(".2D" , [ Token(symbol!"Value",loc,Value(cast(double)0.2)) ]);
	testLex(".2BD", [ Token(symbol!"Value",loc,Value(cast(  real)0.2)) ]);

	testLex("-1.2F" , [ Token(symbol!"Value",loc,Value(cast( float)-1.2)) ]);
	testLex("-1.2"  , [ Token(symbol!"Value",loc,Value(cast(double)-1.2)) ]);
	testLex("-1.2D" , [ Token(symbol!"Value",loc,Value(cast(double)-1.2)) ]);
	testLex("-1.2BD", [ Token(symbol!"Value",loc,Value(cast(  real)-1.2)) ]);

	testLex("-.2F" , [ Token(symbol!"Value",loc,Value(cast( float)-0.2)) ]);
	testLex("-.2"  , [ Token(symbol!"Value",loc,Value(cast(double)-0.2)) ]);
	testLex("-.2D" , [ Token(symbol!"Value",loc,Value(cast(double)-0.2)) ]);
	testLex("-.2BD", [ Token(symbol!"Value",loc,Value(cast(  real)-0.2)) ]);

	testLex( "0.0"  , [ Token(symbol!"Value",loc,Value(cast(double)0.0)) ]);
	testLex( "0.0F" , [ Token(symbol!"Value",loc,Value(cast( float)0.0)) ]);
	testLex( "0.0BD", [ Token(symbol!"Value",loc,Value(cast(  real)0.0)) ]);
	testLex("-0.0"  , [ Token(symbol!"Value",loc,Value(cast(double)0.0)) ]);
	testLex("-0.0F" , [ Token(symbol!"Value",loc,Value(cast( float)0.0)) ]);
	testLex("-0.0BD", [ Token(symbol!"Value",loc,Value(cast(  real)0.0)) ]);
	testLex( "7F"   , [ Token(symbol!"Value",loc,Value(cast( float)7.0)) ]);
	testLex( "7D"   , [ Token(symbol!"Value",loc,Value(cast(double)7.0)) ]);
	testLex( "7BD"  , [ Token(symbol!"Value",loc,Value(cast(  real)7.0)) ]);
	testLex( "0F"   , [ Token(symbol!"Value",loc,Value(cast( float)0.0)) ]);
	testLex( "0D"   , [ Token(symbol!"Value",loc,Value(cast(double)0.0)) ]);
	testLex( "0BD"  , [ Token(symbol!"Value",loc,Value(cast(  real)0.0)) ]);
	testLex("-0F"   , [ Token(symbol!"Value",loc,Value(cast( float)0.0)) ]);
	testLex("-0D"   , [ Token(symbol!"Value",loc,Value(cast(double)0.0)) ]);
	testLex("-0BD"  , [ Token(symbol!"Value",loc,Value(cast(  real)0.0)) ]);

	testLex("1.2 F", [
		Token(symbol!"Value",loc,Value(cast(double)1.2)),
		Token(symbol!"Ident",loc,Value(           null),"F"),
	]);
	testLexThrows("1.2A");
	testLexThrows("1.2B");
	testLexThrows("1.2BDF");

	testLex("1.2;", [
		Token(symbol!"Value",loc,Value(cast(double)1.2)),
		Token(symbol!"EOL",loc),
	]);

	testLex("1.2F;", [
		Token(symbol!"Value",loc,Value(cast(float)1.2)),
		Token(symbol!"EOL",loc),
	]);

	testLex("1.2BD;", [
		Token(symbol!"Value",loc,Value(cast(real)1.2)),
		Token(symbol!"EOL",loc),
	]);

	// Booleans and null
	testLex("true",   [ Token(symbol!"Value",loc,Value( true)) ]);
	testLex("false",  [ Token(symbol!"Value",loc,Value(false)) ]);
	testLex("on",     [ Token(symbol!"Value",loc,Value( true)) ]);
	testLex("off",    [ Token(symbol!"Value",loc,Value(false)) ]);
	testLex("null",   [ Token(symbol!"Value",loc,Value( null)) ]);

	testLex("TRUE",   [ Token(symbol!"Ident",loc,Value(null),"TRUE")  ]);
	testLex("true ",  [ Token(symbol!"Value",loc,Value(true)) ]);
	testLex("true  ", [ Token(symbol!"Value",loc,Value(true)) ]);
	testLex("tru",    [ Token(symbol!"Ident",loc,Value(null),"tru")   ]);
	testLex("truX",   [ Token(symbol!"Ident",loc,Value(null),"truX")  ]);
	testLex("trueX",  [ Token(symbol!"Ident",loc,Value(null),"trueX") ]);

	// Raw Backtick Strings
	testLex("`hello world`",      [ Token(symbol!"Value",loc,Value(`hello world`   )) ]);
	testLex("` hello world `",    [ Token(symbol!"Value",loc,Value(` hello world ` )) ]);
	testLex("`hello \\t world`",  [ Token(symbol!"Value",loc,Value(`hello \t world`)) ]);
	testLex("`hello \\n world`",  [ Token(symbol!"Value",loc,Value(`hello \n world`)) ]);
	testLex("`hello \n world`",   [ Token(symbol!"Value",loc,Value("hello \n world")) ]);
	testLex("`hello \r\n world`", [ Token(symbol!"Value",loc,Value("hello \r\n world")) ]);
	testLex("`hello \"world\"`",  [ Token(symbol!"Value",loc,Value(`hello "world"` )) ]);

	testLexThrows("`foo");
	testLexThrows("`");

	// Double-Quote Strings
	testLex(`"hello world"`,            [ Token(symbol!"Value",loc,Value("hello world"   )) ]);
	testLex(`" hello world "`,          [ Token(symbol!"Value",loc,Value(" hello world " )) ]);
	testLex(`"hello \t world"`,         [ Token(symbol!"Value",loc,Value("hello \t world")) ]);
	testLex(`"hello \n world"`,         [ Token(symbol!"Value",loc,Value("hello \n world")) ]);
	testLex("\"hello \\\n world\"",     [ Token(symbol!"Value",loc,Value("hello world" )) ]);
	testLex("\"hello \\  \n world\"",   [ Token(symbol!"Value",loc,Value("hello world" )) ]);
	testLex("\"hello \\  \n\n world\"", [ Token(symbol!"Value",loc,Value("hello world" )) ]);

	testLexThrows("\"hello \n world\"");
	testLexThrows(`"foo`);
	testLexThrows(`"`);

	// Characters
	testLex("'a'",   [ Token(symbol!"Value",loc,Value(cast(dchar) 'a')) ]);
	testLex("'\\n'", [ Token(symbol!"Value",loc,Value(cast(dchar)'\n')) ]);
	testLex("'\\t'", [ Token(symbol!"Value",loc,Value(cast(dchar)'\t')) ]);
	testLex("'\t'",  [ Token(symbol!"Value",loc,Value(cast(dchar)'\t')) ]);
	testLex("'\\''", [ Token(symbol!"Value",loc,Value(cast(dchar)'\'')) ]);
	testLex(`'\\'`,  [ Token(symbol!"Value",loc,Value(cast(dchar)'\\')) ]);

	testLexThrows("'a");
	testLexThrows("'aa'");
	testLexThrows("''");
	testLexThrows("'\\\n'");
	testLexThrows("'\n'");
	testLexThrows(`'\`);
	testLexThrows(`'\'`);
	testLexThrows("'");
	
	// Unicode
	testLex("日本語",         [ Token(symbol!"Ident",loc,Value(null), "日本語") ]);
	testLex("`おはよう、日本。`", [ Token(symbol!"Value",loc,Value(`おはよう、日本。`)) ]);
	testLex(`"おはよう、日本。"`, [ Token(symbol!"Value",loc,Value(`おはよう、日本。`)) ]);
	testLex("'月'",           [ Token(symbol!"Value",loc,Value("月"d.dup[0]))   ]);

	// Base64 Binary
	testLex("[aGVsbG8gd29ybGQ=]",              [ Token(symbol!"Value",loc,Value(cast(ubyte[])"hello world".dup))]);
	testLex("[ aGVsbG8gd29ybGQ= ]",            [ Token(symbol!"Value",loc,Value(cast(ubyte[])"hello world".dup))]);
	testLex("[\n aGVsbG8g \n \n d29ybGQ= \n]", [ Token(symbol!"Value",loc,Value(cast(ubyte[])"hello world".dup))]);

	testLexThrows("[aGVsbG8gd29ybGQ]"); // Ie: Not multiple of 4
	testLexThrows("[ aGVsbG8gd29ybGQ ]");

	// Date
	testLex( "1999/12/5", [ Token(symbol!"Value",loc,Value(Date( 1999, 12, 5))) ]);
	testLex( "2013/2/22", [ Token(symbol!"Value",loc,Value(Date( 2013, 2, 22))) ]);
	testLex("-2013/2/22", [ Token(symbol!"Value",loc,Value(Date(-2013, 2, 22))) ]);

	testLexThrows("7/");
	testLexThrows("2013/2/22a");
	testLexThrows("2013/2/22f");

	testLex("1999/12/5\n", [
		Token(symbol!"Value",loc,Value(Date(1999, 12, 5))),
		Token(symbol!"EOL",loc),
	]);

	// DateTime, no timezone
	testLex( "2013/2/22 07:53",        [ Token(symbol!"Value",loc,Value(DateTimeFrac(DateTime( 2013, 2, 22, 7, 53,  0)))) ]);
	testLex( "2013/2/22 \t 07:53",     [ Token(symbol!"Value",loc,Value(DateTimeFrac(DateTime( 2013, 2, 22, 7, 53,  0)))) ]);
	testLex( "2013/2/22/*foo*/07:53",  [ Token(symbol!"Value",loc,Value(DateTimeFrac(DateTime( 2013, 2, 22, 7, 53,  0)))) ]);
	testLex( "2013/2/22 /*foo*/ \\\n  /*bar*/ 07:53", [ Token(symbol!"Value",loc,Value(DateTimeFrac(DateTime( 2013, 2, 22, 7, 53,  0)))) ]);
	testLex( "2013/2/22 /*foo*/ \\\n\n  \n  /*bar*/ 07:53", [ Token(symbol!"Value",loc,Value(DateTimeFrac(DateTime( 2013, 2, 22, 7, 53,  0)))) ]);
	testLex( "2013/2/22 /*foo*/ \\\n\\\n  \\\n  /*bar*/ 07:53", [ Token(symbol!"Value",loc,Value(DateTimeFrac(DateTime( 2013, 2, 22, 7, 53,  0)))) ]);
	testLex( "2013/2/22/*foo*/\\\n/*bar*/07:53",      [ Token(symbol!"Value",loc,Value(DateTimeFrac(DateTime( 2013, 2, 22, 7, 53,  0)))) ]);
	testLex("-2013/2/22 07:53",        [ Token(symbol!"Value",loc,Value(DateTimeFrac(DateTime(-2013, 2, 22, 7, 53,  0)))) ]);
	testLex( "2013/2/22 -07:53",       [ Token(symbol!"Value",loc,Value(DateTimeFrac(DateTime( 2013, 2, 22, 0,  0,  0) - hours(7) - minutes(53)))) ]);
	testLex("-2013/2/22 -07:53",       [ Token(symbol!"Value",loc,Value(DateTimeFrac(DateTime(-2013, 2, 22, 0,  0,  0) - hours(7) - minutes(53)))) ]);
	testLex( "2013/2/22 07:53:34",     [ Token(symbol!"Value",loc,Value(DateTimeFrac(DateTime( 2013, 2, 22, 7, 53, 34)))) ]);
	testLex( "2013/2/22 07:53:34.123", [ Token(symbol!"Value",loc,Value(DateTimeFrac(DateTime( 2013, 2, 22, 7, 53, 34), FracSec.from!"msecs"(123)))) ]);
	testLex( "2013/2/22 07:53:34.12",  [ Token(symbol!"Value",loc,Value(DateTimeFrac(DateTime( 2013, 2, 22, 7, 53, 34), FracSec.from!"msecs"(120)))) ]);
	testLex( "2013/2/22 07:53:34.1",   [ Token(symbol!"Value",loc,Value(DateTimeFrac(DateTime( 2013, 2, 22, 7, 53, 34), FracSec.from!"msecs"(100)))) ]);
	testLex( "2013/2/22 07:53.123",    [ Token(symbol!"Value",loc,Value(DateTimeFrac(DateTime( 2013, 2, 22, 7, 53,  0), FracSec.from!"msecs"(123)))) ]);

	testLex( "2013/2/22 34:65",        [ Token(symbol!"Value",loc,Value(DateTimeFrac(DateTime( 2013, 2, 22, 0, 0, 0) + hours(34) + minutes(65) + seconds( 0)))) ]);
	testLex( "2013/2/22 34:65:77.123", [ Token(symbol!"Value",loc,Value(DateTimeFrac(DateTime( 2013, 2, 22, 0, 0, 0) + hours(34) + minutes(65) + seconds(77), FracSec.from!"msecs"(123)))) ]);
	testLex( "2013/2/22 34:65.123",    [ Token(symbol!"Value",loc,Value(DateTimeFrac(DateTime( 2013, 2, 22, 0, 0, 0) + hours(34) + minutes(65) + seconds( 0), FracSec.from!"msecs"(123)))) ]);

	testLex( "2013/2/22 -34:65",        [ Token(symbol!"Value",loc,Value(DateTimeFrac(DateTime( 2013, 2, 22, 0, 0, 0) - hours(34) - minutes(65) - seconds( 0)))) ]);
	testLex( "2013/2/22 -34:65:77.123", [ Token(symbol!"Value",loc,Value(DateTimeFrac(DateTime( 2013, 2, 22, 0, 0, 0) - hours(34) - minutes(65) - seconds(77), FracSec.from!"msecs"(-123)))) ]);
	testLex( "2013/2/22 -34:65.123",    [ Token(symbol!"Value",loc,Value(DateTimeFrac(DateTime( 2013, 2, 22, 0, 0, 0) - hours(34) - minutes(65) - seconds( 0), FracSec.from!"msecs"(-123)))) ]);

	testLexThrows("2013/2/22 07:53a");
	testLexThrows("2013/2/22 07:53f");
	testLexThrows("2013/2/22 07:53:34.123a");
	testLexThrows("2013/2/22 07:53:34.123f");
	testLexThrows("2013/2/22a 07:53");

	testLex(`2013/2/22 "foo"`, [
		Token(symbol!"Value",loc,Value(Date(2013, 2, 22))),
		Token(symbol!"Value",loc,Value("foo")),
	]);

	testLex("2013/2/22 07", [
		Token(symbol!"Value",loc,Value(Date(2013, 2, 22))),
		Token(symbol!"Value",loc,Value(cast(int)7)),
	]);

	testLex("2013/2/22 1.2F", [
		Token(symbol!"Value",loc,Value(Date(2013, 2, 22))),
		Token(symbol!"Value",loc,Value(cast(float)1.2)),
	]);

	testLex("2013/2/22 .2F", [
		Token(symbol!"Value",loc,Value(Date(2013, 2, 22))),
		Token(symbol!"Value",loc,Value(cast(float)0.2)),
	]);

	testLex("2013/2/22 -1.2F", [
		Token(symbol!"Value",loc,Value(Date(2013, 2, 22))),
		Token(symbol!"Value",loc,Value(cast(float)-1.2)),
	]);

	testLex("2013/2/22 -.2F", [
		Token(symbol!"Value",loc,Value(Date(2013, 2, 22))),
		Token(symbol!"Value",loc,Value(cast(float)-0.2)),
	]);

	// DateTime, with known timezone
	testLex( "2013/2/22 07:53-GMT+00:00",        [ Token(symbol!"Value",loc,Value(SysTime(DateTime( 2013, 2, 22, 7, 53,  0), new immutable SimpleTimeZone( hours(0)            )))) ]);
	testLex("-2013/2/22 07:53-GMT+00:00",        [ Token(symbol!"Value",loc,Value(SysTime(DateTime(-2013, 2, 22, 7, 53,  0), new immutable SimpleTimeZone( hours(0)            )))) ]);
	testLex( "2013/2/22 -07:53-GMT+00:00",       [ Token(symbol!"Value",loc,Value(SysTime(DateTime( 2013, 2, 22, 0,  0,  0) - hours(7) - minutes(53), new immutable SimpleTimeZone( hours(0)            )))) ]);
	testLex("-2013/2/22 -07:53-GMT+00:00",       [ Token(symbol!"Value",loc,Value(SysTime(DateTime(-2013, 2, 22, 0,  0,  0) - hours(7) - minutes(53), new immutable SimpleTimeZone( hours(0)            )))) ]);
	testLex( "2013/2/22 07:53-GMT+02:10",        [ Token(symbol!"Value",loc,Value(SysTime(DateTime( 2013, 2, 22, 7, 53,  0), new immutable SimpleTimeZone( hours(2)+minutes(10))))) ]);
	testLex( "2013/2/22 07:53-GMT-05:30",        [ Token(symbol!"Value",loc,Value(SysTime(DateTime( 2013, 2, 22, 7, 53,  0), new immutable SimpleTimeZone(-hours(5)-minutes(30))))) ]);
	testLex( "2013/2/22 07:53:34-GMT+00:00",     [ Token(symbol!"Value",loc,Value(SysTime(DateTime( 2013, 2, 22, 7, 53, 34), new immutable SimpleTimeZone( hours(0)            )))) ]);
	testLex( "2013/2/22 07:53:34-GMT+02:10",     [ Token(symbol!"Value",loc,Value(SysTime(DateTime( 2013, 2, 22, 7, 53, 34), new immutable SimpleTimeZone( hours(2)+minutes(10))))) ]);
	testLex( "2013/2/22 07:53:34-GMT-05:30",     [ Token(symbol!"Value",loc,Value(SysTime(DateTime( 2013, 2, 22, 7, 53, 34), new immutable SimpleTimeZone(-hours(5)-minutes(30))))) ]);
	testLex( "2013/2/22 07:53:34.123-GMT+00:00", [ Token(symbol!"Value",loc,Value(SysTime(DateTime( 2013, 2, 22, 7, 53, 34), FracSec.from!"msecs"(123), new immutable SimpleTimeZone( hours(0)            )))) ]);
	testLex( "2013/2/22 07:53:34.123-GMT+02:10", [ Token(symbol!"Value",loc,Value(SysTime(DateTime( 2013, 2, 22, 7, 53, 34), FracSec.from!"msecs"(123), new immutable SimpleTimeZone( hours(2)+minutes(10))))) ]);
	testLex( "2013/2/22 07:53:34.123-GMT-05:30", [ Token(symbol!"Value",loc,Value(SysTime(DateTime( 2013, 2, 22, 7, 53, 34), FracSec.from!"msecs"(123), new immutable SimpleTimeZone(-hours(5)-minutes(30))))) ]);
	testLex( "2013/2/22 07:53.123-GMT+00:00",    [ Token(symbol!"Value",loc,Value(SysTime(DateTime( 2013, 2, 22, 7, 53,  0), FracSec.from!"msecs"(123), new immutable SimpleTimeZone( hours(0)            )))) ]);
	testLex( "2013/2/22 07:53.123-GMT+02:10",    [ Token(symbol!"Value",loc,Value(SysTime(DateTime( 2013, 2, 22, 7, 53,  0), FracSec.from!"msecs"(123), new immutable SimpleTimeZone( hours(2)+minutes(10))))) ]);
	testLex( "2013/2/22 07:53.123-GMT-05:30",    [ Token(symbol!"Value",loc,Value(SysTime(DateTime( 2013, 2, 22, 7, 53,  0), FracSec.from!"msecs"(123), new immutable SimpleTimeZone(-hours(5)-minutes(30))))) ]);

	testLex( "2013/2/22 -34:65-GMT-05:30",       [ Token(symbol!"Value",loc,Value(SysTime(DateTime( 2013, 2, 22, 0,  0,  0) - hours(34) - minutes(65) - seconds( 0), new immutable SimpleTimeZone(-hours(5)-minutes(30))))) ]);

	// DateTime, with Java SDL's occasionally weird interpretation of some
	// "not quite ISO" variations of the "GMT with offset" timezone strings.
	Token testTokenSimpleTimeZone(Duration d)
	{
		auto dateTime = DateTime(2013, 2, 22, 7, 53, 0);
		auto tz = new immutable SimpleTimeZone(d);
		return Token( symbol!"Value", loc, Value(SysTime(dateTime,tz)) );
	}
	Token testTokenUnknownTimeZone(string tzName)
	{
		auto dateTime = DateTime(2013, 2, 22, 7, 53, 0);
		auto frac = FracSec.from!"msecs"(0);
		return Token( symbol!"Value", loc, Value(DateTimeFracUnknownZone(dateTime,frac,tzName)) );
	}
	testLex("2013/2/22 07:53-GMT+",          [ testTokenUnknownTimeZone("GMT+")     ]);
	testLex("2013/2/22 07:53-GMT+:",         [ testTokenUnknownTimeZone("GMT+:")    ]);
	testLex("2013/2/22 07:53-GMT+:3",        [ testTokenUnknownTimeZone("GMT+:3")   ]);
	testLex("2013/2/22 07:53-GMT+:03",       [ testTokenSimpleTimeZone(minutes(3))  ]);
	testLex("2013/2/22 07:53-GMT+:003",      [ testTokenUnknownTimeZone("GMT+:003") ]);

	testLex("2013/2/22 07:53-GMT+4",         [ testTokenSimpleTimeZone(hours(4))            ]);
	testLex("2013/2/22 07:53-GMT+4:",        [ testTokenUnknownTimeZone("GMT+4:")           ]);
	testLex("2013/2/22 07:53-GMT+4:3",       [ testTokenUnknownTimeZone("GMT+4:3")          ]);
	testLex("2013/2/22 07:53-GMT+4:03",      [ testTokenSimpleTimeZone(hours(4)+minutes(3)) ]);
	testLex("2013/2/22 07:53-GMT+4:003",     [ testTokenUnknownTimeZone("GMT+4:003")        ]);

	testLex("2013/2/22 07:53-GMT+04",        [ testTokenSimpleTimeZone(hours(4))            ]);
	testLex("2013/2/22 07:53-GMT+04:",       [ testTokenUnknownTimeZone("GMT+04:")          ]);
	testLex("2013/2/22 07:53-GMT+04:3",      [ testTokenUnknownTimeZone("GMT+04:3")         ]);
	testLex("2013/2/22 07:53-GMT+04:03",     [ testTokenSimpleTimeZone(hours(4)+minutes(3)) ]);
	testLex("2013/2/22 07:53-GMT+04:03abc",  [ testTokenUnknownTimeZone("GMT+04:03abc")     ]);
	testLex("2013/2/22 07:53-GMT+04:003",    [ testTokenUnknownTimeZone("GMT+04:003")       ]);

	testLex("2013/2/22 07:53-GMT+004",       [ testTokenSimpleTimeZone(minutes(4))     ]);
	testLex("2013/2/22 07:53-GMT+004:",      [ testTokenUnknownTimeZone("GMT+004:")    ]);
	testLex("2013/2/22 07:53-GMT+004:3",     [ testTokenUnknownTimeZone("GMT+004:3")   ]);
	testLex("2013/2/22 07:53-GMT+004:03",    [ testTokenUnknownTimeZone("GMT+004:03")  ]);
	testLex("2013/2/22 07:53-GMT+004:003",   [ testTokenUnknownTimeZone("GMT+004:003") ]);

	testLex("2013/2/22 07:53-GMT+0004",      [ testTokenSimpleTimeZone(minutes(4))      ]);
	testLex("2013/2/22 07:53-GMT+0004:",     [ testTokenUnknownTimeZone("GMT+0004:")    ]);
	testLex("2013/2/22 07:53-GMT+0004:3",    [ testTokenUnknownTimeZone("GMT+0004:3")   ]);
	testLex("2013/2/22 07:53-GMT+0004:03",   [ testTokenUnknownTimeZone("GMT+0004:03")  ]);
	testLex("2013/2/22 07:53-GMT+0004:003",  [ testTokenUnknownTimeZone("GMT+0004:003") ]);

	testLex("2013/2/22 07:53-GMT+00004",     [ testTokenSimpleTimeZone(minutes(4))       ]);
	testLex("2013/2/22 07:53-GMT+00004:",    [ testTokenUnknownTimeZone("GMT+00004:")    ]);
	testLex("2013/2/22 07:53-GMT+00004:3",   [ testTokenUnknownTimeZone("GMT+00004:3")   ]);
	testLex("2013/2/22 07:53-GMT+00004:03",  [ testTokenUnknownTimeZone("GMT+00004:03")  ]);
	testLex("2013/2/22 07:53-GMT+00004:003", [ testTokenUnknownTimeZone("GMT+00004:003") ]);

	// DateTime, with unknown timezone
	testLex( "2013/2/22 07:53-Bogus/Foo",        [ Token(symbol!"Value",loc,Value(DateTimeFracUnknownZone(DateTime( 2013, 2, 22, 7, 53,  0), FracSec.from!"msecs"(  0), "Bogus/Foo")), "2013/2/22 07:53-Bogus/Foo") ]);
	testLex("-2013/2/22 07:53-Bogus/Foo",        [ Token(symbol!"Value",loc,Value(DateTimeFracUnknownZone(DateTime(-2013, 2, 22, 7, 53,  0), FracSec.from!"msecs"(  0), "Bogus/Foo"))) ]);
	testLex( "2013/2/22 -07:53-Bogus/Foo",       [ Token(symbol!"Value",loc,Value(DateTimeFracUnknownZone(DateTime( 2013, 2, 22, 0,  0,  0) - hours(7) - minutes(53), FracSec.from!"msecs"(  0), "Bogus/Foo"))) ]);
	testLex("-2013/2/22 -07:53-Bogus/Foo",       [ Token(symbol!"Value",loc,Value(DateTimeFracUnknownZone(DateTime(-2013, 2, 22, 0,  0,  0) - hours(7) - minutes(53), FracSec.from!"msecs"(  0), "Bogus/Foo"))) ]);
	testLex( "2013/2/22 07:53:34-Bogus/Foo",     [ Token(symbol!"Value",loc,Value(DateTimeFracUnknownZone(DateTime( 2013, 2, 22, 7, 53, 34), FracSec.from!"msecs"(  0), "Bogus/Foo"))) ]);
	testLex( "2013/2/22 07:53:34.123-Bogus/Foo", [ Token(symbol!"Value",loc,Value(DateTimeFracUnknownZone(DateTime( 2013, 2, 22, 7, 53, 34), FracSec.from!"msecs"(123), "Bogus/Foo"))) ]);
	testLex( "2013/2/22 07:53.123-Bogus/Foo",    [ Token(symbol!"Value",loc,Value(DateTimeFracUnknownZone(DateTime( 2013, 2, 22, 7, 53,  0), FracSec.from!"msecs"(123), "Bogus/Foo"))) ]);

	// Time Span
	testLex( "12:14:42",         [ Token(symbol!"Value",loc,Value( days( 0)+hours(12)+minutes(14)+seconds(42)+msecs(  0))) ]);
	testLex("-12:14:42",         [ Token(symbol!"Value",loc,Value(-days( 0)-hours(12)-minutes(14)-seconds(42)-msecs(  0))) ]);
	testLex( "00:09:12",         [ Token(symbol!"Value",loc,Value( days( 0)+hours( 0)+minutes( 9)+seconds(12)+msecs(  0))) ]);
	testLex( "00:00:01.023",     [ Token(symbol!"Value",loc,Value( days( 0)+hours( 0)+minutes( 0)+seconds( 1)+msecs( 23))) ]);
	testLex( "23d:05:21:23.532", [ Token(symbol!"Value",loc,Value( days(23)+hours( 5)+minutes(21)+seconds(23)+msecs(532))) ]);
	testLex( "23d:05:21:23.53",  [ Token(symbol!"Value",loc,Value( days(23)+hours( 5)+minutes(21)+seconds(23)+msecs(530))) ]);
	testLex( "23d:05:21:23.5",   [ Token(symbol!"Value",loc,Value( days(23)+hours( 5)+minutes(21)+seconds(23)+msecs(500))) ]);
	testLex("-23d:05:21:23.532", [ Token(symbol!"Value",loc,Value(-days(23)-hours( 5)-minutes(21)-seconds(23)-msecs(532))) ]);
	testLex("-23d:05:21:23.5",   [ Token(symbol!"Value",loc,Value(-days(23)-hours( 5)-minutes(21)-seconds(23)-msecs(500))) ]);
	testLex( "23d:05:21:23",     [ Token(symbol!"Value",loc,Value( days(23)+hours( 5)+minutes(21)+seconds(23)+msecs(  0))) ]);

	testLexThrows("12:14:42a");
	testLexThrows("23d:05:21:23.532a");
	testLexThrows("23d:05:21:23.532f");

	// Combination
	testLex("foo. 7", [
		Token(symbol!"Ident",loc,Value(      null),"foo."),
		Token(symbol!"Value",loc,Value(cast(int)7))
	]);
	
	testLex(`
		namespace:person "foo" "bar" 1 23L name.first="ひとみ" name.last="Smith" {
			namespace:age 37; namespace:favorite_color "blue" // comment
			somedate 2013/2/22  07:53 -- comment
			
			inventory /* comment */ {
				socks
			}
		}
	`,
	[
		Token(symbol!"EOL",loc,Value(null),"\n"),

		Token(symbol!"Ident", loc, Value(         null ), "namespace"),
		Token(symbol!":",     loc, Value(         null ), ":"),
		Token(symbol!"Ident", loc, Value(         null ), "person"),
		Token(symbol!"Value", loc, Value(        "foo" ), `"foo"`),
		Token(symbol!"Value", loc, Value(        "bar" ), `"bar"`),
		Token(symbol!"Value", loc, Value( cast( int) 1 ), "1"),
		Token(symbol!"Value", loc, Value( cast(long)23 ), "23L"),
		Token(symbol!"Ident", loc, Value(         null ), "name.first"),
		Token(symbol!"=",     loc, Value(         null ), "="),
		Token(symbol!"Value", loc, Value(       "ひとみ" ), `"ひとみ"`),
		Token(symbol!"Ident", loc, Value(         null ), "name.last"),
		Token(symbol!"=",     loc, Value(         null ), "="),
		Token(symbol!"Value", loc, Value(      "Smith" ), `"Smith"`),
		Token(symbol!"{",     loc, Value(         null ), "{"),
		Token(symbol!"EOL",   loc, Value(         null ), "\n"),

		Token(symbol!"Ident", loc, Value(        null ), "namespace"),
		Token(symbol!":",     loc, Value(        null ), ":"),
		Token(symbol!"Ident", loc, Value(        null ), "age"),
		Token(symbol!"Value", loc, Value( cast(int)37 ), "37"),
		Token(symbol!"EOL",   loc, Value(        null ), ";"),
		Token(symbol!"Ident", loc, Value(        null ), "namespace"),
		Token(symbol!":",     loc, Value(        null ), ":"),
		Token(symbol!"Ident", loc, Value(        null ), "favorite_color"),
		Token(symbol!"Value", loc, Value(      "blue" ), `"blue"`),
		Token(symbol!"EOL",   loc, Value(        null ), "\n"),

		Token(symbol!"Ident", loc, Value( null ), "somedate"),
		Token(symbol!"Value", loc, Value( DateTimeFrac(DateTime(2013, 2, 22, 7, 53, 0)) ), "2013/2/22  07:53"),
		Token(symbol!"EOL",   loc, Value( null ), "\n"),
		Token(symbol!"EOL",   loc, Value( null ), "\n"),

		Token(symbol!"Ident", loc, Value(null), "inventory"),
		Token(symbol!"{",     loc, Value(null), "{"),
		Token(symbol!"EOL",   loc, Value(null), "\n"),

		Token(symbol!"Ident", loc, Value(null), "socks"),
		Token(symbol!"EOL",   loc, Value(null), "\n"),

		Token(symbol!"}",     loc, Value(null), "}"),
		Token(symbol!"EOL",   loc, Value(null), "\n"),

		Token(symbol!"}",     loc, Value(null), "}"),
		Token(symbol!"EOL",   loc, Value(null), "\n"),
	]);
	
	if(numErrors > 0)
		stderr.writeln(numErrors, " failed test(s)");
}
