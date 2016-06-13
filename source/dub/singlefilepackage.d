/**
	A package manager.

	Copyright: © 2012-2013 Matthias Dondorff, 2012-2016 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Rory McGuire
*/
module dub.singlefilepackage;

import dub.internal.vibecompat.core.file;
import std.exception;
import std.file;
struct SingleFilePackage {
	static typeof(this) opCall(Path path) {
		import std.file : mkdirRecurse, readText;
		SingleFilePackage ret;
		ret.sourcecode = readText(path.toNativeString());
		ret.init();
		return ret;
	}
	static typeof(this) opCall(string data) {
		SingleFilePackage ret;
		ret.sourcecode = data;
		ret.init();
		return ret;
	}
	auto getRecipe() {
		import dub.recipe.io : parsePackageRecipe;
		return parsePackageRecipe(_recipe, _filename);
	}
	auto toString() {
		import std.format;
		return "%s:\n%s".format(_filename, _recipe);
	}

private:
	string _filename;
	string _recipe;
	void init() {
		import std.string : startsWith, indexOf, strip;
		import std.algorithm : find;
		enforce(sourcecode.startsWith("#!"), "single file packages must start with #!");
		auto unix = sourcecode.find('\n');
		auto mac = sourcecode.find('\r');
		auto sourcecode = unix.length > mac.length ? unix : mac;
		enforce(sourcecode.length > 0, "second line of single file package must contain dub recipe");
		sourcecode = sourcecode[1..$];
		enum shortest = `/+dub.sdl:{}+/`;
		enforce(sourcecode.length >= shortest.length && sourcecode[0]=='/'
				&& (sourcecode[1] == '*' || sourcecode[1] == '+')
			, "second line of single file package must contain dub recipe");
		enum shortestWithCode = `/+dub.sdl:{}+/void main(){}`; // shortest valid
		enforce(sourcecode.length >= shortestWithCode.length, "single file package must contain code");
		
		auto stop = sourcecode[1];
		sourcecode = sourcecode[2..$].strip;
		enforce(sourcecode[0]!='*' && sourcecode[0]!='+', "documentation style comments not supported for dub recipe comment");

		size_t i;
		for(; i<sourcecode.length; i++) {
			if (sourcecode[i]==stop) {
				i++;
				if (i<sourcecode.length && sourcecode[i]=='/') {
					break;
				}
			}
		}
		auto colon = sourcecode.indexOf(':');
		enforce(i-1 > colon+1 && colon >= 7, "Missing /+ dub.(sdl|json): ... +/ recipe comment."); //dub.sdl: // shortest valid
		enforce(i < sourcecode.length, "unclosed dub recipe comment");

		_filename = sourcecode[0..colon];
		_recipe = sourcecode[colon+1..i-1];
	}

	string sourcecode;
}


unittest {
	// first line must be #!
	assertThrown!Exception(SingleFilePackage("/* dub.json: {} */void main(){}"));
	// missing dub recipe
	assertThrown!Exception(SingleFilePackage("#!/asdf\n/* dub: {} */void main(){}"));
	// single file package must contain code
	assertThrown!Exception(SingleFilePackage("#!/asdf\n/* dub.sdl: */"));
	// documentation style comments not supported for dub recipe comment
	assertThrown!Exception(SingleFilePackage("#!/asdf\n/** dub.json: {} */void main(){}"));
	// documentation style comments not supported for dub recipe comment
	assertThrown!Exception(SingleFilePackage("#!/asdf\n/++ dub.json: {} +/void main(){}"));
	// unclosed dub recipe comment
	assertThrown!Exception(SingleFilePackage("#!/asdf\n/* dub.json: {} * /void main(){}"));

	assertNotThrown!Exception(SingleFilePackage("#!/asdf\n/* dub.sdl: {name:\"*\"} */void main(){}"));
	assertNotThrown!Exception(SingleFilePackage("#!/asdf\n/+ dub.json: /* some sdl comment */ +/void main(){}"));
	assertNotThrown!Exception(SingleFilePackage("#!/asdf\n/* dub.json: {} */void main(){}"));
	assertNotThrown!Exception(SingleFilePackage("#!/asdf\n/* dub.sdl: {} */void main(){}"));
}
