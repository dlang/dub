module dub.internal.vibecompat.data.sdl;

version (Have_vibe_d) public import vibe.data.sdl;
else:

import dub.internal.vibecompat.data.utils;
import dub.internal.vibecompat.data.json;

import std.array;
import std.conv;
import std.datetime;
import std.exception;
import std.format;
import std.string;
import std.range;
import std.traits;

version = JsonLineNumbers;



/******************************************************************************/
/* public functions                                                           */
/******************************************************************************/

/**
	Parses the given range as an SDL string and returns the corresponding SDL object.

	The range is shrunk during parsing, leaving any remaining text that is not part of
	the SDL contents.

	Throws an Exception if any parsing error occured.
*/
Json parseSdl(R)(ref R range, int* line = null)
	if( is(R == string) )
{
	Json ret;
	enforce(!range.empty, "SDL string is empty.");

	skipWhitespace(range, line);

	version(JsonLineNumbers){
		import dub.internal.vibecompat.core.log;
		int curline = line ? *line : 0;
		scope(failure) logError("Error at line: %d", line ? *line : 0);
	}

	switch( range.front ){
		case 'f':
			enforce(range[1 .. $].startsWith("alse"), "Expected 'false', got '"~range[0 .. 5]~"'.");
			range.popFrontN(5);
			ret = false;
			break;
		case 'n':
			enforce(range[1 .. $].startsWith("ull"), "Expected 'null', got '"~range[0 .. 4]~"'.");
			range.popFrontN(4);
			ret = null;
			break;
		case 't':
			enforce(range[1 .. $].startsWith("rue"), "Expected 'true', got '"~range[0 .. 4]~"'.");
			range.popFrontN(4);
			ret = true;
			break;
		case '0': .. case '9'+1:
		case '-':
			bool is_float;
			auto num = skipNumber(range, is_float);
			if( is_float ) ret = to!double(num);
			else ret = to!long(num);
			break;
		case '\"':
			ret = skipSdlString(range);
			break;
		case '[':
			Json[] arr;
			range.popFront();
			while(true) {
				skipWhitespace(range, line);
				enforce(!range.empty);
				if(range.front == ']') break;
				arr ~= parseSdl(range, line);
				skipWhitespace(range, line);
				enforce(!range.empty && (range.front == ',' || range.front == ']'), "Expected ']' or ','.");
				if( range.front == ']' ) break;
				else range.popFront();
			}
			range.popFront();
			ret = arr;
			break;
		case '{':
			Json[string] obj;
			range.popFront();
			while(true) {
				skipWhitespace(range, line);
				enforce(!range.empty);
				if(range.front == '}') break;
				string key = skipSdlString(range);
				skipWhitespace(range, line);
				enforce(range.startsWith(":"), "Expected ':' for key '" ~ key ~ "'");
				range.popFront();
				skipWhitespace(range, line);
				Json itm = parseSdl(range, line);
				obj[key] = itm;
				skipWhitespace(range, line);
				enforce(!range.empty && (range.front == ',' || range.front == '}'), "Expected '}' or ',' - got '"~range[0]~"'.");
				if( range.front == '}' ) break;
				else range.popFront();
			}
			range.popFront();
			ret = obj;
			break;
		default:
			enforce(false, "Expected valid sdl token, got '"~to!string(range.length)~range[0 .. range.length>12?12:range.length]~"'.");
	}

	assert(ret.type != Json.Type.undefined);
	version(JsonLineNumbers) ret.line = curline;
	return ret;
}



/**
	Parses the given JSON string and returns the corresponding Json object.

	Throws an Exception if any parsing error occurs.
*/
Json parseSdlString(string str)
{
	Json json = Json();

	int line = 1;
	int off = 0;
	char c;
	
	while(true) {
		// skip whitespace
		while(true) {
			if(off >= str.length) return json;
			c = str[off];
			if(c == ' ' || c == '\t' || c == '\r') {
			
			} else if(c == '\n') {
				line++;
			} else {
				break;
			}
			off++;
		}
		
		
		throw new Exception("sdl not implemented");
		
	}	
}

unittest {
	assert(parseSdlString("null") == Json(null));
	assert(parseSdlString("true") == Json(true));
	assert(parseSdlString("false") == Json(false));
	assert(parseSdlString("1") == Json(1));
	assert(parseSdlString("2.0") == Json(2.0));
	assert(parseSdlString("\"test\"") == Json("test"));
	assert(parseSdlString("[1, 2, 3]") == Json([Json(1), Json(2), Json(3)]));
	assert(parseSdlString("{\"a\": 1}") == Json(["a": Json(1)]));
	assert(parseSdlString(`"\\\/\b\f\n\r\t\u1234"`).get!string == "\\/\b\f\n\r\t\u1234");
}




/**
	Writes the given JSON object as an SDL string into the destination range.

	This function will convert the given JSON value to a string without adding
	any white space between tokens (no newlines, no indentation and no padding).
	The output size is thus minizized, at the cost of bad human readability.

	Params:
		dst   = References the string output range to which the result is written.
		sdl  = Specifies the JSON value that is to be stringified.

	See_Also: Json.toString, writePrettyJsonString
*/
void writeSdlString(R)(ref R dst, in Json sdl)
//	if( isOutputRange!R && is(ElementEncodingType!R == char) )
{
	final switch( sdl.type ){
		case Json.Type.undefined: dst.put("undefined"); break;
		case Json.Type.null_: dst.put("null"); break;
		case Json.Type.bool_: dst.put(cast(bool)sdl ? "true" : "false"); break;
		case Json.Type.int_: formattedWrite(dst, "%d", sdl.get!long); break;
		case Json.Type.float_: formattedWrite(dst, "%.16g", sdl.get!double); break;
		case Json.Type.string:
			dst.put("\"");
			sdlEscape(dst, cast(string)sdl);
			dst.put("\"");
			break;
		case Json.Type.array:
			dst.put("[");
			bool first = true;
			foreach( ref const Json e; sdl ){
				if( e.type == Json.Type.undefined ) continue;
				if( !first ) dst.put(",");
				first = false;
				writeJsonString(dst, e);
			}
			dst.put("]");
			break;
		case Json.Type.object:
			dst.put("{");
			bool first = true;
			foreach( string k, ref const Json e; sdl ){
				if( e.type == Json.Type.undefined ) continue;
				if( !first ) dst.put(",");
				first = false;
				dst.put("\"");
				sdlEscape(dst, k);
				dst.put("\":");
				writeSdlString(dst, e);
			}
			dst.put("}");
			break;
	}
}

/**
	Writes the given JSON object as a prettified JSON string into the destination range.

	The output will contain newlines and indents to make the output human readable.

	Params:
		dst   = References the string output range to which the result is written.
		sdl  = Specifies the JSON value that is to be stringified.
		level = Specifies the base amount of indentation for the output. Indentation is always
			done using tab characters.

	See_Also: Json.toPrettyString, writeJsonString
*/
void writePrettySdlString(R)(ref R dst, in Json sdl, int level = 0)
//	if( isOutputRange!R && is(ElementEncodingType!R == char) )
{
	final switch( sdl.type ){
		case Json.Type.undefined: dst.put("undefined"); break;
		case Json.Type.null_: dst.put("null"); break;
		case Json.Type.bool_: dst.put(cast(bool)sdl ? "true" : "false"); break;
		case Json.Type.int_: formattedWrite(dst, "%d", sdl.get!long); break;
		case Json.Type.float_: formattedWrite(dst, "%.16g", sdl.get!double); break;
		case Json.Type.string:
			dst.put("\"");
			sdlEscape(dst, cast(string)sdl);
			dst.put("\"");
			break;
		case Json.Type.array:
			dst.put("[");
			bool first = true;
			foreach( e; sdl ){
				if( e.type == Json.Type.undefined ) continue;
				if( !first ) dst.put(",");
				first = false;
				dst.put("\n");
				foreach( tab; 0 .. level+1 ) dst.put('\t');
				writePrettySdlString(dst, e, level+1);
			}
			if( sdl.length > 0 ) {
				dst.put('\n');
				foreach( tab; 0 .. level ) dst.put('\t');
			}
			dst.put("]");
			break;
		case Json.Type.object:
			dst.put("{");
			bool first = true;
			foreach( string k, e; sdl ){
				if( e.type == Json.Type.undefined ) continue;
				if( !first ) dst.put(",");
				dst.put("\n");
				first = false;
				foreach( tab; 0 .. level+1 ) dst.put('\t');
				dst.put("\"");
				sdlEscape(dst, k);
				dst.put("\": ");
				writePrettySdlString(dst, e, level+1);
			}
			if( sdl.length > 0 ) {
				dst.put('\n');
				foreach( tab; 0 .. level ) dst.put('\t');
			}
			dst.put("}");
			break;
	}
}

/// private
private void sdlEscape(R)(ref R dst, string s)
{
	foreach( ch; s ){
		switch(ch){
			default: dst.put(ch); break;
			case '\\': dst.put("\\\\"); break;
			case '\r': dst.put("\\r"); break;
			case '\n': dst.put("\\n"); break;
			case '\t': dst.put("\\t"); break;
			case '\"': dst.put("\\\""); break;
		}
	}
}

/// private
private string sdlUnescape(R)(ref R range)
{
	auto ret = appender!string();
	while(!range.empty){
		auto ch = range.front;
		switch( ch ){
			case '"': return ret.data;
			case '\\':
				range.popFront();
				enforce(!range.empty, "Unterminated string escape sequence.");
				switch(range.front){
					default: enforce("Invalid string escape sequence."); break;
					case '"': ret.put('\"'); range.popFront(); break;
					case '\\': ret.put('\\'); range.popFront(); break;
					case '/': ret.put('/'); range.popFront(); break;
					case 'b': ret.put('\b'); range.popFront(); break;
					case 'f': ret.put('\f'); range.popFront(); break;
					case 'n': ret.put('\n'); range.popFront(); break;
					case 'r': ret.put('\r'); range.popFront(); break;
					case 't': ret.put('\t'); range.popFront(); break;
					case 'u':
						range.popFront();
						dchar uch = 0;
						foreach( i; 0 .. 4 ){
							uch *= 16;
							enforce(!range.empty, "Unicode sequence must be '\\uXXXX'.");
							auto dc = range.front;
							range.popFront();
							if( dc >= '0' && dc <= '9' ) uch += dc - '0';
							else if( dc >= 'a' && dc <= 'f' ) uch += dc - 'a' + 10;
							else if( dc >= 'A' && dc <= 'F' ) uch += dc - 'A' + 10;
							else enforce(false, "Unicode sequence must be '\\uXXXX'.");
						}
						ret.put(uch);
						break;
				}
				break;
			default:
				ret.put(ch);
				range.popFront();
				break;
		}
	}
	return ret.data;
}

private string skipNumber(ref string s, out bool is_float)
{
	size_t idx = 0;
	is_float = false;
	if( s[idx] == '-' ) idx++;
	if( s[idx] == '0' ) idx++;
	else {
		enforce(isDigit(s[idx++]), "Digit expected at beginning of number.");
		while( idx < s.length && isDigit(s[idx]) ) idx++;
	}

	if( idx < s.length && s[idx] == '.' ){
		idx++;
		is_float = true;
		while( idx < s.length && isDigit(s[idx]) ) idx++;
	}

	if( idx < s.length && (s[idx] == 'e' || s[idx] == 'E') ){
		idx++;
		is_float = true;
		if( idx < s.length && (s[idx] == '+' || s[idx] == '-') ) idx++;
		enforce( idx < s.length && isDigit(s[idx]), "Expected exponent." ~ s[0 .. idx]);
		idx++;
		while( idx < s.length && isDigit(s[idx]) ) idx++;
	}

	string ret = s[0 .. idx];
	s = s[idx .. $];
	return ret;
}

private string skipSdlString(ref string s, int* line = null)
{
	enforce(s.length >= 2, "Too small for a string: '" ~ s ~ "'");
	enforce(s[0] == '\"', "Expected string, not '" ~ s ~ "'");
	s = s[1 .. $];
	string ret = sdlUnescape(s);
	enforce(s.length > 0 && s[0] == '\"', "Unterminated string literal.");
	s = s[1 .. $];
	return ret;
}

private void skipWhitespace(ref string s, int* line = null)
{
	while( s.length > 0 ){
		switch( s[0] ){
			default: return;
			case ' ', '\t': s = s[1 .. $]; break;
			case '\n':
				s = s[1 .. $];
				if( s.length > 0 && s[0] == '\r' ) s = s[1 .. $];
				if( line ) (*line)++;
				break;
			case '\r':
				s = s[1 .. $];
				if( s.length > 0 && s[0] == '\n' ) s = s[1 .. $];
				if( line ) (*line)++;
				break;
		}
	}
}

/// private
private bool isDigit(T)(T ch){ return ch >= '0' && ch <= '9'; }

private string underscoreStrip(string field_name)
{
	if( field_name.length < 1 || field_name[$-1] != '_' ) return field_name;
	else return field_name[0 .. $-1];
}

private template isSdlSerializable(T) { enum isSdlSerializable = is(typeof(T.init.toSdl()) == Json) && is(typeof(T.fromSdl(Json())) == T); }
package template isStringSerializable(T) { enum isStringSerializable = is(typeof(T.init.toString()) == string) && is(typeof(T.fromString("")) == T); }
