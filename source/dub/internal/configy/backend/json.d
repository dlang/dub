/*******************************************************************************

    A backend using `dub.internal.vibecompat.data.json` as parser.

    This is a more JSON-compliant parser than the YAML one (which is used for
    parsing `dub.json` files) however it doesn't provide location informations
    that are as good as the YAML parser, hence it is only used for internal
    files that may have 'special' UTF-8 characters.

    See_Also:
      https://github.com/dlang-community/D-YAML/issues/342

*******************************************************************************/

module dub.internal.configy.backend.json;

import dub.internal.configy.backend.node;
import dub.internal.configy.utils;
import dub.internal.vibecompat.data.json;

import std.algorithm : among;
import std.exception;
import std.format;

/*******************************************************************************

    A wrapper around a JSON node

    This node is all types at once, however users should use one of the `asX`
    method to get some useful value out of it.

*******************************************************************************/

public class JSONNode : Node, Mapping, Sequence, Scalar {
    /// Underlying data
    private Json n;
    ///
    private string file;

    public this (Json node, string file) @safe {
        this.n = node;
        this.file = file;
    }

    public override Location location () const scope @safe nothrow {
        // No column information
        version (JsonLineNumbers)
            return Location(this.file, this.n.line);
        else
            return Location(this.file, 0);
    }

    public override Type type () const scope @safe nothrow {
        final switch (this.n.type()) {
            // Treat `null` and `undefined` as empty mapping
            case Json.Type.null_:
            case Json.Type.undefined:
            case Json.Type.object:
                return Node.Type.Mapping;
            case Json.Type.array:
                return Node.Type.Sequence;
            case Json.Type.bool_:
            case Json.Type.int_:
            case Json.Type.bigInt:
            case Json.Type.float_:
            case Json.Type.string:
                return Node.Type.Scalar;
        }
    }

    public override inout(Mapping) asMapping () inout scope return @safe {
        return this.type() == Node.Type.Mapping ? this : null;
    }
    public override inout(Sequence) asSequence () inout scope return @safe {
        return this.type() == Node.Type.Sequence ? this : null;
    }
    public override inout(Scalar) asScalar () inout scope return @safe {
        // undefined and null can be used as scalar if one so desire
        return this.n.type().among(Json.Type.object, Json.Type.array) ? null : this;
    }

    public override string str () const scope return @safe {
        return this.n.to!string;
    }
    public override size_t length () const scope @safe {
        return this.n.length();
    }
    public override int opApply (scope MapIterator dg) scope {
        foreach (ref string idx, ref Json val; this.n) {
            scope nIdx = new JSONNode(Json(idx), this.file);
            version (JsonLineNumbers) nIdx.n.line = val.line;
            scope Node nVal = new JSONNode(val, this.file);
            if (auto res = dg(nIdx, nVal))
                return res;
        }
        return 0;
    }
    public override int opApply (scope SeqIterator dg) scope {
        foreach (size_t idx, ref Json val; this.n) {
            scope nVal = new JSONNode(val, this.file);
            if (auto res = dg(idx, nVal))
                return res;
        }
        return 0;
    }
}
