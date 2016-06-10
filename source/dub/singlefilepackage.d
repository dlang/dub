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
		return parsePackageRecipe(_code, _filename);
	}
	auto toString() {
		import std.format;
		return "%s:\n%s".format(_filename, _code);
	}

private:
	string _filename;
	string _code;
	void init() {
		while (!empty && !hadFileName) {
			popFront;
		}
		enforce(!empty, "Missing /+ dub.(sdl|json):... +/ recipe comment.");
		_filename = front;
		popFront();
		_code = front;
	}

	string sourcecode;
	string front;
	bool empty;
	char inComment = '\0';
	bool hadFileName;
	bool hadData;
	int depth;
	void popFront() {
		import std.ascii : isWhite;
		if (empty) return;
		while (sourcecode.length > 0) {
			if (sourcecode[0].isWhite) {
				sourcecode = sourcecode[1..$];
			} else {
				break;
			}
		}
		if (sourcecode.length <= 0) {
			empty = true;
			return;
		}

		int i,j;
		for (; i<sourcecode.length; i++) {
			if (sourcecode[i] == '"') {
				do {
					i++;
					if (sourcecode[i]=='"')
						break;
				} while (i < sourcecode.length);
				continue;
			}
			if (sourcecode[i] == '/') {
				j=i;
				if (inComment=='\0') {
					i++;
					if (sourcecode[i] == '+' || sourcecode[i]=='*') {
						depth++;
						inComment = sourcecode[i];
						i++;
						break;
					}
				} else {
					if (i>0 && sourcecode[i-1]==inComment) {
						if (hadFileName && !hadData) {
							j=0;
							i-=2;
							hadData = true;
							break;
						} else if (hadData) {
							empty = true;
							return;
						}
						inComment = '\0';
						depth--;
						j--;
						i++;
						break;
					}
				}
			}
			if (depth==1 && !hadFileName && inComment && sourcecode[i]==':') {
				hadFileName = true;
				break;
			}
		}
		front = sourcecode[j..i];
		if (hadFileName) {
			i++;
			if (front != "dub.sdl" && front != "dub.json") {
				hadFileName = false; // allow us to keep searching comments if this was a false match
			}
		}
		sourcecode = sourcecode[i..$];
	}
}


unittest {
	/+
	-> nothing
	+/
	assertThrown!Exception(SingleFilePackage("/* foo: */"));


	//-> nothing
	assertThrown!Exception(SingleFilePackage(`/+ foo: +/`));

	//
	//-> valid
	assertNotThrown!Exception(SingleFilePackage(`/* /* */ /* dub.json: {} */`));

	//-> invalid
	//assertThrown!Exception(SingleFilePackage(`/+ /+ +/ /+ dub.json: {} +/`));

	//auto sfp = SingleFilePackage(`/+ /+ +/ /+ dub.json: {} +/`);
	//import std.stdio;
	//writeln("sfp: ", sfp.toString);

	//-> valid
	assertNotThrown!Exception(SingleFilePackage(r"/+ /+ +/ +/ /+ dub.json: {} +/"));

	//`// dub.json:
	//// {}
	//`
	//-> valid

	//`/** dub.json: */`
	//-> invalid, should probably emit a warning that doc comment syntax is not allowed for recipe comments

	//-> invalid
	assertThrown!Exception(SingleFilePackage(`/++ dub.json: */`));

	//-> invalid
	assertThrown!Exception(SingleFilePackage(`/// dub.json:`));
}
