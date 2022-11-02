
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/**
 * YAML serializer.
 * Code based on PyYAML: http://www.pyyaml.org
 */
module dub.internal.dyaml.serializer;


import std.array;
import std.format;
import std.typecons;

import dub.internal.dyaml.emitter;
import dub.internal.dyaml.event;
import dub.internal.dyaml.exception;
import dub.internal.dyaml.node;
import dub.internal.dyaml.resolver;
import dub.internal.dyaml.tagdirective;
import dub.internal.dyaml.token;


package:

///Serializes represented YAML nodes, generating events which are then emitted by Emitter.
struct Serializer
{
    private:
        ///Resolver used to determine which tags are automaticaly resolvable.
        Resolver resolver_;

        ///Do all document starts have to be specified explicitly?
        Flag!"explicitStart" explicitStart_;
        ///Do all document ends have to be specified explicitly?
        Flag!"explicitEnd" explicitEnd_;
        ///YAML version string.
        string YAMLVersion_;

        ///Tag directives to emit.
        TagDirective[] tagDirectives_;

        //TODO Use something with more deterministic memory usage.
        ///Nodes with assigned anchors.
        string[Node] anchors_;
        ///Nodes with assigned anchors that are already serialized.
        bool[Node] serializedNodes_;
        ///ID of the last anchor generated.
        uint lastAnchorID_ = 0;

    public:
        /**
         * Construct a Serializer.
         *
         * Params:
         *          resolver      = Resolver used to determine which tags are automaticaly resolvable.
         *          explicitStart = Do all document starts have to be specified explicitly?
         *          explicitEnd   = Do all document ends have to be specified explicitly?
         *          YAMLVersion   = YAML version string.
         *          tagDirectives = Tag directives to emit.
         */
        this(Resolver resolver,
             const Flag!"explicitStart" explicitStart,
             const Flag!"explicitEnd" explicitEnd, string YAMLVersion,
             TagDirective[] tagDirectives) @safe
        {
            resolver_      = resolver;
            explicitStart_ = explicitStart;
            explicitEnd_   = explicitEnd;
            YAMLVersion_   = YAMLVersion;
            tagDirectives_ = tagDirectives;
        }

        ///Begin the stream.
        void startStream(EmitterT)(ref EmitterT emitter) @safe
        {
            emitter.emit(streamStartEvent(Mark(), Mark()));
        }

        ///End the stream.
        void endStream(EmitterT)(ref EmitterT emitter) @safe
        {
            emitter.emit(streamEndEvent(Mark(), Mark()));
        }

        ///Serialize a node, emitting it in the process.
        void serialize(EmitterT)(ref EmitterT emitter, ref Node node) @safe
        {
            emitter.emit(documentStartEvent(Mark(), Mark(), explicitStart_,
                                             YAMLVersion_, tagDirectives_));
            anchorNode(node);
            serializeNode(emitter, node);
            emitter.emit(documentEndEvent(Mark(), Mark(), explicitEnd_));
            serializedNodes_.destroy();
            anchors_.destroy();
            string[Node] emptyAnchors;
            anchors_ = emptyAnchors;
            lastAnchorID_ = 0;
        }

    private:
        /**
         * Determine if it's a good idea to add an anchor to a node.
         *
         * Used to prevent associating every single repeating scalar with an
         * anchor/alias - only nodes long enough can use anchors.
         *
         * Params:  node = Node to check for anchorability.
         *
         * Returns: True if the node is anchorable, false otherwise.
         */
        static bool anchorable(ref Node node) @safe
        {
            if(node.nodeID == NodeID.scalar)
            {
                return (node.type == NodeType.string) ? node.as!string.length > 64 :
                       (node.type == NodeType.binary) ? node.as!(ubyte[]).length > 64 :
                                               false;
            }
            return node.length > 2;
        }

        @safe unittest
        {
            import std.string : representation;
            auto shortString = "not much";
            auto longString = "A fairly long string that would be a good idea to add an anchor to";
            auto node1 = Node(shortString);
            auto node2 = Node(shortString.representation.dup);
            auto node3 = Node(longString);
            auto node4 = Node(longString.representation.dup);
            auto node5 = Node([node1]);
            auto node6 = Node([node1, node2, node3, node4]);
            assert(!anchorable(node1));
            assert(!anchorable(node2));
            assert(anchorable(node3));
            assert(anchorable(node4));
            assert(!anchorable(node5));
            assert(anchorable(node6));
        }

        ///Add an anchor to the node if it's anchorable and not anchored yet.
        void anchorNode(ref Node node) @safe
        {
            if(!anchorable(node)){return;}

            if((node in anchors_) !is null)
            {
                if(anchors_[node] is null)
                {
                    anchors_[node] = generateAnchor();
                }
                return;
            }

            anchors_.remove(node);
            final switch (node.nodeID)
            {
                case NodeID.mapping:
                    foreach(ref Node key, ref Node value; node)
                    {
                        anchorNode(key);
                        anchorNode(value);
                    }
                    break;
                case NodeID.sequence:
                    foreach(ref Node item; node)
                    {
                        anchorNode(item);
                    }
                    break;
                case NodeID.invalid:
                    assert(0);
                case NodeID.scalar:
            }
        }

        ///Generate and return a new anchor.
        string generateAnchor() @safe
        {
            ++lastAnchorID_;
            auto appender = appender!string();
            formattedWrite(appender, "id%03d", lastAnchorID_);
            return appender.data;
        }

        ///Serialize a node and all its subnodes.
        void serializeNode(EmitterT)(ref EmitterT emitter, ref Node node) @safe
        {
            //If the node has an anchor, emit an anchor (as aliasEvent) on the
            //first occurrence, save it in serializedNodes_, and emit an alias
            //if it reappears.
            string aliased;
            if(anchorable(node) && (node in anchors_) !is null)
            {
                aliased = anchors_[node];
                if((node in serializedNodes_) !is null)
                {
                    emitter.emit(aliasEvent(Mark(), Mark(), aliased));
                    return;
                }
                serializedNodes_[node] = true;
            }
            final switch (node.nodeID)
            {
                case NodeID.mapping:
                    const defaultTag = resolver_.defaultMappingTag;
                    const implicit = node.tag_ == defaultTag;
                    emitter.emit(mappingStartEvent(Mark(), Mark(), aliased, node.tag_,
                                                    implicit, node.collectionStyle));
                    foreach(ref Node key, ref Node value; node)
                    {
                        serializeNode(emitter, key);
                        serializeNode(emitter, value);
                    }
                    emitter.emit(mappingEndEvent(Mark(), Mark()));
                    return;
                case NodeID.sequence:
                    const defaultTag = resolver_.defaultSequenceTag;
                    const implicit = node.tag_ == defaultTag;
                    emitter.emit(sequenceStartEvent(Mark(), Mark(), aliased, node.tag_,
                                                     implicit, node.collectionStyle));
                    foreach(ref Node item; node)
                    {
                        serializeNode(emitter, item);
                    }
                    emitter.emit(sequenceEndEvent(Mark(), Mark()));
                    return;
                case NodeID.scalar:
                    assert(node.type == NodeType.string, "Scalar node type must be string before serialized");
                    auto value = node.as!string;
                    const detectedTag = resolver_.resolve(NodeID.scalar, null, value, true);
                    const bool isDetected = node.tag_ == detectedTag;

                    emitter.emit(scalarEvent(Mark(), Mark(), aliased, node.tag_,
                                  isDetected, value.idup, node.scalarStyle));
                    return;
                case NodeID.invalid:
                    assert(0);
            }
        }
}

// Issue #244
@safe unittest
{
    import dub.internal.dyaml.dumper : dumper;
    auto node = Node([
        Node.Pair(
            Node(""),
            Node([
                Node([
                    Node.Pair(
                        Node("d"),
                        Node([
                            Node([
                                Node.Pair(
                                    Node("c"),
                                    Node("")
                                ),
                                Node.Pair(
                                    Node("b"),
                                    Node("")
                                ),
                                Node.Pair(
                                    Node(""),
                                    Node("")
                                )
                            ])
                        ])
                    ),
                ]),
                Node([
                    Node.Pair(
                        Node("d"),
                        Node([
                            Node(""),
                            Node(""),
                            Node([
                                Node.Pair(
                                    Node("c"),
                                    Node("")
                                ),
                                Node.Pair(
                                    Node("b"),
                                    Node("")
                                ),
                                Node.Pair(
                                    Node(""),
                                    Node("")
                                )
                            ])
                        ])
                    ),
                    Node.Pair(
                        Node("z"),
                        Node("")
                    ),
                    Node.Pair(
                        Node(""),
                        Node("")
                    )
                ]),
                Node("")
            ])
        ),
        Node.Pair(
            Node("g"),
            Node("")
        ),
        Node.Pair(
            Node("h"),
            Node("")
        ),
    ]);

    auto stream = appender!string();
    dumper().dump(stream, node);
}
