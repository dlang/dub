/*******************************************************************************

    Utilities to fill a struct representing the configuration with the content
    of a document.

    The main function of this module is `parseConfig`. Higher-level wrappers
    such as `parseConfigString` and `parseConfigFile` are also available in
    `configy.easy`.

    The type parameter to those three functions must be a struct and is used
    to drive the processing of the mapping. When an error is encountered,
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

    Composite_Types:
      Processing starts from a `struct` at the top level, and recurse into
      every fields individually. If a field is itself a struct,
      the filler will attempt the following, in order:
      - If the field has no value and is not optional, an Exception will
        be thrown with an error message detailing where the issue happened.
      - If the field has no value and is optional, the default value will
        be used.
      - If the type has a `static` method named `fromConfig` whose sole
        non-default argument is a `configy.attributes : ConfigParser`, this hook
        will called to handle deserialization. This is the prefered method to
        handle complex logic.
      - If the type has a `static` method named `fromString` whose sole argument
        is a `string`, it will be used.
      - If the type has a constructor whose sole argument is a `string`,
        it will be used;
      - Finally, the filler will attempt to deserialize all struct members
        one by one and pass them to the default constructor, if there is any.
      - If none of the above succeeded, a `static assert` will trigger.

    fromConfig:
      Because config structs may contain complex types outside of the project's
      control (e.g. a Phobos type, Vibe.d's `URL`, etc...) or one may want
      the config format to be more dynamic (e.g. by exposing union-like behavior),
      one may need to apply more custom logic than what Configy does.
      For this use case, one can define a `fromConfig` static method in the type:
      `static S fromConfig(scope ConfigParser parser)`. Structs with `fromConfig`
      will have this method called instead of going through the normal parsing
      rules. The `ConfigParser` exposes the current path of the field, as well
      as the raw `Node` itself, allowing for maximum flexibility.

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
      be expressed. In the first form, the node should be a mapping,
      and it will be checked for fields matching the supported units
      in `core.time`: `weeks`, `days`, `hours`, `minutes`, `seconds`, `msecs`,
      `usecs`, `hnsecs`, `nsecs`. Strict parsing option will be respected.
      The values of the fields will then be added together, so the following
      YAML usage:
      ---
      // sleepFor:
      //   hours: 8
      //   minutes: 30
      ---
      is equivalent to the less human-friendly version:
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
      In this form, the node is expected to be a scalar.
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
      that the error message, if any, is consistent accross user input.

    Strict_Parsing:
      When strict parsing is enabled, the config filler will also validate
      that the mappings do not contains entry which are not present in the
      struct being processed.
      This can be useful to catch typos or outdated configuration options.

    Post_Validation:
      Some configuration will require validation accross multiple sections.
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

module dub.internal.configy.read;

import dub.internal.configy.attributes;
import dub.internal.configy.exceptions : ConfigException;
import dub.internal.configy.exceptions;
import dub.internal.configy.fieldref;
import dub.internal.configy.utils;
import dub.internal.configy.backend.node;

import std.algorithm;
import std.conv;
import std.datetime;
import std.format;
import std.meta;
import std.range;
import std.stdio;
import std.traits;
import std.typecons : Nullable, nullable;

static import core.time;

// Dub-specific adjustments for output
import dub.internal.logging;

/*******************************************************************************

    Wrap and print exceptions to stderr

    This allows to call either `parseConfigFile` or `parseConfigString`
    and pretty-print the exception:
    ```
    int main ()
    {
        auto configN = wrapException(
            parseConfigString!Config("config.yaml", "/dev/null")
        );
        if (configN.isNull()) return 1; // Error path
        auto config = configN.get();
        // Rest of the program ...
    }
    ```

    Params:
        parseCall = A call to one of the `parse*` functions, such as
                    `parseConfigString` or `parseConfigFile`, or anything
                    that would call them.

    Returns:
        An initialized `T` instance if reading/parsing was successful;
        a `null` instance otherwise.

*******************************************************************************/

public Nullable!T wrapException (T) (lazy T parseCall)
{
    try
        return nullable(parseCall);
    catch (ConfigException exc)
    {
        exc.printException();
        return typeof(return).init;
    }
    catch (Exception exc)
    {
        // Other Exception type may be thrown by the underlying libraries.
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

    Process the content of the document described by `node` into an instance of
    the struct `T`.

    See the module description for a complete overview of this function.

    Params:
      T = Type of the config struct to fill
      node = The root node matching `T`
      strict = Action to take when encountering unknown keys in the document

    Returns:
      An instance of `T` filled with the content of `node`

    Throws:
      If the content of `node` cannot satisfy the requirements set by `T`,
      or if `node` contain extra fields and `strict` is `true`.

*******************************************************************************/

public T parseConfig (T) (Node node, StrictMode strict = StrictMode.Error)
{
    static assert(is(T == struct), "`" ~ __FUNCTION__ ~
                  "` should only be called with a `struct` type as argument, not: `" ~
                  fullyQualifiedName!T ~ "`");

    final switch (node.type())
    {
    case Node.Type.Mapping:
            dbgWrite("Parsing config '%s', strict: %s",
                     fullyQualifiedName!T,
                     strict == StrictMode.Warn ?
                       strict.paint(Yellow) : strict.paintIf(!!strict, Green, Red));
            return node.parseField!(StructFieldRef!T)(
                null, T.init, const(Context)(strict));
    case Node.Type.Sequence:
    case Node.Type.Scalar:
    case Node.Type.Invalid:
        throw new TypeConfigException(node, "a mapping (object)", "document root");
    }
}

/*******************************************************************************

    The behavior to have when encountering a field in the document not present
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
    private StrictMode strict;
}

/*******************************************************************************

    Parse a mapping from `node` into an instance of `T`

    Params:
      TLFR = Top level field reference for this mapping
      node = The node object matching the struct being read
      path = The runtime path to this mapping, used for nested types
      defaultValue = The default value to use for `T`, which can be different
                     from `T.init` when recursing into fields with initializers.
      ctx = A context where properties that need to be conserved during
            recursion are stored
      fieldDefaults = Default value for some fields, used for `Key` recursion

*******************************************************************************/

private TLFR.Type parseMapping (alias TLFR)
    (Mapping node, string path, auto ref TLFR.Type defaultValue,
     in Context ctx, scope Node[string] fieldDefaults)
{
    static assert(is(TLFR.Type == struct), "`parseMapping` called with wrong type (should be a `struct`)");
    assert(node.type() == Node.Type.Mapping, "Internal error: parseMapping shouldn't have been called");

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
    FIELD: foreach (scope Node key, scope Node value; node)
        {
            scope str = key.parseScalar!string(path);
            if (!fieldNames.canFind(str))
            {
                foreach (p; patterns)
                    if (str.startsWith(p))
                        // Require length because `0` would match `canFind`
                        // and we don't want to allow `$PATTERN-`
                        if (str[p.length .. $].length > 1 && str[p.length] == '-')
                            continue FIELD;

                if (ctx.strict == StrictMode.Warn)
                {
                    scope exc = new UnknownKeyConfigException(
                        path, str, fieldNames, key.location());
                    exc.printException();
                }
                else
                    throw new UnknownKeyConfigException(
                        path, str, fieldNames, key.location());
            }
        }
    }

    const enabledState = node.isMappingEnabled!(TLFR.Type)(path, defaultValue);

    if (enabledState.field != EnabledState.Field.None)
        dbgWrite("%s: Mapping is enabled: %s", TLFR.Type.stringof.paint(Cyan), (!!enabledState).paintBool());

    auto convertField (alias FR) ()
    {
        static if (FR.Name != FR.FieldName)
            dbgWrite("Field name `%s` will use document field `%s`",
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

            if (ctx.strict && node.has(FR.FieldName))
                throw new ConfigExceptionImpl("'Key' field is specified twice",
                    path.addPath(FR.FieldName), node.location());
            return (*ptr).parseField!(FR)(path.addPath(FR.FieldName), default_, ctx)
                .dbgWriteRet("Using value '%s' from fieldDefaults for field '%s'",
                             FR.FieldName.paint(Cyan));
        }

        // This, `FR.Pattern`, and the field in `@Name` are special support for `dub`
        static if (FR.Pattern)
        {
            import std.exception : enforce;

            static if (is(FR.Type : V[K], K, V))
            {
                alias AAFieldRef = NestedFieldRef!(V, FR);
                static assert(is(K : string), "Key type should be string-like");
            }
            else
                static assert(0, "Cannot have pattern on non-AA field");

            AAFieldRef.Type[string] result;
            foreach (scope key, scope value; node)
            {
                const kstr = enforce(key.asScalar(), "Key should be a scalar (string)").str;
                if (!kstr.startsWith(FR.Name))
                    continue;
                string suffix = kstr[FR.Name.length .. $];
                if (suffix.length)
                {
                    if (suffix[0] == '-') suffix = suffix[1 .. $];
                    else continue;
                }

                result[suffix] = value.parseField!(AAFieldRef)(
                    path.addPath(kstr), default_.get(kstr, AAFieldRef.Type.init), ctx);
            }
            bool hack = true;
            if (hack) return result;
        }

        return node.withNode(FR.Name, (scope Node key, scope Node value) {
            if (value !is null)
            {
                dbgWrite("%s: document field is %s in node%s",
                    FR.Name.paint(Cyan), "present".paint(Green),
                    (FR.Name == FR.FieldName ? "" : " (note that field name is overriden)").paint(Yellow));
                return value.parseField!(FR)(path.addPath(FR.Name), default_, ctx)
                    .dbgWriteRet("Using value '%s' from document for field '%s'",
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
                scope emptyNode = new EmptyNode(node.location());
                return emptyNode.parseMapping!(FR)(npath, default_, ctx, null);
            }
            else
                throw new MissingKeyException(path.addPath(FR.Name), node.location());
        });
    }

    FR.Type convert (alias FR) ()
    {
        static if (__traits(getAliasThis, TLFR.Type).length == 1 &&
                   __traits(getAliasThis, TLFR.Type)[0] == FR.FieldName)
        {
            static assert(FR.Name == FR.FieldName,
                          "Field `" ~ fullyQualifiedName!(FR.Ref) ~
                          "` is the target of an `alias this` and cannot have a `@Name` attribute");

            alias convertW(string FieldName) = convert!(FieldRef!(FR.Type, FieldName, FR.Optional));
            static assert(hasFieldWiseCtor!FR, "Type `" ~ FR.Type.stringof
                          ~ "` used for `alias this` in type `" ~ TLFR.Type.stringof
                          ~ "` does not support field-wise (default) construction: "
                          ~ "Add field-wise constructor, a string constructor, or a hook");
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
                wrapConstruct(result.validate(), path, node.location());
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
    // In this case, the user most likely needs to provide a hook.
    alias convertWrapper(string FieldName) = convert!(FieldRef!(TLFR.Type, FieldName));
    static assert(hasFieldWiseCtor!TLFR, "Type `" ~ TLFR.Type.stringof
                  ~ "` does not support field-wise (default) construction: "
                  ~ "Add field-wise constructor, a string constructor, or a hook");
    return doValidation(TLFR.Type(staticMap!(convertWrapper, FieldNameTuple!(TLFR.Type))));
}

/*******************************************************************************

    Parse a field, trying to match up the compile-time expectation with
    the run time value of the Node (`Node.Type`).

    This is the central point which does "type conversion", from the node
    to the field type. Whenever adding support for a new type, things should
    happen here.

    Because a `struct` can be filled from either a mapping or a scalar,
    this function will first try the fromConfig / fromString / string ctor
    methods before defaulting to fieldwise construction.

    Note that optional fields are checked before recursion happens,
    so this method does not do this check.

*******************************************************************************/

package FR.Type parseField (alias FR)
    (Node node, string path, auto ref FR.Type defaultValue, in Context ctx)
{
    if (node.type() == Node.Type.Invalid)
        throw new TypeConfigException(node, "valid", path);

    // If we reached this, it means the field is set, so just recurse
    // to peel the type
    static if (is(FR.Type : SetInfo!FT, FT))
        return FR.Type(
            parseField!(FieldRef!(FR.Type, "value"))(node, path, defaultValue, ctx),
            true);

    else static if (hasFromConfig!(FR.Type))
    {
        scope impl = new ConfigParserImpl(node, path, ctx);
        return wrapConstruct(FR.Type.fromConfig(impl), path, node.location());
    }

    else static if (hasFromString!(FR.Type))
        return wrapConstruct(FR.Type.fromString(node.parseScalar!(string)(path)), path, node.location());

    else static if (hasStringCtor!(FR.Type))
        return wrapConstruct(FR.Type(node.parseScalar!(string)(path)), path, node.location());

    else static if (is(immutable(FR.Type) == immutable(core.time.Duration)))
    {
        if (scope mapping = node.asMapping())
            return mapping.parseMapping!(StructFieldRef!DurationMapping)(
                path, DurationMapping.make(defaultValue), ctx, null).opCast!Duration;
        throw new DurationTypeConfigException(node, path);
    }

    else static if (is(FR.Type == struct))
    {
        if (auto mapping = node.asMapping())
            return mapping.parseMapping!(FR)(path, defaultValue, ctx, null);
        throw new TypeConfigException(node, "a mapping (object)", path);
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
        scope mapping = node.asMapping();
        if (mapping is null)
            throw new TypeConfigException(node, "a mapping (associative array)", path);

        // Note: As of June 2022 (DMD v2.100.0), associative arrays cannot
        // have initializers, hence their UX for config is less optimal.
        FR.Type result;
        foreach (scope Node key, scope Node value; mapping) {
            scope ks = key.parseScalar!(K)(path);
            result[ks] = value.parseField!(NestedFieldRef!(E, FR))(
                format("%s[%s]", path, ks), E.init, ctx);
        }
        return result;
    }
    else static if (is(FR.Type : E[], E))
    {
        static if (hasUDA!(FR.Ref, Key))
        {
            scope mapping = node.asMapping();
            if (mapping is null)
                throw new TypeConfigException(node, "mapping (object)", path);

            static assert(getUDAs!(FR.Ref, Key).length == 1,
                          "`" ~ fullyQualifiedName!(FR.Ref) ~
                          "` field shouldn't have more than one `Key` attribute");
            static assert(is(E == struct),
                          "Field `" ~ fullyQualifiedName!(FR.Ref) ~
                          "` has a `Key` attribute, but is a sequence of `" ~
                          fullyQualifiedName!E ~ "`, not a sequence of `struct`");

            string key = getUDAs!(FR.Ref, Key)[0].name;
            E[] result;
            foreach (scope Node k, scope Node value; mapping) {
                scope npath = path.addPath(k.parseScalar!string(path));
                if (scope vmap = value.asMapping()) {
                    result ~= vmap.parseMapping!(StructFieldRef!E)(npath,
                        E.init, ctx, key.length ? [ key: k ] : null);
                    continue;
                }
                // It might be a single entry, e.g.
                // ---
                // values:
                // morevalues:
                //   key: value
                // ---
                // In this instance, `values` is an empty mapping but might be
                // interpreted as a scalar.
                if (scope scalar = value.asScalar())
                    if (scalar.str is null) {
                        scope emptyNode = new EmptyNode(value.location());
                        result ~= emptyNode.parseMapping!(StructFieldRef!E)(npath,
                            E.init, ctx, key.length ? [ key: k ] : null);
                        continue;
                    }
                throw new TypeConfigException(value.type().toString(), "mapping",
                    npath, value.location());
            }
            return result;
        }
        else
        {
            scope seq = node.asSequence();
            if (seq is null)
                throw new TypeConfigException(node, "sequence (array)", path);

            typeof(return) validateLength (E[] res)
            {
                static if (is(FR.Type : E_[k], E_, size_t k))
                {
                    if (res.length != k)
                        throw new ArrayLengthException(
                            res.length, k, path, node.location());
                    return res[0 .. k];
                }
                else
                    return res;
            }

            // We pass `E.init` as default value as it is not going to be used:
            // Either there is something in the document, and that will be
            // converted, or `sequence` will not iterate.
            E[] result;
            foreach (size_t idx, scope Node value; seq)
                result ~= value.parseField!(NestedFieldRef!(E, FR))(
                    format("%s[%s]", path, idx), E.init, ctx);
            return validateLength(result);
        }
    }
    else static if (is(FR.Type == T*, T))
    {
        // Allocate and parse pointers' values.
        // This allows us to have recursive types. Pointers are always optional.
        // If the type needs to be mandatory, it should be declared as a value.
        return [node.parseField!(NestedFieldRef!(T, FR))(path, T.init, ctx)].ptr;
    }
    else
    {
        static assert (!is(FR.Type == union), "`union` are not supported. " ~
            "Use a `struct` with a hook (`fromConfig`, `fromString`, string constructor) instead");
        return node.parseScalar!(FR.Type)(path);
    }
}

/// Parse a node as a scalar
private T parseScalar (T) (Node node, lazy string path)
{
    try
        if (scope scalar = node.asScalar())
            return scalar.str.to!(T);
    catch (Exception exc) {}

    throw new TypeConfigException(node, "a value of type " ~ T.stringof, path);
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
      position = Position of the node
      file = Call site file (otherwise the message would point to this function)
      line = Call site line (see `file` reasoning)

    Returns:
      The result of `exp` evaluation.

*******************************************************************************/

private T wrapConstruct (T) (lazy T exp, string path, in Location position,
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
        // That check should never fail, as the document parser would error out,
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
    !hasFromString!(FR.Type) && !hasStringCtor!(FR.Type) &&
    !hasFromConfig!(FR.Type);

private final class ConfigParserImpl : ConfigParser
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
private EnabledState isMappingEnabled (M) (Mapping node, string path, auto ref M default_)
{
    import std.meta : Filter;

    alias EMT = Filter!(NameIs!("enabled").Pred, FieldRefTuple!M);
    alias DMT = Filter!(NameIs!("disabled").Pred, FieldRefTuple!M);

    static if (EMT.length)
    {
        static assert (DMT.length == 0,
                       "`enabled` field `" ~ EMT[0].FieldName ~
                       "` conflicts with `disabled` field `" ~ DMT[0].FieldName ~ "`");

        return node.withNode("enabled", (scope Node key, scope Node value) {
            if (value !is null)
                return EnabledState(EnabledState.Field.Enabled, value.parseScalar!(bool)(path.addPath("enabled")));
            return EnabledState(EnabledState.Field.Enabled, __traits(getMember, default_, EMT[0].FieldName));
        });
    }
    else static if (DMT.length)
    {
        return node.withNode("disabled", (scope Node key, scope Node value) {
            if (value !is null)
                return EnabledState(EnabledState.Field.Disabled, value.parseScalar!(bool)(path.addPath("disabled")));
            return EnabledState(EnabledState.Field.Disabled, __traits(getMember, default_, DMT[0].FieldName));
        });
    }
    else
    {
        return EnabledState(EnabledState.Field.None);
    }
}

/// Retun value of `isMappingEnabled`
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

/// Check if this type can be instantiated by the sum of its fields (usually default ctor)
private template hasFieldWiseCtor (alias FR)
{
    private alias InitVal(string FieldName) = FieldRef!(FR.Type, FieldName).Default;
    enum hasFieldWiseCtor = is(typeof(FR.Type(staticMap!(InitVal, FieldNameTuple!(FR.Type)))));
}

/// Evaluates to `true` if `T` has a static method that is designed to work with this library
private enum hasFromConfig (T) = is(typeof(T.fromConfig(ConfigParser.init)) : T);

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

    static assert( hasFieldWiseCtor!(StructFieldRef!Simple));
    static assert(!hasStringCtor!Simple);

    static struct PubKey
    {
        ubyte[] data;

        this (string hex) @safe pure nothrow @nogc{}
    }

    static assert(!hasFieldWiseCtor!(StructFieldRef!PubKey));
    static assert( hasStringCtor!PubKey);
}

/// An empty node, used as placeholder in some cases
private final class EmptyNode : Mapping {
    ///
    protected Location location_;

    ///
    public this (Location loc) scope @safe pure nothrow @nogc {
        this.location_ = loc;
    }

    public override inout(Mapping)  asMapping () inout return scope @safe  { return this; }
    public override inout(dub.internal.configy.backend.node.Sequence) asSequence () inout return scope @safe { return null; }
    public override inout(Scalar)   asScalar () inout return scope @safe   { return null; }

    ///
    public override Type type () const scope @safe nothrow { return Type.Mapping; }

    public override Location location () const scope @safe nothrow { return this.location_; }

    ///
    public override size_t length () const scope @safe { return 0; }

    ///
    public override int opApply (scope MapIterator dg) scope { return 0; }
}
