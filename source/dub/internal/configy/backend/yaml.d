/*******************************************************************************

    A backend that can parse YAML (and JSON) documents

    This is the original backend for Configy: it can parse YAML document
    (and JSON which YAML is a superset of). It uses D-YAML as a backend itself.

*******************************************************************************/

module dub.internal.configy.backend.yaml;

import dub.internal.configy.backend.node;

import dub.internal.dyaml.exception;
static import YN = dub.internal.dyaml.node;
import dub.internal.dyaml.loader;

import std.exception;
import std.format;

/**
 * Parses a file at `path` and return a node suitable for `parseConfig`
 *
 * Parses a file located at `path`, expected to contain YAML (or JSON),
 * and return a node that can be passed to `configy.read : parseConfig`.
 *
 * Params:
 *   path = Path to the file to load.
 *
 * Returns:
 *   A mapping representing the document.
 *
 * Throws:
 *   If the file cannot be loaded or the root of the document is not a mapping.
 */
public YAMLMapping parseFile (string path) {
    auto root = Loader.fromFile(path).load();
    enforce(root.nodeID == YN.NodeID.mapping,
        "Expected root of document to be a mapping, not: %s"
        .format(root.nodeID));
    return new YAMLMapping(root);
}

/**
 * Parses YAML `content` and return a node suitable for `parseConfig`
 *
 * Parses a string expecting to contain properly formatted YAML / JSON,
 * with an optional associated path (or symbolic name) and returns a node
 * that can then be passed to `configy.read : parseConfig`.
 *
 * Params:
 *   content = Content of the YAML / JSON document to read.
 *   path = Path to associate to the content. It may be `null`.
 *
 * Returns:
 *   A mapping representing the document.
 *
 * Throws:
 *   If loading the content failed.
 */
public YAMLNode parseString (string content, string path) {
    auto loader = Loader.fromString(content);
    loader.name = path;
    auto root = loader.load();
    enforce(root.nodeID == YN.NodeID.mapping,
        "Expected root of document to be a mapping, not: %s"
        .format(root.nodeID));
    return new YAMLMapping(root);
}

/// The base class for all YAML nodes
public abstract class YAMLNode : Node {
    /// The underlying data
    public YN.Node n;

    ///
    public this (YN.Node node, YN.NodeID expected) @safe pure {
        assert(node.nodeID == expected,
            "Node is not of expected type %s (it is a %s)"
            .format(expected, node.nodeID));
        this.n = node;
    }

    ///
    public override Location location () const scope @safe nothrow {
        const m = this.n.startMark();
        return Location(m.name, m.line + 1, m.column + 1);
    }

    public override inout(Mapping)  asMapping () inout scope return @safe  { return null; }
    public override inout(Sequence) asSequence () inout scope return @safe { return null; }
    public override inout(Scalar)   asScalar () inout scope return @safe   { return null; }
}


///
public final class YAMLMapping : YAMLNode, Mapping {
    ///
    public this (YN.Node node) @safe pure {
        super(node, YN.NodeID.mapping);
    }

    ///
    public override Type type () const scope @safe nothrow {
        return Type.Mapping;
    }

    ///
    public override inout(YAMLMapping) asMapping () inout scope return @safe {
        return this;
    }

    /// Returns: The length of this object (the number of entries in it)
    public override size_t length () const scope @safe {
        return this.n.length();
    }

    /// Iterates over this object, passing each entry to the `dg`
    public override int opApply (scope MapIterator dg) scope {
        foreach (scope pair; this.n.mapping()) {
            scope kn = nodeFactory(pair.key);
            scope kv = nodeFactory(pair.value);
            if (auto res = dg(kn, kv))
                return res;
        }
        return 0;
    }
}


///
public final class YAMLSequence : YAMLNode, Sequence {
    ///
    public this (YN.Node node) @safe pure {
        super(node, YN.NodeID.sequence);
    }

    ///
    public override Type type () const scope @safe nothrow {
        return Type.Sequence;
    }

    ///
    public override inout(YAMLSequence) asSequence () inout scope return @safe {
        return this;
    }

    /// Returns: The length of this sequence
    public override size_t length () const scope @safe {
        return this.n.length();
    }

    /// Iterates over this sequence, passing each entry to the `dg`
    public override int opApply (scope SeqIterator dg) scope {
        size_t idx;
        foreach (scope value; this.n.sequence()) {
            scope val = nodeFactory(value);
            if (auto res = dg(idx++, val))
                return res;
        }
        return 0;
    }
}


///
public final class YAMLScalar : YAMLNode, Scalar {
    ///
    public this (YN.Node node) @safe pure {
        super(node, YN.NodeID.scalar);
    }

    ///
    public override Type type () const scope @safe nothrow {
        return Type.Scalar;
    }

    ///
    public override inout(YAMLScalar) asScalar () inout scope return @safe {
        return this;
    }

    ///
    public override string str () const scope return @safe {
        return this.n.type() == YN.NodeType.null_ ? null : this.n.as!string;
    }
}

///
package(dub.internal.configy) inout(YAMLNode) nodeFactory (inout(YN.Node) node) @safe pure {
    final switch (node.nodeID) {
        case YN.NodeID.invalid:
            return null;
        case YN.NodeID.mapping:
            return new YAMLMapping(node);
        case YN.NodeID.sequence:
            return new YAMLSequence(node);
        case YN.NodeID.scalar:
            return new YAMLScalar(node);
    }
}
