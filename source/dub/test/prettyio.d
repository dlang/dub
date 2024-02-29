/** Pretty Printing.
 *
 * Copyright: Per Nordlöw 2022-.
 * License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: $(WEB Per Nordlöw)
 *
 * TODO: Merge in wip-src/pretty.d
 *
 * Test: dmd -I.. -i -unittest -version=show -main -run prettyio.d
 */
module dub.test.prettyio;

// TODO: instead override?:
// void toString(Sink)(ref scope Sink sink) const scope;

/++ Colorized version of `std.stdio.write`.
 +/
void cwrite(T...)(T args) {
	import std.stdio : sw = write;
	version (none) import nxt.ansi_escape : putWithSGRs; // TODO: use below:
	alias w = pathWrapperSymbol;
	static foreach (arg; args) {{
		static immutable S = typeof(arg).stringof;
		// pragma(msg, __FILE__, "(", __LINE__, ",1): Debug: ", S);
		// static if (S == "URL")
		// 	sw(w, arg, w); // TODO: SGR.yellowForegroundColor
		// else static if (S == "Path")
		// 	sw(w, arg, w); // TODO: SGR.whiteForegroundColor
		// else static if (S == "FilePath")
		// 	sw(w, arg, w); // TODO: SGR.whiteForegroundColor
		// else static if (S == "DirPath")
		// 	sw(w, arg, w); // TODO: SGR.cyanForegroundColor
		// else static if (S == "ExePath")
		// 	sw(w, arg, w); // TODO: SGR.lightRedForegroundColor
		// else static if (S == "FileName")
		// 	sw(w, arg, w); // TODO: SGR.whiteForegroundColor
		// else static if (S == "DirName")
		// 	sw(w, arg, w); // TODO: SGR.redForegroundColor
		// else static if (S == "ExitStatus")
		// 	sw(w, arg, w); // TODO: SGR.greenForegroundColor if arg == 0, otherwise SGR.redForegroundColor
		// else
		sw(arg);
	}}
}

/++ Colorized version of `std.stdio.writeln`.
 +/
void cwriteln(T...)(T args) {
	import std.stdio : swln = writeln;
	// TODO: is this ok?:
	cwrite!(T)(args);
	swln();
}

/++ Wrapper symbol when printing paths and URLs to standard out (`stdout`) and standard error (`stderr`).
 +/
private static immutable string pathWrapperSymbol = `"`;

/++ Colorized pretty print `arg`.
 +/
void cwritePretty(T)(T arg,
					 in size_t depth = 0,
					 in char[] fieldName = [],
					 in char[] indent = "\t",
					 in char[] lterm = "\n",
					 in bool showType = true,
					 in void*[] ptrs = []) {
	void cwriteIndent() {
		foreach (_; 0 .. depth) cwrite(indent);
	}
	void cwriteFieldName() {
		if (fieldName) cwrite(fieldName, ": ");
	}
	static immutable typeName = T.stringof;
	void cwriteTypeName() {
		// static if (is(T == struct))
		// 	cwrite("struct ");
		// else if (is(T == class))
		// 	cwrite("class ");
		if (showType) cwrite(typeName, " ");
	}
	import std.traits : isArray, isSomeString, isSomeChar;
	import std.range.primitives : ElementType;
	cwriteIndent();
	cwriteFieldName();
	cwriteTypeName();
    static if (is(T == struct) || is(T == class)) { // TODO: union
		import std.traits : FieldNameTuple;
		void cwriteMembers() {
			foreach (memberName; FieldNameTuple!T)
				cwritePretty(__traits(getMember, arg, memberName), depth + 1, memberName, indent);
		}
		static if (is(T == class)) {
			if (arg is null) {
				cwrite("null", lterm);
			} else {
				cwrite('@', cast(void*)arg, ' ');
				cwrite("{", lterm);
				cwriteMembers();
				cwriteIndent();
				cwrite("}", lterm);
			}
		} else {
			cwrite("{", lterm);
			cwriteMembers();
			cwriteIndent();
			cwrite("}", lterm);
		}
    } else static if (isSomeString!T) {
        cwrite('"', arg, '"', lterm);
    } else static if (isSomeChar!T) {
        cwrite(`'`, arg, `'`, lterm);
    } else static if (isArray!T) {
        cwrite("[");
		alias E = ElementType!(T);
        foreach (ref element; arg) {
			static if (__traits(isScalar, E)) {
				cwritePretty(element, 0, [], [], [], false);
				cwrite(',');
			} else {
				cwriteln();
				cwritePretty(element, depth + 1, [], indent);
			}
		}
		static if (__traits(isScalar, E)) {
			cwrite("]", lterm);
		} else {
			cwriteIndent();
			cwrite("]", lterm);
		}
    } else static if (__traits(isAssociativeArray, T)) {
        cwrite(arg, lterm);
    } else {
        cwrite(arg, lterm);
    }
}

@safe struct P {
    double x;
    double y;
    double z;
}

@safe struct S {
    int x;
    double y;
	char[3] c3 = "abc";
	string w3 = "xyz";
	int[3] i3;
	float[3] f3;
	double[3] d3;
	real[3] r3;
	int[string] ais = ["a":1, "b":2];
	P[string] ps = ["a":P(1,2,3)];
}

@safe class Cls {
	this(int x) {
		this.x = x;
	}
    int x;
}

@safe struct Top {
    S s;
    S[2] s2;
    Cls cls;
    Cls clsNull;
    string name;
    int[] numbers;
}

version (show)
@safe unittest {
	S s = S(10, 20.5);
    Top top = { s, [s,s], new Cls(1), null, "example", [1, 2, 3] };
    top.cwritePretty(0, "top", "\t");
}
