/**
 * Algebraic data type implementation based on a tagged union.
 * 
 * Copyright: Copyright 2015, Sönke Ludwig.
 * License:   $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Sönke Ludwig
*/
module dub.internal.taggedalgebraic;

version (Have_taggedalgebraic) public import taggedalgebraic;
else:

import std.typetuple;

// TODO:
//  - distinguish between @property and non@-property methods.
//  - verify that static methods are handled properly

/** Implements a generic algebraic type using an enum to identify the stored type.

	This struct takes a `union` or `struct` declaration as an input and builds
	an algebraic data type from its fields, using an automatically generated
	`Kind` enumeration to identify which field of the union is currently used.
	Multiple fields with the same value are supported.

	All operators and methods are transparently forwarded to the contained
	value. The caller has to make sure that the contained value supports the
	requested operation. Failure to do so will result in an assertion failure.

	The return value of forwarded operations is determined as follows:
	$(UL
		$(LI If the type can be uniquely determined, it is used as the return
			value)
		$(LI If there are multiple possible return values and all of them match
			the unique types defined in the `TaggedAlgebraic`, a
			`TaggedAlgebraic` is returned.)
		$(LI If there are multiple return values and none of them is a
			`Variant`, an `Algebraic` of the set of possible return types is
			returned.)
		$(LI If any of the possible operations returns a `Variant`, this is used
			as the return value.)
	)
*/
struct TaggedAlgebraic(U) if (is(U == union) || is(U == struct))
{
	import std.algorithm : among;
	import std.string : format;
	import std.traits : FieldTypeTuple, FieldNameTuple, Largest, hasElaborateCopyConstructor, hasElaborateDestructor;

	private alias Union = U;
	private alias FieldTypes = FieldTypeTuple!U;
	private alias fieldNames = FieldNameTuple!U;

	static assert(FieldTypes.length > 0, "The TaggedAlgebraic's union type must have at least one field.");
	static assert(FieldTypes.length == fieldNames.length);


	private {
		void[Largest!FieldTypes.sizeof] m_data = void;
		Kind m_kind;
	}

	/// A type enum that identifies the type of value currently stored.
	alias Kind = TypeEnum!U;

	/// Compatibility alias
	deprecated("Use 'Kind' instead.") alias Type = Kind;

	/// The type ID of the currently stored value.
	@property Kind kind() const { return m_kind; }

	// Compatibility alias
	deprecated("Use 'kind' instead.")
	alias typeID = kind;

	// constructors
	//pragma(msg, generateConstructors!U());
	mixin(generateConstructors!U);

	this(TaggedAlgebraic other)
	{
		import std.algorithm : swap;
		swap(this, other);
	}

	void opAssign(TaggedAlgebraic other)
	{
		import std.algorithm : swap;
		swap(this, other);
	}

	// postblit constructor
	static if (anySatisfy!(hasElaborateCopyConstructor, FieldTypes))
	{
		this(this)
		{
			switch (m_kind) {
				default: break;
				foreach (i, tname; fieldNames) {
					alias T = typeof(__traits(getMember, U, tname));
					static if (hasElaborateCopyConstructor!T)
					{
						case __traits(getMember, Kind, tname):
							typeid(T).postblit(cast(void*)&trustedGet!tname());
							return;
					}
				}
			}
		}
	}

	// destructor
	static if (anySatisfy!(hasElaborateDestructor, FieldTypes))
	{
		~this()
		{
			final switch (m_kind) {
				foreach (i, tname; fieldNames) {
					alias T = typeof(__traits(getMember, U, tname));
					case __traits(getMember, Kind, tname):
						static if (hasElaborateDestructor!T) {
							.destroy(trustedGet!tname);
						}
						return;
				}
			}
		}
	}

	/// Enables conversion or extraction of the stored value.
	T opCast(T)()
	{
		import std.conv : to;

		final switch (m_kind) {
			foreach (i, FT; FieldTypes) {
				case __traits(getMember, Kind, fieldNames[i]):
					static if (is(typeof(to!T(trustedGet!(fieldNames[i]))))) {
						return to!T(trustedGet!(fieldNames[i]));
					} else {
						assert(false, "Cannot cast a "~(cast(Kind)m_kind).to!string~" value ("~FT.stringof~") to "~T.stringof);
					}
			}
		}
		assert(false); // never reached
	}
	/// ditto
	T opCast(T)() const
	{
		// this method needs to be duplicated because inout doesn't work with to!()
		import std.conv : to;

		final switch (m_kind) {
			foreach (i, FT; FieldTypes) {
				case __traits(getMember, Kind, fieldNames[i]):
					static if (is(typeof(to!T(trustedGet!(fieldNames[i]))))) {
						return to!T(trustedGet!(fieldNames[i]));
					} else {
						assert(false, "Cannot cast a "~(cast(Kind)m_kind).to!string~" value ("~FT.stringof~") to "~T.stringof);
					}
			}
		}
		assert(false); // never reached
	}

	/// Uses `cast(string)`/`to!string` to return a string representation of the enclosed value.
	string toString() const { return cast(string)this; }

	// NOTE: "this TA" is used here as the functional equivalent of inout,
	//       just that it generates one template instantiation per modifier
	//       combination, so that we can actually decide what to do for each
	//       case.

	/// Enables the invocation of methods of the stored value.
	auto opDispatch(string name, this TA, ARGS...)(auto ref ARGS args) if (hasOp!(TA, OpKind.method, name, ARGS)) { return implementOp!(OpKind.method, name)(this, args); }
	/// Enables accessing properties/fields of the stored value.
	@property auto opDispatch(string name, this TA, ARGS...)(auto ref ARGS args) if (hasOp!(TA, OpKind.field, name, ARGS) && !hasOp!(TA, OpKind.method, name, ARGS)) { return implementOp!(OpKind.field, name)(this, args); }
	/// Enables equality comparison with the stored value.
	auto opEquals(T, this TA)(auto ref T other) if (hasOp!(TA, OpKind.binary, "==", T)) { return implementOp!(OpKind.binary, "==")(this, other); }
	/// Enables relational comparisons with the stored value.
	auto opCmp(T, this TA)(auto ref T other) if (hasOp!(TA, OpKind.binary, "<", T)) { assert(false, "TODO!"); }
	/// Enables the use of unary operators with the stored value.
	auto opUnary(string op, this TA)() if (hasOp!(TA, OpKind.unary, op)) { return implementOp!(OpKind.unary, op)(this); }
	/// Enables the use of binary operators with the stored value.
	auto opBinary(string op, T, this TA)(auto ref T other) if (hasOp!(TA, OpKind.binary, op, T)) { return implementOp!(OpKind.binary, op)(this, other); }
	/// Enables the use of binary operators with the stored value.
	auto opBinaryRight(string op, T, this TA)(auto ref T other) if (hasOp!(TA, OpKind.binaryRight, op, T)) { return implementOp!(OpKind.binaryRight, op)(this, other); }
	/// Enables operator assignments on the stored value.
	auto opOpAssign(string op, T, this TA)(auto ref T other) if (hasOp!(TA, OpKind.binary, op~"=", T)) { return implementOp!(OpKind.binary, op~"=")(this, other); }
	/// Enables indexing operations on the stored value.
	auto opIndex(this TA, ARGS...)(auto ref ARGS args) if (hasOp!(TA, OpKind.index, null, ARGS)) { return implementOp!(OpKind.index, null)(this, args); }
	/// Enables index assignments on the stored value.
	auto opIndexAssign(this TA, ARGS...)(auto ref ARGS args) if (hasOp!(TA, OpKind.indexAssign, null, ARGS)) { return implementOp!(OpKind.indexAssign, null)(this, args); }
	/// Enables call syntax operations on the stored value.
	auto opCall(this TA, ARGS...)(auto ref ARGS args) if (hasOp!(TA, OpKind.call, null, ARGS)) { return implementOp!(OpKind.call, null)(this, args); }

	private @trusted @property ref inout(typeof(__traits(getMember, U, f))) trustedGet(string f)() inout { return trustedGet!(inout(typeof(__traits(getMember, U, f)))); }
	private @trusted @property ref inout(T) trustedGet(T)() inout { return *cast(inout(T)*)m_data.ptr; }
}

///
unittest
{
	struct Foo {
		string name;
		void bar() {}
	}

	union Base {
		int i;
		string str;
		Foo foo;
	}

	alias Tagged = TaggedAlgebraic!Base;

	// Instantiate
	Tagged taggedInt = 5;
	Tagged taggedString = "Hello";
	Tagged taggedFoo = Foo();
	Tagged taggedAny = taggedInt;
	taggedAny = taggedString;
	taggedAny = taggedFoo;
	
	// Check type: Tagged.Kind is an enum
	assert(taggedInt.kind == Tagged.Kind.i);
	assert(taggedString.kind == Tagged.Kind.str);
	assert(taggedFoo.kind == Tagged.Kind.foo);
	assert(taggedAny.kind == Tagged.Kind.foo);

	// In most cases, can simply use as-is
	auto num = 4 + taggedInt;
	auto msg = taggedString ~ " World!";
	taggedFoo.bar();
	if (taggedAny.kind == Tagged.Kind.foo) // Make sure to check type first!
		taggedAny.bar();
	//taggedString.bar(); // AssertError: Not a Foo!

	// Convert back by casting
	auto i   = cast(int)    taggedInt;
	auto str = cast(string) taggedString;
	auto foo = cast(Foo)    taggedFoo;
	if (taggedAny.kind == Tagged.Kind.foo) // Make sure to check type first!
		auto foo2 = cast(Foo) taggedAny;
	//cast(Foo) taggedString; // AssertError!

	// Kind is an enum, so final switch is supported:
	final switch (taggedAny.kind) {
		case Tagged.Kind.i:
			// It's "int i"
			break;

		case Tagged.Kind.str:
			// It's "string str"
			break;

		case Tagged.Kind.foo:
			// It's "Foo foo"
			break;
	}
}

/** Operators and methods of the contained type can be used transparently.
*/
@trusted unittest {
	static struct S {
		int v;
		int test() { return v / 2; }
	}

	static union Test {
		typeof(null) null_;
		int integer;
		string text;
		string[string] dictionary;
		S custom;
	}

	alias TA = TaggedAlgebraic!Test;

	TA ta;
	assert(ta.kind == TA.Kind.null_);

	ta = 12;
	assert(ta.kind == TA.Kind.integer);
	assert(ta == 12);
	assert(cast(int)ta == 12);
	assert(cast(long)ta == 12);
	assert(cast(short)ta == 12);

	ta += 12;
	assert(ta == 24);
	assert(ta - 10 == 14);

	ta = ["foo" : "bar"];
	assert(ta.kind == TA.Kind.dictionary);
	assert(ta["foo"] == "bar");

	ta["foo"] = "baz";
	assert(ta["foo"] == "baz");

	ta = S(8);
	assert(ta.test() == 4);
}

unittest { // std.conv integration
	import std.conv : to;

	static struct S {
		int v;
		int test() { return v / 2; }
	}

	static union Test {
		typeof(null) null_;
		int number;
		string text;
	}

	alias TA = TaggedAlgebraic!Test;

	TA ta;
	assert(ta.kind == TA.Kind.null_);
	ta = "34";
	assert(ta == "34");
	assert(to!int(ta) == 34, to!string(to!int(ta)));
	assert(to!string(ta) == "34", to!string(ta));
}

/** Multiple fields are allowed to have the same type, in which case the type
	ID enum is used to disambiguate.
*/
@trusted unittest {
	static union Test {
		typeof(null) null_;
		int count;
		int difference;
	}

	alias TA = TaggedAlgebraic!Test;

	TA ta;
	ta = TA(12, TA.Kind.count);
	assert(ta.kind == TA.Kind.count);
	assert(ta == 12);

	ta = null;
	assert(ta.kind == TA.Kind.null_);
}

unittest {
	// test proper type modifier support
	static struct  S {
		void test() {}
		void testI() immutable {}
		void testC() const {}
		void testS() shared {}
		void testSC() shared const {}
	}
	static union U {
		S s;
	}
	
	auto u = TaggedAlgebraic!U(S.init);
	const uc = u;
	immutable ui = cast(immutable)u;
	//const shared usc = cast(shared)u;
	//shared us = cast(shared)u;

	static assert( is(typeof(u.test())));
	static assert(!is(typeof(u.testI())));
	static assert( is(typeof(u.testC())));
	static assert(!is(typeof(u.testS())));
	static assert(!is(typeof(u.testSC())));

	static assert(!is(typeof(uc.test())));
	static assert(!is(typeof(uc.testI())));
	static assert( is(typeof(uc.testC())));
	static assert(!is(typeof(uc.testS())));
	static assert(!is(typeof(uc.testSC())));

	static assert(!is(typeof(ui.test())));
	static assert( is(typeof(ui.testI())));
	static assert( is(typeof(ui.testC())));
	static assert(!is(typeof(ui.testS())));
	static assert( is(typeof(ui.testSC())));

	/*static assert(!is(typeof(us.test())));
	static assert(!is(typeof(us.testI())));
	static assert(!is(typeof(us.testC())));
	static assert( is(typeof(us.testS())));
	static assert( is(typeof(us.testSC())));

	static assert(!is(typeof(usc.test())));
	static assert(!is(typeof(usc.testI())));
	static assert(!is(typeof(usc.testC())));
	static assert(!is(typeof(usc.testS())));
	static assert( is(typeof(usc.testSC())));*/
}

unittest {
	// test attributes on contained values
	import std.typecons : Rebindable, rebindable;

	class C {
		void test() {}
		void testC() const {}
		void testI() immutable {}
	}
	union U {
		Rebindable!(immutable(C)) c;
	}

	auto ta = TaggedAlgebraic!U(rebindable(new immutable C));
	static assert(!is(typeof(ta.test())));
	static assert( is(typeof(ta.testC())));
	static assert( is(typeof(ta.testI())));
}

version (unittest) {
	// test recursive definition using a wrapper dummy struct
	// (needed to avoid "no size yet for forward reference" errors)
	template ID(What) { alias ID = What; }
	private struct _test_Wrapper {
		TaggedAlgebraic!_test_U u;
		alias u this;
		this(ARGS...)(ARGS args) { u = TaggedAlgebraic!_test_U(args); }
	}
	private union _test_U {
		_test_Wrapper[] children;
		int value;
	}
	unittest {
		alias TA = _test_Wrapper;
		auto ta = TA(null);
		ta ~= TA(0);
		ta ~= TA(1);
		ta ~= TA([TA(2)]);
		assert(ta[0] == 0);
		assert(ta[1] == 1);
		assert(ta[2][0] == 2);
	}
}

unittest { // postblit/destructor test
	static struct S {
		static int i = 0;
		bool initialized = false;
		this(bool) { initialized = true; i++; }
		this(this) { if (initialized) i++; }
		~this() { if (initialized) i--; }
	}

	static struct U {
		S s;
		int t;
	}
	alias TA = TaggedAlgebraic!U;
	{
		assert(S.i == 0);
		auto ta = TA(S(true));
		assert(S.i == 1);
		{
			auto tb = ta;
			assert(S.i == 2);
			ta = tb;
			assert(S.i == 2);
			ta = 1;
			assert(S.i == 1);
			ta = S(true);
			assert(S.i == 2);
		}
		assert(S.i == 1);
	}
	assert(S.i == 0);

	static struct U2 {
		S a;
		S b;
	}
	alias TA2 = TaggedAlgebraic!U2;
	{
		auto ta2 = TA2(S(true), TA2.Kind.a);
		assert(S.i == 1);
	}
	assert(S.i == 0);
}

unittest {
	static struct S {
		union U {
			int i;
			string s;
			U[] a;
		}
		alias TA = TaggedAlgebraic!U;
		TA p;
		alias p this;
	}
	S s = S(S.TA("hello"));
	assert(cast(string)s == "hello");
}

unittest { // multiple operator choices
	union U {
		int i;
		double d;
	}
	alias TA = TaggedAlgebraic!U;
	TA ta = 12;
	static assert(is(typeof(ta + 10) == TA)); // ambiguous, could be int or double
	assert((ta + 10).kind == TA.Kind.i);
	assert(ta + 10 == 22);
	static assert(is(typeof(ta + 10.5) == double));
	assert(ta + 10.5 == 22.5);
}

unittest { // Binary op between two TaggedAlgebraic values
	union U { int i; }
	alias TA = TaggedAlgebraic!U;

	TA a = 1, b = 2;
	static assert(is(typeof(a + b) == int));
	assert(a + b == 3);
}

unittest { // Ambiguous binary op between two TaggedAlgebraic values
	union U { int i; double d; }
	alias TA = TaggedAlgebraic!U;

	TA a = 1, b = 2;
	static assert(is(typeof(a + b) == TA));
	assert((a + b).kind == TA.Kind.i);
	assert(a + b == 3);
}

unittest {
	struct S {
		union U {
			@disableIndex string str;
			S[] array;
			S[string] object;
		}
		alias TA = TaggedAlgebraic!U;
		TA payload;
		alias payload this;
	}

	S a = S(S.TA("hello"));
	S b = S(S.TA(["foo": a]));
	S c = S(S.TA([a]));
	assert(b["foo"] == a);
	assert(b["foo"] == "hello");
	assert(c[0] == a);
	assert(c[0] == "hello");
}


/** Tests if the algebraic type stores a value of a certain data type.
*/
bool hasType(T, U)(in ref TaggedAlgebraic!U ta)
{
	alias Fields = Filter!(fieldMatchesType!(U, T), ta.fieldNames);
	static assert(Fields.length > 0, "Type "~T.stringof~" cannot be stored in a "~(TaggedAlgebraic!U).stringof~".");

	switch (ta.kind) {
		default: return false;
		foreach (i, fname; Fields)
			case __traits(getMember, ta.Kind, fname):
				return true;
	}
	assert(false); // never reached
}

///
unittest {
	union Fields {
		int number;
		string text;
	}

	TaggedAlgebraic!Fields ta = "test";

	assert(ta.hasType!string);
	assert(!ta.hasType!int);

	ta = 42;
	assert(ta.hasType!int);
	assert(!ta.hasType!string);
}

unittest { // issue #1
	union U {
		int a;
		int b;
	}
	alias TA = TaggedAlgebraic!U;

	TA ta = TA(0, TA.Kind.b);
	static assert(!is(typeof(ta.hasType!double)));
	assert(ta.hasType!int);
}

/** Gets the value stored in an algebraic type based on its data type.
*/
ref inout(T) get(T, U)(ref inout(TaggedAlgebraic!U) ta)
{
	assert(hasType!(T, U)(ta));
	return ta.trustedGet!T;
}

/// Convenience type that can be used for union fields that have no value (`void` is not allowed).
struct Void {}

/// User-defined attibute to disable `opIndex` forwarding for a particular tagged union member.
@property auto disableIndex() { assert(__ctfe, "disableIndex must only be used as an attribute."); return DisableOpAttribute(OpKind.index, null); }

private struct DisableOpAttribute {
	OpKind kind;
	string name;
}


private template hasOp(TA, OpKind kind, string name, ARGS...)
{
	import std.traits : CopyTypeQualifiers;
	alias UQ = CopyTypeQualifiers!(TA, TA.Union);
	enum hasOp = TypeTuple!(OpInfo!(UQ, kind, name, ARGS).fields).length > 0;
}

unittest {
	static struct S {
		void m(int i) {}
		bool opEquals(int i) { return true; }
		bool opEquals(S s) { return true; }
	}

	static union U { int i; string s; S st; }
	alias TA = TaggedAlgebraic!U;

	static assert(hasOp!(TA, OpKind.binary, "+", int));
	static assert(hasOp!(TA, OpKind.binary, "~", string));
	static assert(hasOp!(TA, OpKind.binary, "==", int));
	static assert(hasOp!(TA, OpKind.binary, "==", string));
	static assert(hasOp!(TA, OpKind.binary, "==", int));
	static assert(hasOp!(TA, OpKind.binary, "==", S));
	static assert(hasOp!(TA, OpKind.method, "m", int));
	static assert(hasOp!(TA, OpKind.binary, "+=", int));
	static assert(!hasOp!(TA, OpKind.binary, "~", int));
	static assert(!hasOp!(TA, OpKind.binary, "~", int));
	static assert(!hasOp!(TA, OpKind.method, "m", string));
	static assert(!hasOp!(TA, OpKind.method, "m"));
	static assert(!hasOp!(const(TA), OpKind.binary, "+=", int));
	static assert(!hasOp!(const(TA), OpKind.method, "m", int));
}

unittest {
	struct S {
		union U {
			string s;
			S[] arr;
			S[string] obj;
		}
		alias TA = TaggedAlgebraic!(S.U);
		TA payload;
		alias payload this;
	}
	static assert(hasOp!(S.TA, OpKind.index, null, size_t));
	static assert(hasOp!(S.TA, OpKind.index, null, int));
	static assert(hasOp!(S.TA, OpKind.index, null, string));
	static assert(hasOp!(S.TA, OpKind.field, "length"));
}

unittest { // "in" operator
	union U {
		string[string] dict;
	}
	alias TA = TaggedAlgebraic!U;
	auto ta = TA(["foo": "bar"]);
	assert("foo" in ta);
	assert(*("foo" in ta) == "bar");
}

private static auto implementOp(OpKind kind, string name, T, ARGS...)(ref T self, auto ref ARGS args)
{
	import std.array : join;
	import std.traits : CopyTypeQualifiers;
	import std.variant : Algebraic, Variant;
	alias UQ = CopyTypeQualifiers!(T, T.Union);

	alias info = OpInfo!(UQ, kind, name, ARGS);

	static assert(hasOp!(T, kind, name, ARGS));

	static assert(info.fields.length > 0, "Implementing operator that has no valid implementation for any supported type.");

	//pragma(msg, "Fields for "~kind.stringof~" "~name~", "~T.stringof~": "~info.fields.stringof);
	//pragma(msg, "Return types for "~kind.stringof~" "~name~", "~T.stringof~": "~info.ReturnTypes.stringof);
	//pragma(msg, typeof(T.Union.tupleof));
	//import std.meta : staticMap; pragma(msg, staticMap!(isMatchingUniqueType!(T.Union), info.ReturnTypes));

	switch (self.m_kind) {
		default: assert(false, "Operator "~name~" ("~kind.stringof~") can only be used on values of the following types: "~[info.fields].join(", "));
		foreach (i, f; info.fields) {
			alias FT = typeof(__traits(getMember, T.Union, f));
			case __traits(getMember, T.Kind, f):
				static if (NoDuplicates!(info.ReturnTypes).length == 1)
					return info.perform(self.trustedGet!FT, args);
				else static if (allSatisfy!(isMatchingUniqueType!(T.Union), info.ReturnTypes))
					return TaggedAlgebraic!(T.Union)(info.perform(self.trustedGet!FT, args));
				else static if (allSatisfy!(isNoVariant, info.ReturnTypes)) {
					alias Alg = Algebraic!(NoDuplicates!(info.ReturnTypes));
					info.ReturnTypes[i] ret = info.perform(self.trustedGet!FT, args);
					import std.traits : isInstanceOf;
					static if (isInstanceOf!(TaggedAlgebraic, typeof(ret))) return Alg(ret.payload);
					else return Alg(ret);
				}
				else static if (is(FT == Variant))
					return info.perform(self.trustedGet!FT, args);
				else
					return Variant(info.perform(self.trustedGet!FT, args));
		}
	}

	assert(false); // never reached
}

unittest { // opIndex on recursive TA with closed return value set
	static struct S {
		union U {
			char ch;
			string str;
			S[] arr;
		}
		alias TA = TaggedAlgebraic!U;
		TA payload;
		alias payload this;

		this(T)(T t) { this.payload = t; }
	}
	S a = S("foo");
	S s = S([a]);

	assert(implementOp!(OpKind.field, "length")(s.payload) == 1);
	static assert(is(typeof(implementOp!(OpKind.index, null)(s.payload, 0)) == S.TA));
	assert(implementOp!(OpKind.index, null)(s.payload, 0) == "foo");
}

unittest { // opIndex on recursive TA with closed return value set using @disableIndex
	static struct S {
		union U {
			@disableIndex string str;
			S[] arr;
		}
		alias TA = TaggedAlgebraic!U;
		TA payload;
		alias payload this;

		this(T)(T t) { this.payload = t; }
	}
	S a = S("foo");
	S s = S([a]);

	assert(implementOp!(OpKind.field, "length")(s.payload) == 1);
	static assert(is(typeof(implementOp!(OpKind.index, null)(s.payload, 0)) == S));
	assert(implementOp!(OpKind.index, null)(s.payload, 0) == "foo");
}


private auto performOpRaw(U, OpKind kind, string name, T, ARGS...)(ref T value, /*auto ref*/ ARGS args)
{
	static if (kind == OpKind.binary) return mixin("value "~name~" args[0]");
	else static if (kind == OpKind.binaryRight) return mixin("args[0] "~name~" value");
	else static if (kind == OpKind.unary) return mixin("name "~value);
	else static if (kind == OpKind.method) return __traits(getMember, value, name)(args);
	else static if (kind == OpKind.field) return __traits(getMember, value, name);
	else static if (kind == OpKind.index) return value[args];
	else static if (kind == OpKind.indexAssign) return value[args[1 .. $]] = args[0];
	else static if (kind == OpKind.call) return value(args);
	else static assert(false, "Unsupported kind of operator: "~kind.stringof);
}

unittest {
	union U { int i; string s; }

	{ int v = 1; assert(performOpRaw!(U, OpKind.binary, "+")(v, 3) == 4); }
	{ string v = "foo"; assert(performOpRaw!(U, OpKind.binary, "~")(v, "bar") == "foobar"); }
}


private auto performOp(U, OpKind kind, string name, T, ARGS...)(ref T value, /*auto ref*/ ARGS args)
{
	import std.traits : isInstanceOf;
	static if (ARGS.length > 0 && isInstanceOf!(TaggedAlgebraic, ARGS[0])) {
		static if (is(typeof(performOpRaw!(U, kind, name, T, ARGS)(value, args)))) {
			return performOpRaw!(U, kind, name, T, ARGS)(value, args);
		} else {
			alias TA = ARGS[0];
			template MTypesImpl(size_t i) {
				static if (i < TA.FieldTypes.length) {
					alias FT = TA.FieldTypes[i];
					static if (is(typeof(&performOpRaw!(U, kind, name, T, FT, ARGS[1 .. $]))))
						alias MTypesImpl = TypeTuple!(FT, MTypesImpl!(i+1));
					else alias MTypesImpl = TypeTuple!(MTypesImpl!(i+1));
				} else alias MTypesImpl = TypeTuple!();
			}
			alias MTypes = NoDuplicates!(MTypesImpl!0);
			static assert(MTypes.length > 0, "No type of the TaggedAlgebraic parameter matches any function declaration.");
			static if (MTypes.length == 1) {
				if (args[0].hasType!(MTypes[0]))
					return performOpRaw!(U, kind, name)(value, args[0].get!(MTypes[0]), args[1 .. $]);
			} else {
				// TODO: allow all return types (fall back to Algebraic or Variant)
				foreach (FT; MTypes) {
					if (args[0].hasType!FT)
						return ARGS[0](performOpRaw!(U, kind, name)(value, args[0].get!FT, args[1 .. $]));
				}
			}
			throw new /*InvalidAgument*/Exception("Algebraic parameter type mismatch");
		}
	} else return performOpRaw!(U, kind, name, T, ARGS)(value, args);
}

unittest {
	union U { int i; double d; string s; }

	{ int v = 1; assert(performOp!(U, OpKind.binary, "+")(v, 3) == 4); }
	{ string v = "foo"; assert(performOp!(U, OpKind.binary, "~")(v, "bar") == "foobar"); }
	{ string v = "foo"; assert(performOp!(U, OpKind.binary, "~")(v, TaggedAlgebraic!U("bar")) == "foobar"); }
	{ int v = 1; assert(performOp!(U, OpKind.binary, "+")(v, TaggedAlgebraic!U(3)) == 4); }
}


private template OpInfo(U, OpKind kind, string name, ARGS...)
{
	import std.traits : CopyTypeQualifiers, FieldTypeTuple, FieldNameTuple, ReturnType;

	private alias FieldTypes = FieldTypeTuple!U;
	private alias fieldNames = FieldNameTuple!U;

	private template isOpEnabled(string field)
	{
		alias attribs = TypeTuple!(__traits(getAttributes, __traits(getMember, U, field)));
		template impl(size_t i) {
			static if (i < attribs.length) {
				static if (is(typeof(attribs[i]) == DisableOpAttribute)) {
					static if (kind == attribs[i].kind && name == attribs[i].name)
						enum impl = false;
					else enum impl = impl!(i+1);
				} else enum impl = impl!(i+1);
			} else enum impl = true;
		}
		enum isOpEnabled = impl!0;
	}

	template fieldsImpl(size_t i)
	{
		static if (i < FieldTypes.length) {
			static if (isOpEnabled!(fieldNames[i]) && is(typeof(&performOp!(U, kind, name, FieldTypes[i], ARGS)))) {
				alias fieldsImpl = TypeTuple!(fieldNames[i], fieldsImpl!(i+1));
			} else alias fieldsImpl = fieldsImpl!(i+1);
		} else alias fieldsImpl = TypeTuple!();
	}
	alias fields = fieldsImpl!0;

	template ReturnTypesImpl(size_t i) {
		static if (i < fields.length) {
			alias FT = CopyTypeQualifiers!(U, typeof(__traits(getMember, U, fields[i])));
			alias ReturnTypesImpl = TypeTuple!(ReturnType!(performOp!(U, kind, name, FT, ARGS)), ReturnTypesImpl!(i+1));
		} else alias ReturnTypesImpl = TypeTuple!();
	}
	alias ReturnTypes = ReturnTypesImpl!0;

	static auto perform(T)(ref T value, auto ref ARGS args) { return performOp!(U, kind, name)(value, args); }
}

private template ImplicitUnqual(T) {
	import std.traits : Unqual, hasAliasing;
	static if (is(T == void)) alias ImplicitUnqual = void;
	else {
		private static struct S { T t; }
		static if (hasAliasing!S) alias ImplicitUnqual = T;
		else alias ImplicitUnqual = Unqual!T;
	}
}

private enum OpKind {
	binary,
	binaryRight,
	unary,
	method,
	field,
	index,
	indexAssign,
	call
}

private template TypeEnum(U)
{
	import std.array : join;
	import std.traits : FieldNameTuple;
	mixin("enum TypeEnum { " ~ [FieldNameTuple!U].join(", ") ~ " }");
}

private string generateConstructors(U)()
{
	import std.algorithm : map;
	import std.array : join;
	import std.string : format;
	import std.traits : FieldTypeTuple;

	string ret;

	// disable default construction if first type is not a null/Void type
	static if (!is(FieldTypeTuple!U[0] == typeof(null)) && !is(FieldTypeTuple!U[0] == Void))
	{
		ret ~= q{
			@disable this();
		};
	}

	// normal type constructors
	foreach (tname; UniqueTypeFields!U)
		ret ~= q{
			this(typeof(U.%s) value)
			{
				m_data.rawEmplace(value);
				m_kind = Kind.%s;
			}

			void opAssign(typeof(U.%s) value)
			{
				if (m_kind != Kind.%s) {
					// NOTE: destroy(this) doesn't work for some opDispatch-related reason
					static if (is(typeof(&this.__xdtor)))
						this.__xdtor();
					m_data.rawEmplace(value);
				} else {
					trustedGet!"%s" = value;
				}
				m_kind = Kind.%s;
			}
		}.format(tname, tname, tname, tname, tname, tname);

	// type constructors with explicit type tag
	foreach (tname; AmbiguousTypeFields!U)
		ret ~= q{
			this(typeof(U.%s) value, Kind type)
			{
				assert(type.among!(%s), format("Invalid type ID for type %%s: %%s", typeof(U.%s).stringof, type));
				m_data.rawEmplace(value);
				m_kind = type;
			}
		}.format(tname, [SameTypeFields!(U, tname)].map!(f => "Kind."~f).join(", "), tname);

	return ret;
}

private template UniqueTypeFields(U) {
	import std.traits : FieldTypeTuple, FieldNameTuple;

	alias Types = FieldTypeTuple!U;

	template impl(size_t i) {
		static if (i < Types.length) {
			enum name = FieldNameTuple!U[i];
			alias T = Types[i];
			static if (staticIndexOf!(T, Types) == i && staticIndexOf!(T, Types[i+1 .. $]) < 0)
				alias impl = TypeTuple!(name, impl!(i+1));
			else alias impl = TypeTuple!(impl!(i+1));
		} else alias impl = TypeTuple!();
	}
	alias UniqueTypeFields = impl!0;
}

private template AmbiguousTypeFields(U) {
	import std.traits : FieldTypeTuple, FieldNameTuple;

	alias Types = FieldTypeTuple!U;

	template impl(size_t i) {
		static if (i < Types.length) {
			enum name = FieldNameTuple!U[i];
			alias T = Types[i];
			static if (staticIndexOf!(T, Types) == i && staticIndexOf!(T, Types[i+1 .. $]) >= 0)
				alias impl = TypeTuple!(name, impl!(i+1));
			else alias impl = impl!(i+1);
		} else alias impl = TypeTuple!();
	}
	alias AmbiguousTypeFields = impl!0;
}

unittest {
	union U {
		int a;
		string b;
		int c;
		double d;
	}
	static assert([UniqueTypeFields!U] == ["b", "d"]);
	static assert([AmbiguousTypeFields!U] == ["a"]);
}

private template SameTypeFields(U, string field) {
	import std.traits : FieldTypeTuple, FieldNameTuple;

	alias Types = FieldTypeTuple!U;

	alias T = typeof(__traits(getMember, U, field));
	template impl(size_t i) {
		static if (i < Types.length) {
			enum name = FieldNameTuple!U[i];
			static if (is(Types[i] == T))
				alias impl = TypeTuple!(name, impl!(i+1));
			else alias impl = TypeTuple!(impl!(i+1));
		} else alias impl = TypeTuple!();
	}
	alias SameTypeFields = impl!0;
}

private template MemberType(U) {
	template MemberType(string name) {
		alias MemberType = typeof(__traits(getMember, U, name));
	}
}

private template isMatchingType(U) {
	import std.traits : FieldTypeTuple;
	enum isMatchingType(T) = staticIndexOf!(T, FieldTypeTuple!U) >= 0;
}

private template isMatchingUniqueType(U) {
	import std.traits : staticMap;
	alias UniqueTypes = staticMap!(FieldTypeOf!U, UniqueTypeFields!U);
	template isMatchingUniqueType(T) {
		static if (is(T : TaggedAlgebraic!U)) enum isMatchingUniqueType = true;
		else enum isMatchingUniqueType = staticIndexOfImplicit!(T, UniqueTypes) >= 0;
	}
}

private template fieldMatchesType(U, T)
{
	enum fieldMatchesType(string field) = is(typeof(__traits(getMember, U, field)) == T);
}

private template FieldTypeOf(U) {
	template FieldTypeOf(string name) {
		alias FieldTypeOf = typeof(__traits(getMember, U, name));
	}
}

private template staticIndexOfImplicit(T, Types...) {
	template impl(size_t i) {
		static if (i < Types.length) {
			static if (is(T : Types[i])) enum impl = i;
			else enum impl = impl!(i+1);
		} else enum impl = -1;
	}
	enum staticIndexOfImplicit = impl!0;
}

unittest {
	static assert(staticIndexOfImplicit!(immutable(char), char) == 0);
	static assert(staticIndexOfImplicit!(int, long) == 0);
	static assert(staticIndexOfImplicit!(long, int) < 0);
	static assert(staticIndexOfImplicit!(int, int, double) == 0);
	static assert(staticIndexOfImplicit!(double, int, double) == 1);
}


private template isNoVariant(T) {
	import std.variant : Variant;
	enum isNoVariant = !is(T == Variant);
}

private void rawEmplace(T)(void[] dst, ref T src)
{
	T* tdst = () @trusted { return cast(T*)dst.ptr; } ();
	static if (is(T == class)) {
		*tdst = src;
	} else {
		import std.conv : emplace;
		emplace(tdst);
		*tdst = src;
	}
}
