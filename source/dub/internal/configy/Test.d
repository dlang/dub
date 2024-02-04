/*******************************************************************************
    Contains all the tests for this library.

    Copyright:
        Copyright (c) 2019-2022 BOSAGORA Foundation
        All rights reserved.

    License:
        MIT License. See LICENSE for details.

*******************************************************************************/

module dub.internal.configy.Test;

import dub.internal.configy.Attributes;
import dub.internal.configy.Exceptions;
import dub.internal.configy.Read;
import dub.internal.configy.Utils;

import dub.internal.dyaml.node;

import std.format;

import core.time;

/// Basic usage tests
unittest
{
    static struct Address
    {
        string address;
        string city;
        bool accessible;
    }

    static struct Nested
    {
        Address address;
    }

    static struct Config
    {
        bool enabled = true;

        string name = "Jessie";
        int age = 42;
        double ratio = 24.42;

        Address address = { address: "Yeoksam-dong", city: "Seoul", accessible: true };

        Nested nested = { address: { address: "Gangnam-gu", city: "Also Seoul", accessible: false } };
    }

    auto c1 = parseConfigString!Config("enabled: false", "/dev/null");
    assert(!c1.enabled);
    assert(c1.name == "Jessie");
    assert(c1.age == 42);
    assert(c1.ratio == 24.42);

    assert(c1.address.address == "Yeoksam-dong");
    assert(c1.address.city == "Seoul");
    assert(c1.address.accessible);

    assert(c1.nested.address.address == "Gangnam-gu");
    assert(c1.nested.address.city == "Also Seoul");
    assert(!c1.nested.address.accessible);
}

// Tests for SetInfo
unittest
{
    static struct Address
    {
        string address;
        string city;
        bool accessible;
    }

    static struct Config
    {
        SetInfo!int value;
        SetInfo!int answer = 42;
        SetInfo!string name = SetInfo!string("Lorene", false);

        SetInfo!Address address;
    }

    auto c1 = parseConfigString!Config("value: 24", "/dev/null");
    assert(c1.value == 24);
    assert(c1.value.set);

    assert(c1.answer.set);
    assert(c1.answer == 42);

    assert(!c1.name.set);
    assert(c1.name == "Lorene");

    assert(!c1.address.set);

    auto c2 = parseConfigString!Config(`
name: Lorene
address:
  address: Somewhere
  city:    Over the rainbow
`, "/dev/null");

    assert(!c2.value.set);
    assert(c2.name == "Lorene");
    assert(c2.name.set);
    assert(c2.address.set);
    assert(c2.address.address == "Somewhere");
    assert(c2.address.city == "Over the rainbow");
}

unittest
{
    static struct Nested { core.time.Duration timeout; }
    static struct Config { Nested node; }

    try
    {
        auto result = parseConfigString!Config("node:\n  timeout:", "/dev/null");
        assert(0);
    }
    catch (Exception exc)
    {
        assert(exc.toString() == "/dev/null(1:10): node.timeout: Field is of type scalar, " ~
               "but expected a mapping with at least one of: weeks, days, hours, minutes, " ~
               "seconds, msecs, usecs, hnsecs, nsecs");
    }

    {
        auto result = parseConfigString!Nested("timeout:\n  days: 10\n  minutes: 100\n  hours: 3\n", "/dev/null");
        assert(result.timeout == 10.days + 4.hours + 40.minutes);
    }
}

unittest
{
    static struct Config { string required; }
    try
        auto result = parseConfigString!Config("value: 24", "/dev/null");
    catch (ConfigException e)
    {
        assert(format("%s", e) ==
               "/dev/null(0:0): value: Key is not a valid member of this section. There are 1 valid keys: required");
        assert(format("%S", e) ==
               format("%s/dev/null%s(%s0%s:%s0%s): %svalue%s: Key is not a valid member of this section. " ~
                      "There are %s1%s valid keys: %srequired%s", Yellow, Reset, Cyan, Reset, Cyan, Reset,
                      Yellow, Reset, Yellow, Reset, Green, Reset));
    }
}

// Test for various type errors
unittest
{
    static struct Mapping
    {
        string value;
    }

    static struct Config
    {
        @Optional Mapping map;
        @Optional Mapping[] array;
        int scalar;
    }

    try
    {
        auto result = parseConfigString!Config("map: Hello World", "/dev/null");
        assert(0);
    }
    catch (ConfigException exc)
    {
        assert(exc.toString() == "/dev/null(0:5): map: Expected to be of type mapping (object), but is a scalar");
    }

    try
    {
        auto result = parseConfigString!Config("map:\n  - Hello\n  - World", "/dev/null");
        assert(0);
    }
    catch (ConfigException exc)
    {
        assert(exc.toString() == "/dev/null(1:2): map: Expected to be of type mapping (object), but is a sequence");
    }

    try
    {
        auto result = parseConfigString!Config("scalar:\n  - Hello\n  - World", "/dev/null");
        assert(0);
    }
    catch (ConfigException exc)
    {
        assert(exc.toString() == "/dev/null(1:2): scalar: Expected to be of type scalar (value), but is a sequence");
    }

    try
    {
        auto result = parseConfigString!Config("scalar:\n  hello:\n    World", "/dev/null");
        assert(0);
    }
    catch (ConfigException exc)
    {
        assert(exc.toString() == "/dev/null(1:2): scalar: Expected to be of type scalar (value), but is a mapping");
    }
}

// Test for strict mode
unittest
{
    static struct Config
    {
        string value;
        string valhu;
        string halvue;
    }

    try
    {
        auto result = parseConfigString!Config("valeu: This is a typo", "/dev/null");
        assert(0);
    }
    catch (ConfigException exc)
    {
        assert(exc.toString() == "/dev/null(0:0): valeu: Key is not a valid member of this section. Did you mean: value, valhu");
    }
}

// Test for required key
unittest
{
    static struct Nested
    {
        string required;
        string optional = "Default";
    }

    static struct Config
    {
        Nested inner;
    }

    try
    {
        auto result = parseConfigString!Config("inner:\n  optional: Not the default value", "/dev/null");
        assert(0);
    }
    catch (ConfigException exc)
    {
        assert(exc.toString() == "/dev/null(1:2): inner.required: Required key was not found in configuration or command line arguments");
    }
}

// Testing 'validate()' on nested structures
unittest
{
    __gshared int validateCalls0 = 0;
    __gshared int validateCalls1 = 1;
    __gshared int validateCalls2 = 2;

    static struct SecondLayer
    {
        string value = "default";

        public void validate () const
        {
            validateCalls2++;
        }
    }

    static struct FirstLayer
    {
        bool enabled = true;
        SecondLayer ltwo;

        public void validate () const
        {
            validateCalls1++;
        }
    }

    static struct Config
    {
        FirstLayer lone;

        public void validate () const
        {
            validateCalls0++;
        }
    }

    auto r1 = parseConfigString!Config("lone:\n  ltwo:\n    value: Something\n", "/dev/null");

    assert(r1.lone.ltwo.value == "Something");
    // `validateCalls` are given different value to avoid false-positive
    // if they are set to 0 / mixed up
    assert(validateCalls0 == 1);
    assert(validateCalls1 == 2);
    assert(validateCalls2 == 3);

    auto r2 = parseConfigString!Config("lone:\n  enabled: false\n", "/dev/null");
    assert(validateCalls0 == 2); // + 1
    assert(validateCalls1 == 2); // Other are disabled
    assert(validateCalls2 == 3);
}

// Test the throwing ctor / fromString
unittest
{
    static struct ThrowingFromString
    {
        public static ThrowingFromString fromString (scope const(char)[] value)
            @safe pure
        {
            throw new Exception("Some meaningful error message");
        }

        public int value;
    }

    static struct ThrowingCtor
    {
        public this (scope const(char)[] value)
            @safe pure
        {
            throw new Exception("Something went wrong... Obviously");
        }

        public int value;
    }

    static struct InnerConfig
    {
        public int value;
        @Optional ThrowingCtor ctor;
        @Optional ThrowingFromString fromString;

        @Converter!int(
            (scope ConfigParser!int parser) {
                // We have to trick DMD a bit so that it infers an `int` return
                // type but doesn't emit a "Statement is not reachable" warning
                if (parser.node is Node.init || parser.node !is Node.init )
                    throw new Exception("You shall not pass");
                return 42;
            })
        @Optional int converter;
    }

    static struct Config
    {
        public InnerConfig config;
    }

    try
    {
        auto result = parseConfigString!Config("config:\n  value: 42\n  ctor: 42", "/dev/null");
        assert(0);
    }
    catch (ConfigException exc)
    {
        assert(exc.toString() == "/dev/null(2:8): config.ctor: Something went wrong... Obviously");
    }

    try
    {
        auto result = parseConfigString!Config("config:\n  value: 42\n  fromString: 42", "/dev/null");
        assert(0);
    }
    catch (ConfigException exc)
    {
        assert(exc.toString() == "/dev/null(2:14): config.fromString: Some meaningful error message");
    }

    try
    {
        auto result = parseConfigString!Config("config:\n  value: 42\n  converter: 42", "/dev/null");
        assert(0);
    }
    catch (ConfigException exc)
    {
        assert(exc.toString() == "/dev/null(2:13): config.converter: You shall not pass");
    }

    // We also need to test with arrays, to ensure they are correctly called
    static struct InnerArrayConfig
    {
        @Optional int value;
        @Optional ThrowingCtor ctor;
        @Optional ThrowingFromString fromString;
    }

    static struct ArrayConfig
    {
        public InnerArrayConfig[] configs;
    }

    try
    {
        auto result = parseConfigString!ArrayConfig("configs:\n  - ctor: something", "/dev/null");
        assert(0);
    }
    catch (ConfigException exc)
    {
        assert(exc.toString() == "/dev/null(1:10): configs[0].ctor: Something went wrong... Obviously");
    }

    try
    {
        auto result = parseConfigString!ArrayConfig(
            "configs:\n  - value: 42\n  - fromString: something", "/dev/null");
        assert(0);
    }
    catch (ConfigException exc)
    {
        assert(exc.toString() == "/dev/null(2:16): configs[1].fromString: Some meaningful error message");
    }
}

// Test duplicate fields detection
unittest
{
    static struct Config
    {
        @Name("shadow") int value;
        @Name("value")  int shadow;
    }

    auto result = parseConfigString!Config("shadow: 42\nvalue: 84\n", "/dev/null");
    assert(result.value  == 42);
    assert(result.shadow == 84);

    static struct BadConfig
    {
        int value;
        @Name("value") int something;
    }

    // Cannot test the error message, so this is as good as it gets
    static assert(!is(typeof(() {
                    auto r = parseConfigString!BadConfig("shadow: 42\nvalue: 84\n", "/dev/null");
                })));
}

// Test a renamed `enabled` / `disabled`
unittest
{
    static struct ConfigA
    {
        @Name("enabled") bool shouldIStay;
        int value;
    }

    static struct ConfigB
    {
        @Name("disabled") bool orShouldIGo;
        int value;
    }

    {
        auto c = parseConfigString!ConfigA("enabled: true\nvalue: 42", "/dev/null");
        assert(c.shouldIStay == true);
        assert(c.value == 42);
    }

    {
        auto c = parseConfigString!ConfigB("disabled: false\nvalue: 42", "/dev/null");
        assert(c.orShouldIGo == false);
        assert(c.value == 42);
    }
}

// Test for 'mightBeOptional' & missing key
unittest
{
    static struct RequestLimit { size_t reqs = 100; }
    static struct Nested       { @Name("jay") int value; }
    static struct Config { @Name("chris") Nested value; RequestLimit limits; }

    auto r = parseConfigString!Config("chris:\n  jay: 42", "/dev/null");
    assert(r.limits.reqs == 100);

    try
    {
        auto _ = parseConfigString!Config("limits:\n  reqs: 42", "/dev/null");
    }
    catch (ConfigException exc)
    {
        assert(exc.toString() == "(0:0): chris.jay: Required key was not found in configuration or command line arguments");
    }
}

// Support for associative arrays
unittest
{
    static struct Nested
    {
        int[string] answers;
    }

    static struct Parent
    {
        Nested[string] questions;
        string[int] names;
    }

    auto c = parseConfigString!Parent(
`names:
  42: "Forty two"
  97: "Quatre vingt dix sept"
questions:
  first:
    answers:
      # Need to use quotes here otherwise it gets interpreted as
      # true / false, perhaps a dyaml issue ?
      'yes': 42
      'no':  24
  second:
    answers:
      maybe:  69
      whynot: 20
`, "/dev/null");

    assert(c.names == [42: "Forty two", 97: "Quatre vingt dix sept"]);
    assert(c.questions.length == 2);
    assert(c.questions["first"] == Nested(["yes": 42, "no": 24]));
    assert(c.questions["second"] == Nested(["maybe": 69, "whynot": 20]));
}

unittest
{
    static struct FlattenMe
    {
        int value;
        string name;
    }

    static struct Config
    {
        FlattenMe flat = FlattenMe(24, "Four twenty");
        alias flat this;

        FlattenMe not_flat;
    }

    auto c = parseConfigString!Config(
        "value: 42\nname: John\nnot_flat:\n  value: 69\n  name: Henry",
        "/dev/null");
    assert(c.flat.value == 42);
    assert(c.flat.name == "John");
    assert(c.not_flat.value == 69);
    assert(c.not_flat.name == "Henry");

    auto c2 = parseConfigString!Config(
        "not_flat:\n  value: 69\n  name: Henry", "/dev/null");
    assert(c2.flat.value == 24);
    assert(c2.flat.name == "Four twenty");

    static struct OptConfig
    {
        @Optional FlattenMe flat;
        alias flat this;

        int value;
    }
    auto c3 = parseConfigString!OptConfig("value: 69\n", "/dev/null");
    assert(c3.value == 69);
}

unittest
{
    static struct Config
    {
        @Name("names")
        string[] names_;

        size_t names () const scope @safe pure nothrow @nogc
        {
            return this.names_.length;
        }
    }

    auto c = parseConfigString!Config("names:\n  - John\n  - Luca\n", "/dev/null");
    assert(c.names_ == [ "John", "Luca" ]);
    assert(c.names == 2);
}

unittest
{
    static struct BuildTemplate
    {
        string targetName;
        string platform;
    }
    static struct BuildConfig
    {
        BuildTemplate config;
        alias config this;
    }
    static struct Config
    {
        string name;

        @Optional BuildConfig config;
        alias config this;
    }

    auto c = parseConfigString!Config("name: dummy\n", "/dev/null");
    assert(c.name == "dummy");

    auto c2 = parseConfigString!Config("name: dummy\nplatform: windows\n", "/dev/null");
    assert(c2.name == "dummy");
    assert(c2.config.platform == "windows");
}

// Make sure unions don't compile
unittest
{
    static union MyUnion
    {
        string value;
        int number;
    }

    static struct Config
    {
        MyUnion hello;
    }

    static assert(!is(typeof(parseConfigString!Config("hello: world\n", "/dev/null"))));
    static assert(!is(typeof(parseConfigString!MyUnion("hello: world\n", "/dev/null"))));
}

// Test the `@Key` attribute
unittest
{
    static struct Interface
    {
        string name;
        string static_ip;
    }

    static struct Config
    {
        string profile;

        @Key("name")
        immutable(Interface)[] ifaces = [
            Interface("lo", "127.0.0.1"),
        ];
    }

    auto c = parseConfigString!Config(`profile: default
ifaces:
  eth0:
    static_ip: "192.168.1.42"
  lo:
    static_ip: "127.0.0.42"
`, "/dev/null");
    assert(c.ifaces.length == 2);
    assert(c.ifaces == [ Interface("eth0", "192.168.1.42"), Interface("lo", "127.0.0.42")]);
}

// Nested ConstructionException
unittest
{
    static struct WillFail
    {
        string name;
        this (string value) @safe pure
        {
            throw new Exception("Parsing failed!");
        }
    }

    static struct Container
    {
        WillFail[] array;
    }

    static struct Config
    {
        Container data;
    }

    try auto c = parseConfigString!Config(`data:
  array:
    - Not
    - Working
`, "/dev/null");
    catch (Exception exc)
        assert(exc.toString() == `/dev/null(2:6): data.array[0]: Parsing failed!`);
}

/// Test for error message: Has to be versioned out, uncomment to check manually
unittest
{
    static struct Nested
    {
        int field1;

        private this (string arg) {}
    }

    static struct Config
    {
        Nested nested;
    }

    static struct Config2
    {
        Nested nested;
        alias nested this;
    }

    version(none) auto c1 = parseConfigString!Config(null, null);
    version(none) auto c2 = parseConfigString!Config2(null, null);
}

/// Test support for `fromYAML` hook
unittest
{
    static struct PackageDef
    {
        string name;
        @Optional string target;
        int build = 42;
    }

    static struct Package
    {
        string path;
        PackageDef def;

        public static Package fromYAML (scope ConfigParser!Package parser)
        {
            if (parser.node.nodeID == NodeID.mapping)
                return Package(null, parser.parseAs!PackageDef);
            else
                return Package(parser.parseAs!string);
        }
    }

    static struct Config
    {
        string name;
        Package[] deps;
    }

    auto c = parseConfigString!Config(
`
name: myPkg
deps:
  - /foo/bar
  - name: foo
    target: bar
    build: 24
  - name: fur
  - /one/last/path
`, "/dev/null");
    assert(c.name == "myPkg");
    assert(c.deps.length == 4);
    assert(c.deps[0] == Package("/foo/bar"));
    assert(c.deps[1] == Package(null, PackageDef("foo", "bar", 24)));
    assert(c.deps[2] == Package(null, PackageDef("fur", null, 42)));
    assert(c.deps[3] == Package("/one/last/path"));
}

/// Test top level hook (fromYAML / fromString)
unittest
{
    static struct Version1 {
        uint fileVersion;
        uint value;
    }

    static struct Version2 {
        uint fileVersion;
        string str;
    }

    static struct Config
    {
        uint fileVersion;
        union {
            Version1 v1;
            Version2 v2;
        }
        static Config fromYAML (scope ConfigParser!Config parser)
        {
            static struct OnlyVersion { uint fileVersion; }
            auto vers = parseConfig!OnlyVersion(
                CLIArgs.init, parser.node, StrictMode.Ignore);
            switch (vers.fileVersion) {
            case 1:
                return Config(1, parser.parseAs!Version1);
            case 2:
                Config conf = Config(2);
                conf.v2 = parser.parseAs!Version2;
                return conf;
            default:
                assert(0);
            }
        }
    }

    auto v1 = parseConfigString!Config("fileVersion: 1\nvalue: 42", "/dev/null");
    auto v2 = parseConfigString!Config("fileVersion: 2\nstr: hello world", "/dev/null");

    assert(v1.fileVersion == 1);
    assert(v1.v1.fileVersion == 1);
    assert(v1.v1.value == 42);

    assert(v2.fileVersion == 2);
    assert(v2.v2.fileVersion == 2);
    assert(v2.v2.str == "hello world");
}

/// Don't call `opCmp` / `opEquals` as they might not be CTFEable
/// Also various tests around static arrays
unittest
{
    static struct NonCTFEAble
    {
        int value;

        public bool opEquals (const NonCTFEAble other) const scope
        {
            assert(0);
        }

        public bool opEquals (const ref NonCTFEAble other) const scope
        {
            assert(0);
        }

        public int opCmp (const NonCTFEAble other) const scope
        {
            assert(0);
        }

        public int opCmp (const ref NonCTFEAble other) const scope
        {
            assert(0);
        }
    }

    static struct Config
    {
        NonCTFEAble fixed;
        @Name("static") NonCTFEAble[3] static_;
        NonCTFEAble[] dynamic;
    }

    auto c = parseConfigString!Config(`fixed:
  value: 42
static:
  - value: 84
  - value: 126
  - value: 168
dynamic:
  - value: 420
  - value: 840
`, "/dev/null");

    assert(c.fixed.value == 42);
    assert(c.static_[0].value == 84);
    assert(c.static_[1].value == 126);
    assert(c.static_[2].value == 168);
    assert(c.dynamic.length == 2);
    assert(c.dynamic[0].value == 420);
    assert(c.dynamic[1].value == 840);

    try parseConfigString!Config(`fixed:
  value: 42
dynamic:
  - value: 420
  - value: 840
`, "/dev/null");
    catch (ConfigException e)
        assert(e.toString() == "/dev/null(0:0): static: Required key was not found in configuration or command line arguments");

    try parseConfigString!Config(`fixed:
  value: 42
static:
  - value: 1
  - value: 2
dynamic:
  - value: 420
  - value: 840
`, "/dev/null");
    catch (ConfigException e)
        assert(e.toString() == "/dev/null(3:2): static: Too few entries for sequence: Expected 3, got 2");

    try parseConfigString!Config(`fixed:
  value: 42
static:
  - value: 1
  - value: 2
  - value: 3
  - value: 4
dynamic:
  - value: 420
  - value: 840
`, "/dev/null");
    catch (ConfigException e)
        assert(e.toString() == "/dev/null(3:2): static: Too many entries for sequence: Expected 3, got 4");

    // Check that optional static array work
    static struct ConfigOpt
    {
        NonCTFEAble fixed;
        @Name("static") NonCTFEAble[3] static_ = [
            NonCTFEAble(69),
            NonCTFEAble(70),
            NonCTFEAble(71),
        ];
    }

    auto c1 = parseConfigString!ConfigOpt(`fixed:
  value: 1100
`, "/dev/null");

    assert(c1.fixed.value == 1100);
    assert(c1.static_[0].value == 69);
    assert(c1.static_[1].value == 70);
    assert(c1.static_[2].value == 71);
}
