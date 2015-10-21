/**
	Utility functions for data serialization

	Copyright: © 2012 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.internal.vibecompat.data.utils;

version (Have_vibe_d) {}
else:

public import std.traits;

/**
	Checks if given type is a getter function type

	Returns: `true` if argument is a getter
 */
template isPropertyGetter(T...)
	if (T.length == 1)
{
	import std.traits : functionAttributes, FunctionAttribute, ReturnType,
		isSomeFunction;
	static if (isSomeFunction!(T[0])) {
		enum isPropertyGetter =
			(functionAttributes!(T[0]) & FunctionAttribute.property) != 0
			&& !is(ReturnType!T == void);
	}
	else
		enum isPropertyGetter = false;
}

///
unittest
{
	interface Test
	{
		@property int getter();
		@property void setter(int);
		int simple();
	}

	static assert(isPropertyGetter!(typeof(&Test.getter)));
	static assert(!isPropertyGetter!(typeof(&Test.setter)));
	static assert(!isPropertyGetter!(typeof(&Test.simple)));
	static assert(!isPropertyGetter!int);
}

/**
	Checks if given type is a setter function type

	Returns: `true` if argument is a setter
 */
template isPropertySetter(T...)
	if (T.length == 1)
{
	import std.traits : functionAttributes, FunctionAttribute, ReturnType,
		isSomeFunction;

	static if (isSomeFunction!(T[0])) {
		enum isPropertySetter =
			(functionAttributes!(T) & FunctionAttribute.property) != 0
			&& is(ReturnType!(T[0]) == void);
	}
	else
		enum isPropertySetter = false;
}

///
unittest
{
	interface Test
	{
		@property int getter();
		@property void setter(int);
		int simple();
	}

	static assert(isPropertySetter!(typeof(&Test.setter)));
	static assert(!isPropertySetter!(typeof(&Test.getter)));
	static assert(!isPropertySetter!(typeof(&Test.simple)));
	static assert(!isPropertySetter!int);
}

/**
	Deduces single base interface for a type. Multiple interfaces
	will result in compile-time error.

	Params:
		T = interface or class type

	Returns:
		T if it is an interface. If T is a class, interface it implements.
*/
template baseInterface(T)
	if (is(T == interface) || is(T == class))
{
	import std.traits : InterfacesTuple;

	static if (is(T == interface)) {
		alias baseInterface = T;
	}
	else
	{
		alias Ifaces = InterfacesTuple!T;
		static assert (
			Ifaces.length == 1,
			"Type must be either provided as an interface or implement only one interface"
		);
		alias baseInterface = Ifaces[0];
	}
}

///
unittest
{
	interface I1 { }
	class A : I1 { }
	interface I2 { }
	class B : I1, I2 { }

	static assert (is(baseInterface!I1 == I1));
	static assert (is(baseInterface!A == I1));
	static assert (!is(typeof(baseInterface!B)));
}


/**
	Determins if a member is a public, non-static data field.
*/
template isRWPlainField(T, string M)
{
	static if (!isRWField!(T, M)) enum isRWPlainField = false;
	else {
		//pragma(msg, T.stringof~"."~M~":"~typeof(__traits(getMember, T, M)).stringof);
		enum isRWPlainField = __traits(compiles, *(&__traits(getMember, Tgen!T(), M)) = *(&__traits(getMember, Tgen!T(), M)));
	}
}

/**
	Determines if a member is a public, non-static, de-facto data field.

	In addition to plain data fields, R/W properties are also accepted.
*/
template isRWField(T, string M)
{
	import std.traits;
	import std.typetuple;

	static void testAssign()() {
		T t = void;
		__traits(getMember, t, M) = __traits(getMember, t, M);
	}

	// reject type aliases
	static if (is(TypeTuple!(__traits(getMember, T, M)))) enum isRWField = false;
	// reject non-public members
	else static if (!isPublicMember!(T, M)) enum isRWField = false;
	// reject static members
	else static if (!isNonStaticMember!(T, M)) enum isRWField = false;
	// reject non-typed members
	else static if (!is(typeof(__traits(getMember, T, M)))) enum isRWField = false;
	// reject void typed members (includes templates)
	else static if (is(typeof(__traits(getMember, T, M)) == void)) enum isRWField = false;
	// reject non-assignable members
	else static if (!__traits(compiles, testAssign!()())) enum isRWField = false;
	else static if (anySatisfy!(isSomeFunction, __traits(getMember, T, M))) {
		// If M is a function, reject if not @property or returns by ref
		private enum FA = functionAttributes!(__traits(getMember, T, M));
		enum isRWField = (FA & FunctionAttribute.property) != 0;
	} else {
		enum isRWField = true;
	}
}

unittest {
	import std.algorithm;

	struct S {
		alias a = int; // alias
		int i; // plain RW field
		enum j = 42; // manifest constant
		static int k = 42; // static field
		private int privateJ; // private RW field

		this(Args...)(Args args) {}

		// read-write property (OK)
		@property int p1() { return privateJ; }
		@property void p1(int j) { privateJ = j; }
		// read-only property (NO)
		@property int p2() { return privateJ; }
		// write-only property (NO)
		@property void p3(int value) { privateJ = value; }
		// ref returning property (OK)
		@property ref int p4() { return i; }
		// parameter-less template property (OK)
		@property ref int p5()() { return i; }
		// not treated as a property by DMD, so not a field
		@property int p6()() { return privateJ; }
		@property void p6(int j)() { privateJ = j; }

		static @property int p7() { return k; }
		static @property void p7(int value) { k = value; }

		ref int f1() { return i; } // ref returning function (no field)

		int f2(Args...)(Args args) { return i; }

		ref int f3(Args...)(Args args) { return i; }

		void someMethod() {}

		ref int someTempl()() { return i; }
	}

	enum plainFields = ["i"];
	enum fields = ["i", "p1", "p4", "p5"];

	foreach (mem; __traits(allMembers, S)) {
		static if (isRWField!(S, mem)) static assert(fields.canFind(mem), mem~" detected as field.");
		else static assert(!fields.canFind(mem), mem~" not detected as field.");

		static if (isRWPlainField!(S, mem)) static assert(plainFields.canFind(mem), mem~" not detected as plain field.");
		else static assert(!plainFields.canFind(mem), mem~" not detected as plain field.");
	}
}

package T Tgen(T)(){ return T.init; }


/**
	Tests if the protection of a member is public.
*/
template isPublicMember(T, string M)
{
	import std.algorithm, std.typetuple : TypeTuple;

	static if (!__traits(compiles, TypeTuple!(__traits(getMember, T, M)))) enum isPublicMember = false;
	else {
		alias MEM = TypeTuple!(__traits(getMember, T, M));
		enum _prot =  __traits(getProtection, MEM);
		enum isPublicMember = _prot == "public" || _prot == "export";
	}
}

unittest {
	class C {
		int a;
		export int b;
		protected int c;
		private int d;
		package int e;
		void f() {}
		static void g() {}
		private void h() {}
		private static void i() {}
	}

	static assert (isPublicMember!(C, "a"));
	static assert (isPublicMember!(C, "b"));
	static assert (!isPublicMember!(C, "c"));
	static assert (!isPublicMember!(C, "d"));
	static assert (!isPublicMember!(C, "e"));
	static assert (isPublicMember!(C, "f"));
	static assert (isPublicMember!(C, "g"));
	static assert (!isPublicMember!(C, "h"));
	static assert (!isPublicMember!(C, "i"));

	struct S {
		int a;
		export int b;
		private int d;
		package int e;
	}
	static assert (isPublicMember!(S, "a"));
	static assert (isPublicMember!(S, "b"));
	static assert (!isPublicMember!(S, "d"));
	static assert (!isPublicMember!(S, "e"));

	S s;
	s.a = 21;
	assert(s.a == 21);
}

/**
	Tests if a member requires $(D this) to be used.
*/
template isNonStaticMember(T, string M)
{
	import std.typetuple;
	import std.traits;

	alias MF = TypeTuple!(__traits(getMember, T, M));
	static if (M.length == 0) {
		enum isNonStaticMember = false;
	} else static if (anySatisfy!(isSomeFunction, MF)) {
		enum isNonStaticMember = !__traits(isStaticFunction, MF);
	} else {
		enum isNonStaticMember = !__traits(compiles, (){ auto x = __traits(getMember, T, M); }());
	}
}

unittest { // normal fields
	struct S {
		int a;
		static int b;
		enum c = 42;
		void f();
		static void g();
		ref int h() { return a; }
		static ref int i() { return b; }
	}
	static assert(isNonStaticMember!(S, "a"));
	static assert(!isNonStaticMember!(S, "b"));
	static assert(!isNonStaticMember!(S, "c"));
	static assert(isNonStaticMember!(S, "f"));
	static assert(!isNonStaticMember!(S, "g"));
	static assert(isNonStaticMember!(S, "h"));
	static assert(!isNonStaticMember!(S, "i"));
}

unittest { // tuple fields
	struct S(T...) {
		T a;
		static T b;
	}

	alias T = S!(int, float);
	auto p = T.b;
	static assert(isNonStaticMember!(T, "a"));
	static assert(!isNonStaticMember!(T, "b"));

	alias U = S!();
	static assert(!isNonStaticMember!(U, "a"));
	static assert(!isNonStaticMember!(U, "b"));
}


/**
	Tests if a Group of types is implicitly convertible to a Group of target types.
*/
bool areConvertibleTo(alias TYPES, alias TARGET_TYPES)()
	if (isGroup!TYPES && isGroup!TARGET_TYPES)
{
	static assert(TYPES.expand.length == TARGET_TYPES.expand.length);
	foreach (i, V; TYPES.expand)
		if (!is(V : TARGET_TYPES.expand[i]))
			return false;
	return true;
}

/// Test if the type $(D DG) is a correct delegate for an opApply where the
/// key/index is of type $(D TKEY) and the value of type $(D TVALUE).
template isOpApplyDg(DG, TKEY, TVALUE) {
	import std.traits;
	static if (is(DG == delegate) && is(ReturnType!DG : int)) {
		private alias PTT = ParameterTypeTuple!(DG);
		private alias PSCT = ParameterStorageClassTuple!(DG);
		private alias STC = ParameterStorageClass;
		// Just a value
		static if (PTT.length == 1) {
			enum isOpApplyDg = (is(PTT[0] == TVALUE) && PSCT[0] == STC.ref_);
		} else static if (PTT.length == 2) {
			enum isOpApplyDg = (is(PTT[0] == TKEY) && PSCT[0] == STC.ref_)
				&& (is(PTT[1] == TKEY) && PSCT[1] == STC.ref_);
		} else
			enum isOpApplyDg = false;
	} else {
		enum isOpApplyDg = false;
	}
}

/**
	TypeTuple which does not auto-expand.
	
	Useful when you need
	to multiple several type tuples as different template argument
	list parameters, without merging those.	
*/
template Group(T...)
{
	alias expand = T;
}

///
unittest
{
	alias group = Group!(int, double, string);
	static assert (!is(typeof(group.length)));
	static assert (group.expand.length == 3);
	static assert (is(group.expand[1] == double));
}

/**
*/
template isGroup(T...)
{
	static if (T.length != 1) enum isGroup = false;
	else enum isGroup =
		!is(T[0]) && is(typeof(T[0]) == void)      // does not evaluate to something
		&& is(typeof(T[0].expand.length) : size_t) // expands to something with length
		&& !is(typeof(&(T[0].expand)));            // expands to not addressable
}

version (unittest) // NOTE: GDC complains about template definitions in unittest blocks
{
	import std.typetuple;
	
	alias group = Group!(int, double, string);
	alias group2 = Group!();
	
	template Fake(T...)
	{
		int[] expand;
	}
	alias fake = Fake!(int, double, string);

	alias fake2 = TypeTuple!(int, double, string);

	static assert (isGroup!group);
	static assert (isGroup!group2);
	static assert (!isGroup!fake);
	static assert (!isGroup!fake2);
}

/* Copied from Phobos as it is private there.
 */
private template isSame(ab...)
    if (ab.length == 2)
{
    static if (is(ab[0]) && is(ab[1]))
    {
        enum isSame = is(ab[0] == ab[1]);
    }
    else static if (!is(ab[0]) &&
                    !is(ab[1]) &&
                    is(typeof(ab[0] == ab[1]) == bool) &&
					(ab[0] == ab[1]))
    {
        static if (!__traits(compiles, &ab[0]) ||
                   !__traits(compiles, &ab[1]))
            enum isSame = (ab[0] == ab[1]);
        else
            enum isSame = __traits(isSame, ab[0], ab[1]);
    }
    else
    {
        enum isSame = __traits(isSame, ab[0], ab[1]);
    }
}


/**
	Small convenience wrapper to find and extract certain UDA from given type.
	Will stop on first element which is of required type.

	Params:
		UDA = type or template to search for in UDA list
		Symbol = symbol to query for UDA's
		allow_types = if set to `false` considers attached `UDA` types an error
			(only accepts instances/values)

	Returns: aggregated search result struct with 3 field. `value` aliases found UDA.
		`found` is boolean flag for having a valid find. `index` is integer index in
		attribute list this UDA was found at.
*/
template findFirstUDA(alias UDA, alias Symbol, bool allow_types = false) if (!is(UDA))
{
	enum findFirstUDA = findNextUDA!(UDA, Symbol, 0, allow_types);
}

/// Ditto
template findFirstUDA(UDA, alias Symbol, bool allow_types = false)
{
	enum findFirstUDA = findNextUDA!(UDA, Symbol, 0, allow_types);
}

private struct UdaSearchResult(alias UDA)
{
	alias value = UDA;
	bool found = false;
	long index = -1;
}

/**
	Small convenience wrapper to find and extract certain UDA from given type.
	Will start at the given index and stop on the next element which is of required type.

	Params:
		UDA = type or template to search for in UDA list
		Symbol = symbol to query for UDA's
		idx = 0-based index to start at. Should be positive, and under the total number of attributes.
		allow_types = if set to `false` considers attached `UDA` types an error
			(only accepts instances/values)

	Returns: aggregated search result struct with 3 field. `value` aliases found UDA.
		`found` is boolean flag for having a valid find. `index` is integer index in
		attribute list this UDA was found at.
 */
template findNextUDA(alias UDA, alias Symbol, long idx, bool allow_types = false) if (!is(UDA))
{
	import std.traits : isInstanceOf;
	import std.typetuple : TypeTuple;

	private alias udaTuple = TypeTuple!(__traits(getAttributes, Symbol));

	static assert(idx >= 0, "Index given to findNextUDA can't be negative");
	static assert(idx <= udaTuple.length, "Index given to findNextUDA is above the number of attribute");

	public template extract(size_t index, list...)
	{
		static if (!list.length) enum extract = UdaSearchResult!(null)(false, -1);
		else {
			static if (is(list[0])) {
				static if (is(UDA) && is(list[0] == UDA) || !is(UDA) && isInstanceOf!(UDA, list[0])) {
					static assert (allow_types, "findNextUDA is designed to look up values, not types");
					enum extract = UdaSearchResult!(list[0])(true, index);
				} else enum extract = extract!(index + 1, list[1..$]);
			} else {
				static if (is(UDA) && is(typeof(list[0]) == UDA) || !is(UDA) && isInstanceOf!(UDA, typeof(list[0]))) {
					import vibe.internal.meta.traits : isPropertyGetter;
					static if (isPropertyGetter!(list[0])) {
						enum value = list[0];
						enum extract = UdaSearchResult!(value)(true, index);
					} else enum extract = UdaSearchResult!(list[0])(true, index);
				} else enum extract = extract!(index + 1, list[1..$]);
			}
		}
	}

	enum findNextUDA = extract!(idx, udaTuple[idx .. $]);
}
/// ditto
template findNextUDA(UDA, alias Symbol, long idx, bool allow_types = false)
{
	import std.traits : isInstanceOf;
	import std.typetuple : TypeTuple;

	private alias udaTuple = TypeTuple!(__traits(getAttributes, Symbol));

	static assert(idx >= 0, "Index given to findNextUDA can't be negative");
	static assert(idx <= udaTuple.length, "Index given to findNextUDA is above the number of attribute");

	public template extract(size_t index, list...)
	{
		static if (!list.length) enum extract = UdaSearchResult!(null)(false, -1);
		else {
			static if (is(list[0])) {
				static if (is(list[0] == UDA)) {
					static assert (allow_types, "findNextUDA is designed to look up values, not types");
					enum extract = UdaSearchResult!(list[0])(true, index);
				} else enum extract = extract!(index + 1, list[1..$]);
			} else {
				static if (is(typeof(list[0]) == UDA)) {
					static if (isPropertyGetter!(list[0])) {
						enum value = list[0];
						enum extract = UdaSearchResult!(value)(true, index);
					} else enum extract = UdaSearchResult!(list[0])(true, index);
				} else enum extract = extract!(index + 1, list[1..$]);
			}
		}
    }

	enum findNextUDA = extract!(idx, udaTuple[idx .. $]);
}


///
unittest
{
	struct Attribute { int x; }

	@("something", Attribute(42), Attribute(41))
	void symbol();

	enum result0 = findNextUDA!(string, symbol, 0);
	static assert (result0.found);
	static assert (result0.index == 0);
	static assert (result0.value == "something");

	enum result1 = findNextUDA!(Attribute, symbol, 0);
	static assert (result1.found);
	static assert (result1.index == 1);
	static assert (result1.value == Attribute(42));

	enum result2 = findNextUDA!(int, symbol, 0);
	static assert (!result2.found);

	enum result3 = findNextUDA!(Attribute, symbol, result1.index + 1);
	static assert (result3.found);
	static assert (result3.index == 2);
	static assert (result3.value == Attribute(41));
}

unittest
{
	struct Attribute { int x; }

	@(Attribute) void symbol();

	static assert (!is(findNextUDA!(Attribute, symbol, 0)));

	enum result0 = findNextUDA!(Attribute, symbol, 0, true);
	static assert (result0.found);
	static assert (result0.index == 0);
	static assert (is(result0.value == Attribute));
}

unittest
{
	struct Attribute { int x; }
	enum Dummy;

	@property static Attribute getter()
	{
		return Attribute(42);
	}

	@Dummy @getter void symbol();

	enum result0 = findNextUDA!(Attribute, symbol, 0);
	static assert (result0.found);
	static assert (result0.index == 1);
	static assert (result0.value == Attribute(42));
}

/// Eager version of findNextUDA that represent all instances of UDA in a Tuple.
/// If one of the attribute is a type instead of an instance, compilation will fail.
template UDATuple(alias UDA, alias Sym) {
	import std.typetuple : TypeTuple;

	private template extract(size_t maxSize, Founds...)
	{
		private alias LastFound = Founds[$ - 1];
		// No more to find
		static if (!LastFound.found)
			enum extract = Founds[0 .. $ - 1];
		else {
			// For ease of use, this is a Tuple of UDA, not a tuple of UdaSearchResult!(...)
			private alias Result = TypeTuple!(Founds[0 .. $ - 1], LastFound.value);
			// We're at the last parameter
			static if (LastFound.index == maxSize)
				enum extract = Result;
			else
				enum extract = extract!(maxSize, Result, findNextUDA!(UDA, Sym, LastFound.index + 1));
		}
	}

	private enum maxIndex = TypeTuple!(__traits(getAttributes, Sym)).length;
	enum UDATuple = extract!(maxIndex, findNextUDA!(UDA, Sym, 0));
}

unittest
{
	import std.typetuple : TypeTuple;

	struct Attribute { int x; }
	enum Dummy;

	@(Dummy, Attribute(21), Dummy, Attribute(42), Attribute(84)) void symbol() {}
	@(Dummy, Attribute(21), Dummy, Attribute(42), Attribute) void wrong() {}

	alias Cmp = TypeTuple!(Attribute(21), Attribute(42), Attribute(84));
	static assert(Cmp == UDATuple!(Attribute, symbol));
	static assert(!is(UDATuple!(Attribute, wrong)));
}

/// Avoid repeating the same error message again and again.
/// ----
/// if (!__ctfe)
///	assert(0, onlyAsUda!func);
/// ----
template onlyAsUda(string from /*= __FUNCTION__*/)
{
	// With default param, DMD think expression is void, even when writing 'enum string onlyAsUda = ...'
	enum onlyAsUda = from~" must only be used as an attribute - not called as a runtime function.";
}
