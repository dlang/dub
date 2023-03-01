/*******************************************************************************

    Utilities to fill a struct representing the configuration with the content
    of a YAML document.

    The main function of this module is `parseConfig`. Convenience functions
    `parseConfigString` and `parseConfigFile` are also available.

    The type parameter to those three functions must be a struct and is used
    to drive the processing of the YAML node. When an error is encountered,
    an `Exception` will be thrown, with a descriptive message.
    The rules by which the struct is filled are designed to be
    as intuitive as possible, and are described below.

    Optional_Fields:
      One of the major convenience offered by this utility is its handling
      of optional fields. A field is detected as optional if it has
      an initializer that is different from its type `init` value,
      for example `string field = "Something";` is an optional field,
      but `int count = 0;` is not.
      To mark a field as optional even with its default value,
      use the `Optional` UDA: `@Optional int count = 0;`.

    Converter:
      Because config structs may contain complex types such as
      a Phobos type, a user-defined `Amount`, or Vibe.d's `URL`,
      one may need to apply a converter to a struct's field.
      Converters are functions that take a YAML `Node` as argument
      and return a type that is implicitly convertible to the field type
      (usually just the field type). They offer the most power to users,
      as they can inspect the YAML structure, but should be used as a last resort.

    Composite_Types:
      Processing starts from a `struct` at the top level, and recurse into
      every fields individually. If a field is itself a struct,
      the filler will attempt the following, in order:
      - If the field has no value and is not optional, an Exception will
        be thrown with an error message detailing where the issue happened.
      - If the field has no value and is optional, the default value will
        be used.
      - If the field has a value, the filler will first check for a converter
        and use it if present.
      - If the type has a `static` method named `fromString` whose sole argument
        is a `string`, it will be used.
      - If the type has a constructor whose sole argument is a `string`,
        it will be used;
      - Finally, the filler will attempt to deserialize all struct members
        one by one and pass them to the default constructor, if there is any.
      - If none of the above succeeded, a `static assert` will trigger.

    Alias_this:
      If a `struct` contains an `alias this`, the field that is aliased will be
      ignored, instead the config parser will parse nested fields as if they
      were part of the enclosing structure. This allow to re-use a single `struct`
      in multiple place without having to resort to a `mixin template`.
      Having an initializer will make all fields in the aliased struct optional.
      The aliased field cannot have attributes other than `@Optional`,
      which will then apply to all fields it exposes.

    Duration_parsing:
      If the config field is of type `core.time.Duration`, special parsing rules
      will apply. There are two possible forms in which a Duration field may
      be expressed. In the first form, the YAML node should be a mapping,
      and it will be checked for fields matching the supported units
      in `core.time`: `weeks`, `days`, `hours`, `minutes`, `seconds`, `msecs`,
      `usecs`, `hnsecs`, `nsecs`. Strict parsing option will be respected.
      The values of the fields will then be added together, so the following
      YAML usages are equivalent:
      ---
      // sleepFor:
      //   hours: 8
      //   minutes: 30
      ---
      and:
      ---
      // sleepFor:
      //   minutes: 510
      ---
      Provided that the definition of the field is:
      ---
      public Duration sleepFor;
      ---

      In the second form, the field should have a suffix composed of an
      underscore ('_'), followed by a unit name as defined in `core.time`.
      This can be either the field name directly, or a name override.
      The latter is recommended to avoid confusion when using the field in code.
      In this form, the YAML node is expected to be a scalar.
      So the previous example, using this form, would be expressed as:
      ---
      sleepFor_minutes: 510
      ---
      and the field definition should be one of those two:
      ---
      public @Name("sleepFor_minutes") Duration sleepFor; /// Prefer this
      public Duration sleepFor_minutes; /// This works too
      ---

      Those forms are mutually exclusive, so a field with a unit suffix
      will error out if a mapping is used. This prevents surprises and ensures
      that the error message, if any, is consistent across user input.

      To disable or change this behavior, one may use a `Converter` instead.

    Strict_Parsing:
      When strict parsing is enabled, the config filler will also validate
      that the YAML nodes do not contains entry which are not present in the
      mapping (struct) being processed.
      This can be useful to catch typos or outdated configuration options.

    Post_Validation:
      Some configuration will require validation across multiple sections.
      For example, two sections may be mutually exclusive as a whole,
      or may have fields which are mutually exclusive with another section's
      field(s). This kind of dependence is hard to account for declaratively,
      and does not affect parsing. For this reason, the preferred way to
      handle those cases is to define a `validate` member method on the
      affected config struct(s), which will be called once
      parsing for that mapping is completed.
      If an error is detected, this method should throw an Exception.

    Enabled_or_disabled_field:
      While most complex logic validation should be handled post-parsing,
      some section may be optional by default, but if provided, will have
      required fields. To support this use case, if a field with the name
      `enabled` is present in a struct, the parser will first process it.
      If it is `false`, the parser will not attempt to process the struct
      further, and the other fields will have their default value.
      Likewise, if a field named `disabled` exists, the struct will not
      be processed if it is set to `true`.

    Copyright:
        Copyright (c) 2019-2022 BOSAGORA Foundation
        All rights reserved.

    License:
        MIT License. See LICENSE for details.

*******************************************************************************/

module dub.internal.configy.Read;

public import dub.internal.configy.Attributes;
public import dub.internal.configy.Exceptions : ConfigException;
import dub.internal.configy.Exceptions;
import dub.internal.configy.FieldRef;
import dub.internal.configy.Utils;

import dub.internal.dyaml.exception;
import dub.internal.dyaml.node;
import dub.internal.dyaml.loader;

import std.algorithm;
import std.conv;
import std.datetime;
import std.format;
import std.getopt;
import std.meta;
import std.range;
import std.traits;
import std.typecons : Nullable, nullable, tuple;

static import core.time;

// Dub-specific adjustments for output
import dub.internal.logging;

/// Command-line arguments
public struct CLIArgs
{
    /// Path to the config file
    public string config_path = "config.yaml";

    /// Overrides for config options
    public string[][string] overrides;

    /// Helper to add items to `overrides`
    public void overridesHandler (string, string value)
    {
        import std.string;
        const idx = value.indexOf('=');
        if (idx < 0) return;
        string k = value[0 .. idx], v = value[idx + 1 .. $];
        if (auto val = k in this.overrides)
            (*val) ~= v;
        else
            this.overrides[k] = [ v ];
    }

    /***************************************************************************

        Parses the base command line arguments

        This can be composed with the program argument.
        For example, consider a program which wants to expose a `--version`
        switch, the definition could look like this:
        ---
        public struct ProgramCLIArgs
        {
            public CLIArgs base; // This struct

            public alias base this; // For convenience

            public bool version_; // Program-specific part
        }
        ---
        Then, an application-specific configuration routine would be:
        ---
        public GetoptResult parse (ref ProgramCLIArgs clargs, ref string[] args)
        {
            auto r = clargs.base.parse(args);
            if (r.helpWanted) return r;
            return getopt(
                args,
                "version", "Print the application version, &clargs.version_");
        }
        ---

        Params:
          args = The command line args to parse (parsed options will be removed)
          passThrough = Whether to enable `config.passThrough` and
                        `config.keepEndOfOptions`. `true` by default, to allow
                        composability. If your program doesn't have other
                        arguments, pass `false`.

        Returns:
          The result of calling `getopt`

    ***************************************************************************/

    public GetoptResult parse (ref string[] args, bool passThrough = true)
    {
        return getopt(
            args,
            // `caseInsensitive` is the default, but we need something
            // with the same type for the ternary
            passThrough ? config.keepEndOfOptions : config.caseInsensitive,
            // Also the default, same reasoning
            passThrough ? config.passThrough : config.noPassThrough,
            "config|c",
                "Path to the config file. Defaults to: " ~ this.config_path,
                &this.config_path,

            "override|O",
                "Override a config file value\n" ~
                "Example: -O foo.bar=true -o dns=1.1.1.1 -o dns=2.2.2.2\n" ~
                "Array values are additive, other items are set to the last override",
                &this.overridesHandler,
        );
    }
}

/*******************************************************************************

    Attempt to read and process the config file at `path`, print any error

    This 'simple' overload of the more detailed `parseConfigFile` will attempt
    to read the file at `path`, and return a `Nullable` instance of it.
    If an error happens, either because the file isn't readable or
    the configuration has an issue, a message will be printed to `stderr`,
    with colors if the output is a TTY, and a `null` instance will be returned.

    The calling code can hence just read a config file via:
    ```
    int main ()
    {
        auto configN = parseConfigFileSimple!Config("config.yaml");
        if (configN.isNull()) return 1; // Error path
        auto config = configN.get();
        // Rest of the program ...
    }
    ```
    An overload accepting `CLIArgs args` also exists.

    Params:
        path = Path of the file to read from
        args = Command line arguments on which `parse` has been called
        strict = Whether the parsing should reject unknown keys in the
                 document, warn, or ignore them (default: `StrictMode.Error`)

    Returns:
        An initialized `Config` instance if reading/parsing was successful;
        a `null` instance otherwise.

*******************************************************************************/

public Nullable!T parseConfigFileSimple (T) (string path, StrictMode strict = StrictMode.Error)
{
    return parseConfigFileSimple!(T)(CLIArgs(path), strict);
}


/// Ditto
public Nullable!T parseConfigFileSimple (T) (in CLIArgs args, StrictMode strict = StrictMode.Error)
{
    try
    {
        Node root = Loader.fromFile(args.config_path).load();
        return nullable(parseConfig!T(args, root, strict));
    }
    catch (ConfigException exc)
    {
        exc.printException();
        return typeof(return).init;
    }
    catch (Exception exc)
    {
        // Other Exception type may be thrown by D-YAML,
        // they won't include rich information.
        logWarn("%s", exc.message());
        return typeof(return).init;
    }
}

/*******************************************************************************

    Print an Exception, potentially with colors on

    Trusted because of `stderr` usage.

*******************************************************************************/

private void printException (scope ConfigException exc) @trusted
{
    import dub.internal.logging;

    if (hasColors)
        logWarn("%S", exc);
    else
        logWarn("%s", exc.message());
}

/*******************************************************************************

    Parses the config file or string and returns a `Config` instance.

    Params:
        cmdln = command-line arguments (containing the path to the config)
        path = When parsing a string, the path corresponding to it
        strict = Whether the parsing should reject unknown keys in the
                 document, warn, or ignore them (default: `StrictMode.Error`)

    Throws:
        `Exception` if parsing the config file failed.

    Returns:
        `Config` instance

*******************************************************************************/

public T parseConfigFile (T) (in CLIArgs cmdln, StrictMode strict = StrictMode.Error)
{
    Node root = Loader.fromFile(cmdln.config_path).load();
    return parseConfig!T(cmdln, root, strict);
}

/// ditto
public T parseConfigString (T) (string data, string path, StrictMode strict = StrictMode.Error)
{
    CLIArgs cmdln = { config_path: path };
    auto loader = Loader.fromString(data);
    loader.name = path;
    Node root = loader.load();
    return parseConfig!T(cmdln, root, strict);
}

/*******************************************************************************

    Process the content of the YAML document described by `node` into an
    instance of the struct `T`.

    See the module description for a complete overview of this function.

    Params:
      T = Type of the config struct to fill
      cmdln = Command line arguments
      node = The root node matching `T`
      strict = Action to take when encountering unknown keys in the document

    Returns:
      An instance of `T` filled with the content of `node`

    Throws:
      If the content of `node` cannot satisfy the requirements set by `T`,
      or if `node` contain extra fields and `strict` is `true`.

*******************************************************************************/

public T parseConfig (T) (
    in CLIArgs cmdln, Node node, StrictMode strict = StrictMode.Error)
{
    static assert(is(T == struct), "`" ~ __FUNCTION__ ~
                  "` should only be called with a `struct` type as argument, not: `" ~
                  fullyQualifiedName!T ~ "`");

    final switch (node.nodeID)
    {
    case NodeID.mapping:
            dbgWrite("Parsing config '%s', strict: %s",
                     fullyQualifiedName!T,
                     strict == StrictMode.Warn ?
                       strict.paint(Yellow) : strict.paintIf(!!strict, Green, Red));
            return node.parseMapping!(StructFieldRef!T)(
                null, T.init, const(Context)(cmdln, strict), null);
    case NodeID.sequence:
    case NodeID.scalar:
    case NodeID.invalid:
        throw new TypeConfigException(node, "mapping (object)", "document root");
    }
}

/*******************************************************************************

    The behavior to have when encountering a field in YAML not present
    in the config definition.

*******************************************************************************/

public enum StrictMode
{
    /// Issue an error by throwing an `UnknownKeyConfigException`
    Error  = 0,
    /// Write a message to `stderr`, but continue processing the file
    Warn   = 1,
    /// Be silent and do nothing
    Ignore = 2,
}

/// Used to pass around configuration
package struct Context
{
    ///
    private CLIArgs cmdln;

    ///
    private StrictMode strict;
}

/*******************************************************************************

    Parse a mapping from `node` into an instance of `T`

    Params:
      TLFR = Top level field reference for this mapping
      node = The YAML node object matching the struct being read
      path = The runtime path to this mapping, used for nested types
      defaultValue = The default value to use for `T`, which can be different
                     from `T.init` when recursing into fields with initializers.
      ctx = A context where properties that need to be conserved during
            recursion are stored
      fieldDefaults = Default value for some fields, used for `Key` recursion

*******************************************************************************/
private TLFR.Type parseMapping (alias TLFR)
    (Node node, string path, auto ref TLFR.Type defaultValue,
     in Context ctx, in Node[string] fieldDefaults)
{
    static assert(is(TLFR.Type == struct), "`parseMapping` called with wrong type (should be a `struct`)");
    assert(node.nodeID == NodeID.mapping, "Internal error: parseMapping shouldn't have been called");

    dbgWrite("%s: `parseMapping` called for '%s' (node entries: %s)",
             TLFR.Type.stringof.paint(Cyan), path.paint(Cyan),
             node.length.paintIf(!!node.length, Green, Red));

    static foreach (FR; FieldRefTuple!(TLFR.Type))
    {
        static if (FR.Name != FR.FieldName && hasMember!(TLFR.Type, FR.Name) &&
                   !is(typeof(mixin("TLFR.Type.", FR.Name)) == function))
            static assert (FieldRef!(TLFR.Type, FR.Name).Name != FR.Name,
                           "Field `" ~ FR.FieldName ~ "` `@Name` attribute shadows field `" ~
                           FR.Name ~ "` in `" ~ TLFR.Type.stringof ~ "`: Add a `@Name` attribute to `" ~
                           FR.Name ~ "` or change that of `" ~ FR.FieldName ~ "`");
    }

    if (ctx.strict != StrictMode.Ignore)
    {
        /// First, check that all the sections found in the mapping are present in the type
        /// If not, the user might have made a typo.
        immutable string[] fieldNames = [ FieldsName!(TLFR.Type) ];
        immutable string[] patterns = [ Patterns!(TLFR.Type) ];
    FIELD: foreach (const ref Node key, const ref Node value; node)
        {
            const k = key.as!string;
            if (!fieldNames.canFind(k))
            {
                foreach (p; patterns)
                    if (k.startsWith(p))
                        // Require length because `0` would match `canFind`
                        // and we don't want to allow `$PATTERN-`
                        if (k[p.length .. $].length > 1 && k[p.length] == '-')
                            continue FIELD;

                if (ctx.strict == StrictMode.Warn)
                {
                    scope exc = new UnknownKeyConfigException(
                        path, key.as!string, fieldNames, key.startMark());
                    exc.printException();
                }
                else
                    throw new UnknownKeyConfigException(
                        path, key.as!string, fieldNames, key.startMark());
            }
        }
    }

    const enabledState = node.isMappingEnabled!(TLFR.Type)(defaultValue);

    if (enabledState.field != EnabledState.Field.None)
        dbgWrite("%s: Mapping is enabled: %s", TLFR.Type.stringof.paint(Cyan), (!!enabledState).paintBool());

    auto convertField (alias FR) ()
    {
        static if (FR.Name != FR.FieldName)
            dbgWrite("Field name `%s` will use YAML field `%s`",
                     FR.FieldName.paint(Yellow), FR.Name.paint(Green));
        // Using exact type here matters: we could get a qualified type
        // (e.g. `immutable(string)`) if the field is qualified,
        // which causes problems.
        FR.Type default_ = __traits(getMember, defaultValue, FR.FieldName);

        // If this struct is disabled, do not attempt to parse anything besides
        // the `enabled` / `disabled` field.
        if (!enabledState)
        {
            // Even this is too noisy
            version (none)
                dbgWrite("%s: %s field of disabled struct, default: %s",
                         path.paint(Cyan), "Ignoring".paint(Yellow), default_);

            static if (FR.Name == "enabled")
                return false;
            else static if (FR.Name == "disabled")
                return true;
            else
                return default_;
        }

        if (auto ptr = FR.FieldName in fieldDefaults)
        {
            dbgWrite("Found %s (%s.%s) in `fieldDefaults`",
                     FR.Name.paint(Cyan), path.paint(Cyan), FR.FieldName.paint(Cyan));

            if (ctx.strict && FR.FieldName in node)
                throw new ConfigExceptionImpl("'Key' field is specified twice", path, FR.FieldName, node.startMark());
            return (*ptr).parseField!(FR)(path.addPath(FR.FieldName), default_, ctx)
                .dbgWriteRet("Using value '%s' from fieldDefaults for field '%s'",
                             FR.FieldName.paint(Cyan));
        }

        // This, `FR.Pattern`, and the field in `@Name` are special support for `dub`
        static if (FR.Pattern)
        {
            static if (is(FR.Type : V[K], K, V))
            {
                alias AAFieldRef = NestedFieldRef!(V, FR);
                static assert(is(K : string), "Key type should be string-like");
            }
            else
                static assert(0, "Cannot have pattern on non-AA field");

            AAFieldRef.Type[string] result;
            foreach (pair; node.mapping)
            {
                const key = pair.key.as!string;
                if (!key.startsWith(FR.Name))
                    continue;
                string suffix = key[FR.Name.length .. $];
                if (suffix.length)
                {
                    if (suffix[0] == '-') suffix = suffix[1 .. $];
                    else continue;
                }

                result[suffix] = pair.value.parseField!(AAFieldRef)(
                    path.addPath(key), default_.get(key, AAFieldRef.Type.init), ctx);
            }
            bool hack = true;
            if (hack) return result;
        }

        if (auto ptr = FR.Name in node)
        {
            dbgWrite("%s: YAML field is %s in node%s",
                     FR.Name.paint(Cyan), "present".paint(Green),
                     (FR.Name == FR.FieldName ? "" : " (note that field name is overriden)").paint(Yellow));
            return (*ptr).parseField!(FR)(path.addPath(FR.Name), default_, ctx)
                .dbgWriteRet("Using value '%s' from YAML document for field '%s'",
                             FR.FieldName.paint(Cyan));
        }

        dbgWrite("%s: Field is %s from node%s",
                 FR.Name.paint(Cyan), "missing".paint(Red),
                 (FR.Name == FR.FieldName ? "" : " (note that field name is overriden)").paint(Yellow));

        // A field is considered optional if it has an initializer that is different
        // from its default value, or if it has the `Optional` UDA.
        // In that case, just return this value.
        static if (FR.Optional)
            return default_
                .dbgWriteRet("Using default value '%s' for optional field '%s'", FR.FieldName.paint(Cyan));

        // The field is not present, but it could be because it is an optional section.
        // For example, the section could be defined as:
        // ---
        // struct RequestLimit { size_t reqs = 100; }
        // struct Config { RequestLimit limits; }
        // ---
        // In this case we need to recurse into `RequestLimit` to check if any
        // of its field is required.
        else static if (mightBeOptional!FR)
        {
            const npath = path.addPath(FR.Name);
            string[string] aa;
            return Node(aa).parseMapping!(FR)(npath, default_, ctx, null);
        }
        else
            throw new MissingKeyException(path, FR.Name, node.startMark());
    }

    FR.Type convert (alias FR) ()
    {
        static if (__traits(getAliasThis, TLFR.Type).length == 1 &&
                   __traits(getAliasThis, TLFR.Type)[0] == FR.FieldName)
        {
            static assert(FR.Name == FR.FieldName,
                          "Field `" ~ fullyQualifiedName!(FR.Ref) ~
                          "` is the target of an `alias this` and cannot have a `@Name` attribute");
            static assert(!hasConverter!(FR.Ref),
                          "Field `" ~ fullyQualifiedName!(FR.Ref) ~
                          "` is the target of an `alias this` and cannot have a `@Converter` attribute");

            alias convertW(string FieldName) = convert!(FieldRef!(FR.Type, FieldName, FR.Optional));
            return FR.Type(staticMap!(convertW, FieldNameTuple!(FR.Type)));
        }
        else
            return convertField!(FR)();
    }

    debug (ConfigFillerDebug)
    {
        indent++;
        scope (exit) indent--;
    }

    TLFR.Type doValidation (TLFR.Type result)
    {
        static if (is(typeof(result.validate())))
        {
            if (enabledState)
            {
                dbgWrite("%s: Calling `%s` method",
                     TLFR.Type.stringof.paint(Cyan), "validate()".paint(Green));
                result.validate();
            }
            else
            {
                dbgWrite("%s: Ignoring `%s` method on disabled mapping",
                         TLFR.Type.stringof.paint(Cyan), "validate()".paint(Green));
            }
        }
        else if (enabledState)
            dbgWrite("%s: No `%s` method found",
                     TLFR.Type.stringof.paint(Cyan), "validate()".paint(Yellow));

        return result;
    }

    // This might trigger things like "`this` is not accessible".
    // In this case, the user most likely needs to provide a converter.
    alias convertWrapper(string FieldName) = convert!(FieldRef!(TLFR.Type, FieldName));
    return doValidation(TLFR.Type(staticMap!(convertWrapper, FieldNameTuple!(TLFR.Type))));
}

/*******************************************************************************

    Parse a field, trying to match up the compile-time expectation with
    the run time value of the Node (`nodeID`).

    This is the central point which does "type conversion", from the YAML node
    to the field type. Whenever adding support for a new type, things should
    happen here.

    Because a `struct` can be filled from either a mapping or a scalar,
    this function will first try the converter / fromString / string ctor
    methods before defaulting to field-wise construction.

    Note that optional fields are checked before recursion happens,
    so this method does not do this check.

*******************************************************************************/

package FR.Type parseField (alias FR)
    (Node node, string path, auto ref FR.Type defaultValue, in Context ctx)
{
    if (node.nodeID == NodeID.invalid)
        throw new TypeConfigException(node, "valid", path);

    // If we reached this, it means the field is set, so just recurse
    // to peel the type
    static if (is(FR.Type : SetInfo!FT, FT))
        return FR.Type(
            parseField!(FieldRef!(FR.Type, "value"))(node, path, defaultValue, ctx),
            true);

    else static if (hasConverter!(FR.Ref))
        return wrapException(node.viaConverter!(FR)(path, ctx), path, node.startMark());

    else static if (hasFromYAML!(FR.Type))
    {
        scope impl = new ConfigParserImpl!(FR.Type)(node, path, ctx);
        return wrapException(FR.Type.fromYAML(impl), path, node.startMark());
    }

    else static if (hasFromString!(FR.Type))
        return wrapException(FR.Type.fromString(node.as!string), path, node.startMark());

    else static if (hasStringCtor!(FR.Type))
        return wrapException(FR.Type(node.as!string), path, node.startMark());

    else static if (is(immutable(FR.Type) == immutable(core.time.Duration)))
    {
        if (node.nodeID != NodeID.mapping)
            throw new DurationTypeConfigException(node, path);
        return node.parseMapping!(StructFieldRef!DurationMapping)(
            path, DurationMapping.make(defaultValue), ctx, null).opCast!Duration;
    }

    else static if (is(FR.Type == struct))
    {
        if (node.nodeID != NodeID.mapping)
            throw new TypeConfigException(node, "mapping (object)", path);
        return node.parseMapping!(FR)(path, defaultValue, ctx, null);
    }

    // Handle string early as they match the sequence rule too
    else static if (isSomeString!(FR.Type))
        // Use `string` type explicitly because `Variant` thinks
        // `immutable(char)[]` (aka `string`) and `immutable(char[])`
        // (aka `immutable(string)`) are not compatible.
        return node.parseScalar!(string)(path);
    // Enum too, as their base type might be an array (including strings)
    else static if (is(FR.Type == enum))
        return node.parseScalar!(FR.Type)(path);

    else static if (is(FR.Type : E[K], E, K))
    {
        if (node.nodeID != NodeID.mapping)
            throw new TypeConfigException(node, "mapping (associative array)", path);

        // Note: As of June 2022 (DMD v2.100.0), associative arrays cannot
        // have initializers, hence their UX for config is less optimal.
        return node.mapping().map!(
                (Node.Pair pair) {
                    return tuple(
                        pair.key.get!K,
                        pair.value.parseField!(NestedFieldRef!(E, FR))(
                            format("%s[%s]", path, pair.key.as!string), E.init, ctx));
                }).assocArray();

    }
    else static if (is(FR.Type : E[], E))
    {
        static if (hasUDA!(FR.Ref, Key))
        {
            static assert(getUDAs!(FR.Ref, Key).length == 1,
                          "`" ~ fullyQualifiedName!(FR.Ref) ~
                          "` field shouldn't have more than one `Key` attribute");
            static assert(is(E == struct),
                          "Field `" ~ fullyQualifiedName!(FR.Ref) ~
                          "` has a `Key` attribute, but is a sequence of `" ~
                          fullyQualifiedName!E ~ "`, not a sequence of `struct`");

            string key = getUDAs!(FR.Ref, Key)[0].name;

            if (node.nodeID != NodeID.mapping && node.nodeID != NodeID.sequence)
                throw new TypeConfigException(node, "mapping (object) or sequence", path);

            if (node.nodeID == NodeID.mapping) return node.mapping().map!(
                (Node.Pair pair) {
                    if (pair.value.nodeID != NodeID.mapping)
                        throw new TypeConfigException(
                            "sequence of " ~ pair.value.nodeTypeString(),
                            "sequence of mapping (array of objects)",
                            path, null, node.startMark());

                    return pair.value.parseMapping!(StructFieldRef!E)(
                        path.addPath(pair.key.as!string),
                        E.init, ctx, key.length ? [ key: pair.key ] : null);
                }).array();
        }
        if (node.nodeID != NodeID.sequence)
            throw new TypeConfigException(node, "sequence (array)", path);

        // We pass `E.init` as default value as it is not going to be used:
        // Either there is something in the YAML document, and that will be
        // converted, or `sequence` will not iterate.
        return node.sequence.enumerate.map!(
            kv => kv.value.parseField!(NestedFieldRef!(E, FR))(
                format("%s[%s]", path, kv.index), E.init, ctx))
            .array();
    }
    else
    {
        static assert (!is(FR.Type == union),
                       "`union` are not supported. Use a converter instead");
        return node.parseScalar!(FR.Type)(path);
    }
}

/// Parse a node as a scalar
private T parseScalar (T) (Node node, string path)
{
    if (node.nodeID != NodeID.scalar)
        throw new TypeConfigException(node, "scalar (value)", path);

    static if (is(T == enum))
        return node.as!string.to!(T);
    else
        return node.as!(T);
}

/*******************************************************************************

    Write a potentially throwing user-provided expression in ConfigException

    The user-provided hooks may throw (e.g. `fromString / the constructor),
    and the error may or may not be clear. We can't do anything about a bad
    message but we can wrap the thrown exception in a `ConfigException`
    to provide the location in the yaml file where the error happened.

    Params:
      exp = The expression that may throw
      path = Path within the config file of the field
      position = Position of the node in the YAML file
      file = Call site file (otherwise the message would point to this function)
      line = Call site line (see `file` reasoning)

    Returns:
      The result of `exp` evaluation.

*******************************************************************************/

private T wrapException (T) (lazy T exp, string path, Mark position,
    string file = __FILE__, size_t line = __LINE__)
{
    try
        return exp;
    catch (ConfigException exc)
        throw exc;
    catch (Exception exc)
        throw new ConstructionException(exc, path, position, file, line);
}

/// Allows us to reuse parseMapping and strict parsing
private struct DurationMapping
{
    public SetInfo!long weeks;
    public SetInfo!long days;
    public SetInfo!long hours;
    public SetInfo!long minutes;
    public SetInfo!long seconds;
    public SetInfo!long msecs;
    public SetInfo!long usecs;
    public SetInfo!long hnsecs;
    public SetInfo!long nsecs;

    private static DurationMapping make (Duration def) @safe pure nothrow @nogc
    {
        typeof(return) result;
        auto fullSplit = def.split();
        result.weeks = SetInfo!long(fullSplit.weeks, fullSplit.weeks != 0);
        result.days = SetInfo!long(fullSplit.days, fullSplit.days != 0);
        result.hours = SetInfo!long(fullSplit.hours, fullSplit.hours != 0);
        result.minutes = SetInfo!long(fullSplit.minutes, fullSplit.minutes != 0);
        result.seconds = SetInfo!long(fullSplit.seconds, fullSplit.seconds != 0);
        result.msecs = SetInfo!long(fullSplit.msecs, fullSplit.msecs != 0);
        result.usecs = SetInfo!long(fullSplit.usecs, fullSplit.usecs != 0);
        result.hnsecs = SetInfo!long(fullSplit.hnsecs, fullSplit.hnsecs != 0);
        // nsecs is ignored by split as it's not representable in `Duration`
        return result;
    }

    ///
    public void validate () const @safe
    {
        // That check should never fail, as the YAML parser would error out,
        // but better be safe than sorry.
        foreach (field; this.tupleof)
            if (field.set)
                return;

        throw new Exception(
            "Expected at least one of the components (weeks, days, hours, " ~
            "minutes, seconds, msecs, usecs, hnsecs, nsecs) to be set");
    }

    ///  Allow conversion to a `Duration`
    public Duration opCast (T : Duration) () const scope @safe pure nothrow @nogc
    {
        return core.time.weeks(this.weeks) + core.time.days(this.days) +
            core.time.hours(this.hours) + core.time.minutes(this.minutes) +
            core.time.seconds(this.seconds) + core.time.msecs(this.msecs) +
            core.time.usecs(this.usecs) + core.time.hnsecs(this.hnsecs) +
            core.time.nsecs(this.nsecs);
    }
}

/// Evaluates to `true` if we should recurse into the struct via `parseMapping`
private enum mightBeOptional (alias FR) = is(FR.Type == struct) &&
    !is(immutable(FR.Type) == immutable(core.time.Duration)) &&
    !hasConverter!(FR.Ref) && !hasFromString!(FR.Type) &&
    !hasStringCtor!(FR.Type) && !hasFromYAML!(FR.Type);

/// Convenience template to check for the presence of converter(s)
private enum hasConverter (alias Field) = hasUDA!(Field, Converter);

/// Provided a field reference `FR` which is known to have at least one converter,
/// perform basic checks and return the value after applying the converter.
private auto viaConverter (alias FR) (Node node, string path, in Context context)
{
    enum Converters = getUDAs!(FR.Ref, Converter);
    static assert (Converters.length,
                   "Internal error: `viaConverter` called on field `" ~
                   FR.FieldName ~ "` with no converter");

    static assert(Converters.length == 1,
                  "Field `" ~ FR.FieldName ~ "` cannot have more than one `Converter`");

    scope impl = new ConfigParserImpl!(FR.Type)(node, path, context);
    return Converters[0].converter(impl);
}

private final class ConfigParserImpl (T) : ConfigParser!T
{
    private Node node_;
    private string path_;
    private const(Context) context_;

    /// Ctor
    public this (Node n, string p, const Context c) scope @safe pure nothrow @nogc
    {
        this.node_ = n;
        this.path_ = p;
        this.context_ = c;
    }

    public final override inout(Node) node () inout @safe pure nothrow @nogc
    {
        return this.node_;
    }

    public final override string path () const @safe pure nothrow @nogc
    {
        return this.path_;
    }

    protected final override const(Context) context () const @safe pure nothrow @nogc
    {
        return this.context_;
    }
}

/// Helper predicate
private template NameIs (string searching)
{
    enum bool Pred (alias FR) = (searching == FR.Name);
}

/// Returns whether or not the field has a `enabled` / `disabled` field,
/// and its value. If it does not, returns `true`.
private EnabledState isMappingEnabled (M) (Node node, auto ref M default_)
{
    import std.meta : Filter;

    alias EMT = Filter!(NameIs!("enabled").Pred, FieldRefTuple!M);
    alias DMT = Filter!(NameIs!("disabled").Pred, FieldRefTuple!M);

    static if (EMT.length)
    {
        static assert (DMT.length == 0,
                       "`enabled` field `" ~ EMT[0].FieldName ~
                       "` conflicts with `disabled` field `" ~ DMT[0].FieldName ~ "`");

        if (auto ptr = "enabled" in node)
            return EnabledState(EnabledState.Field.Enabled, (*ptr).as!bool);
        return EnabledState(EnabledState.Field.Enabled, __traits(getMember, default_, EMT[0].FieldName));
    }
    else static if (DMT.length)
    {
        if (auto ptr = "disabled" in node)
            return EnabledState(EnabledState.Field.Disabled, (*ptr).as!bool);
        return EnabledState(EnabledState.Field.Disabled, __traits(getMember, default_, DMT[0].FieldName));
    }
    else
    {
        return EnabledState(EnabledState.Field.None);
    }
}

/// Return value of `isMappingEnabled`
private struct EnabledState
{
    /// Used to determine which field controls a mapping enabled state
    private enum Field
    {
        /// No such field, the mapping is considered enabled
        None,
        /// The field is named 'enabled'
        Enabled,
        /// The field is named 'disabled'
        Disabled,
    }

    /// Check if the mapping is considered enabled
    public bool opCast () const scope @safe pure @nogc nothrow
    {
        return this.field == Field.None ||
            (this.field == Field.Enabled && this.fieldValue) ||
            (this.field == Field.Disabled && !this.fieldValue);
    }

    /// Type of field found
    private Field field;

    /// Value of the field, interpretation depends on `field`
    private bool fieldValue;
}

/// Evaluates to `true` if `T` is a `struct` with a default ctor
private enum hasFieldwiseCtor (T) = (is(T == struct) && is(typeof(() => T(T.init.tupleof))));

/// Evaluates to `true` if `T` has a static method that is designed to work with this library
private enum hasFromYAML (T) = is(typeof(T.fromYAML(ConfigParser!(T).init)) : T);

/// Evaluates to `true` if `T` has a static method that accepts a `string` and returns a `T`
private enum hasFromString (T) = is(typeof(T.fromString(string.init)) : T);

/// Evaluates to `true` if `T` is a `struct` which accepts a single string as argument
private enum hasStringCtor (T) = (is(T == struct) && is(typeof(T.__ctor)) &&
                                  Parameters!(T.__ctor).length == 1 &&
                                  is(typeof(() => T(string.init))));

unittest
{
    static struct Simple
    {
        int value;
        string otherValue;
    }

    static assert( hasFieldwiseCtor!Simple);
    static assert(!hasStringCtor!Simple);

    static struct PubKey
    {
        ubyte[] data;

        this (string hex) @safe pure nothrow @nogc{}
    }

    static assert(!hasFieldwiseCtor!PubKey);
    static assert( hasStringCtor!PubKey);

    static assert(!hasFieldwiseCtor!string);
    static assert(!hasFieldwiseCtor!int);
    static assert(!hasStringCtor!string);
    static assert(!hasStringCtor!int);
}

/// Convenience function to extend a YAML path
private string addPath (string opath, string newPart)
in(newPart.length)
do {
    return opath.length ? format("%s.%s", opath, newPart) : newPart;
}
