/*******************************************************************************

    Abstract away the underlying node type implementation

    While Configy was originally written to be a YAML configuration parser,
    it has been extended to support other kind of configuration.
    All one needs is to define a class overriding `ConfigNode` and implementing
    the appropriate methods.

*******************************************************************************/

module dub.internal.configy.backend.node;

import dub.internal.configy.utils;

import std.format;

/*******************************************************************************

    An abstract `Node` in a structured document

    A `Node` is an abstraction that should be generic enough for any format.
    `Node`s can be of different types: Mapping (object), `Sequence` (array),
    or simply scalar (numbers, string, advanced types like datetime in YAML).

*******************************************************************************/

public interface Node {
    /// The `Node` type
    public enum Type {
        /// A node that has no valid representation
        Invalid,
        /// A mapping has named keys and associated values, e.g. a JSON object
        /// or an associative array in D
        Mapping,
        /// Correspond to an array in D / JSON / YAML
        Sequence,
        /// A value that can be a string, integer, or whatever the underlying
        /// library supports as native type (e.g. YAML's datetime).
        Scalar,
    }

    /// Returns: The `Location` of this `Node` in the file
    public Location location () const scope @safe nothrow;

    /// Returns: The `type` of the `Node`
    public Type type () const scope @safe nothrow;

    /// Returns: `this` typed as a `Mapping`, or `null` if it isn't a mapping
    public inout(Mapping) asMapping () inout scope return @safe;
    /// Returns: `this` typed as a `Sequence`, or `null` if it isn't a sequence
    public inout(Sequence) asSequence () inout scope return @safe;
    /// Returns: `this` typed as a `Scalar`, or `null` if it isn't a scalar
    public inout(Scalar) asScalar () inout scope return @safe;
}

/// Represent a mapping / object in a document
public interface Mapping : Node {
    /// The delegate type to iterate over a mapping
    public alias MapIterator = int delegate(
        scope Node key, scope Node value) @system;

    /// Returns: The length of this object (the number of entries in it)
    public size_t length () const scope @safe;

    /// Iterates over this object, passing each entry to the `dg`
    public int opApply (scope MapIterator dg) scope;
}

/// Represent a sequence / array in a document
public interface Sequence : Node {
    /// The delegate type to iterate over a sequence
    public alias SeqIterator = int delegate(
        size_t idx, scope Node value) @system;

    /// Returns: The length of this sequence (the number of entries in it)
    public size_t length () const scope @safe;

    /// Iterates over this sequence, passing each entry and index to the `dg`
    public int opApply (scope SeqIterator dg) scope;
}

/// Represent a scalar: anything that can be represented as a simple string
public interface Scalar : Node {
    /// Returns: This `Scalar` represented as `string`
    public string str () const scope return @safe;
}

/// The location of the node in the file (if there is a file)
public struct Location {
    /**
     * The file in which the node resides.
     *
     * Non-file based backend may use this field to store other information,
     * e.g. variable name or command-line argument name.
     */
    public string file;
    /// Line at which the error happen (or 0 if no line information is available)
    public size_t line;
    /// Column at which the error happen (or 0 if no column information is available)
    /// Column information is only printed if there's a line information.
    public size_t column;

    /// Returns: A human-readable representation
    public string toString () const scope @safe {
        string buffer;
        this.toString((in char[] data) { buffer ~= data; }, FormatSpec!char("%s"));
        return buffer;
    }

    /// Format this `Location` into a human-readable representation
    /// Returns: Whether something has been written to the sink.
    public bool toString (scope SinkType sink,
        in FormatSpec!char spec = FormatSpec!char("%s")) const scope @safe {
        import core.internal.string : unsignedToTempString;

        if (!this.file.length)
            return false;

        const useColors = spec.spec == 'S';
        char[20] buffer = void;

        if (useColors) sink(Yellow);
        sink(this.file);
        if (useColors) sink(Reset);

        if (!this.line) return true;
        sink("(");
        if (useColors) sink(Cyan);
        sink(unsignedToTempString(this.line, buffer));
        if (useColors) sink(Reset);
        if (this.column) {
            sink(":");
            if (useColors) sink(Cyan);
            sink(unsignedToTempString(this.column, buffer));
            if (useColors) sink(Reset);
        }
        sink(")");
        return true;
    }
}

/// Returns: A string representation of `type`
public string toString (Node.Type type) @safe pure nothrow @nogc {
    final switch (type) {
        case Node.Type.Mapping:
            return "mapping";
        case Node.Type.Sequence:
            return "sequence";
        case Node.Type.Scalar:
            return "scalar";
        case Node.Type.Invalid:
            return "invalid";
    }
}

/// Convenience function to compare a node to a specific scalar
public bool isScalarValue (scope const Node node, scope const char[] value) @safe {
    if (auto sc = node.asScalar())
        return sc.isScalarValue(value);
    return false;
}

/// Ditto
public bool isScalarValue (scope const Scalar node, scope const char[] value) @safe {
    return node.str() == value;
}


/// Convenience function to find a specific key in a mapping
public RT withNode (DGT : RT delegate(scope Node, scope Node), RT)
    (scope Mapping map, string key, scope DGT dg) {
    foreach (scope k, scope v; map)
        if (k.isScalarValue(key))
            return dg(k, v);
    return dg(null, null);
}

/// Ditto
public RT withNode (DGT : RT function(scope Node, scope Node), RT)
    (scope Mapping map, string key, scope DGT dg) {
    foreach (scope k, scope v; map)
        if (k.isScalarValue(key))
            return dg(k, v);
    return dg(null, null);
}

/// Ditto
public bool has (scope Mapping map, string key) {
    return map.withNode(key, (scope Node key, scope Node value) => value !is null);
}
