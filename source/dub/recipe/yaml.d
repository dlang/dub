/*******************************************************************************

    YAML serialization helper

*******************************************************************************/

module dub.recipe.yaml;

import dub.internal.vibecompat.data.json;

import std.algorithm;
import std.array : appender, Appender;
import std.bigint;
import std.format;
import std.range;

package string toYAML (Json json) {
    auto sb = appender!string();
    serializeHelper(json, sb, 0);
    return sb.data;
}

package void toYAML (R) (Json json, ref R dst) {
    serializeHelper(json, dst, 0);
}

private void serializeHelper (R) (Json value, ref R dst, size_t indent, bool skipFirstIndent = false) {
    final switch (value.type) {
        case Json.Type.object:
            foreach (fieldName; FieldOrder) {
                if (auto ptr = fieldName in value) {
                    serializeField(dst, fieldName, *ptr, skipFirstIndent ? 0 : indent);
                    skipFirstIndent = false;
                }
            }
            foreach (string key, fieldValue; value) {
                if (FieldOrder.canFind(key)) continue;
                serializeField(dst, key, fieldValue, skipFirstIndent ? 0 : indent);
                skipFirstIndent = false;
            }
            break;
        case Json.Type.array:
            foreach (size_t idx, element; value) {
                formattedWrite(dst, "%*.*0$s- ", indent, ` `);

                if (element.isScalar) {
                    serializeHelper(element, dst, 0);
                } else {
                    serializeHelper(element, dst, indent + 2, true);
                }
            }
            break;
        case Json.Type.string:
            formattedWrite(dst, `"%s"`, value.get!string);
            break;
        case Json.Type.bool_:
            dst.put(value.get!bool ? "true" : "false");
            break;
        case Json.Type.null_:
            dst.put("null");
            break;
        case Json.Type.int_:
            formattedWrite(dst, "%s", value.get!long);
            break;
        case Json.Type.bigInt:
            formattedWrite(dst, "%s", value.get!BigInt);
            break;
        case Json.Type.float_:
            formattedWrite(dst, "%s", value.get!double);
            break;
        case Json.Type.undefined:
            break;
    }
    if (value.isScalar)
        dst.put("\n");
}

private void serializeField (R) (ref R dst, string key, Json fieldValue, size_t indent) {
    formattedWrite(dst, "%*.*0$s%s:", indent, ` `, key);
    if (fieldValue.isScalar) {
        dst.put(" ");
        serializeHelper(fieldValue, dst, 0);
    } else {
        dst.put("\n");
        serializeHelper(fieldValue, dst, indent + 2);
    }
}

private bool isScalar(Json value) {
    return value.type != Json.Type.object && value.type != Json.Type.array;
}

/// To get a better formatted YAML out of the box
private immutable FieldOrder = [
    "name", "description", "homepage", "authors", "copyright", "license",
    "toolchainRequirements", "mainSourceFile", "dependencies", "configurations",
];
