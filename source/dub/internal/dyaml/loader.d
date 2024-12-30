
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// Class used to load YAML documents.
module dub.internal.dyaml.loader;


import std.exception;
import std.file;
import std.stdio : File;
import std.string;

import dub.internal.dyaml.composer;
import dub.internal.dyaml.constructor;
import dub.internal.dyaml.event;
import dub.internal.dyaml.exception;
import dub.internal.dyaml.node;
import dub.internal.dyaml.parser;
import dub.internal.dyaml.reader;
import dub.internal.dyaml.resolver;
import dub.internal.dyaml.scanner;
import dub.internal.dyaml.token;


/** Loads YAML documents from files or char[].
 *
 * User specified Constructor and/or Resolver can be used to support new
 * tags / data types.
 */
struct Loader
{
    private:
        // Assembles YAML documents
        Composer composer_;
        // Are we done loading?
        bool done_;
        // Last node read from stream
        Node currentNode;
        // Has the range interface been initialized yet?
        bool rangeInitialized;

    public:
        @disable int opCmp(ref Loader);
        @disable bool opEquals(ref Loader);

        /** Construct a Loader to load YAML from a file.
         *
         * Params:  filename = Name of the file to load from.
         *          file = Already-opened file to load from.
         *
         * Throws:  YAMLException if the file could not be opened or read.
         */
         static Loader fromFile(string filename) @trusted
         {
            try
            {
                auto loader = Loader(std.file.read(filename), filename);
                return loader;
            }
            catch(FileException e)
            {
                throw new YAMLException("Unable to open file %s for YAML loading: %s"
                                        .format(filename, e.msg), e.file, e.line);
            }
         }
         /// ditto
         static Loader fromFile(File file) @system
         {
            auto loader = Loader(file.byChunk(4096).join, file.name);
            return loader;
         }

        /** Construct a Loader to load YAML from a string.
         *
         * Params:
         *   data = String to load YAML from. The char[] version $(B will)
         *          overwrite its input during parsing as D:YAML reuses memory.
         *   filename = The filename to give to the Loader, defaults to `"<unknown>"`
         *
         * Returns: Loader loading YAML from given string.
         *
         * Throws:
         *
         * YAMLException if data could not be read (e.g. a decoding error)
         */
        static Loader fromString(char[] data, string filename = "<unknown>") @safe
        {
            return Loader(cast(ubyte[])data, filename);
        }
        /// Ditto
        static Loader fromString(string data, string filename = "<unknown>") @safe
        {
            return fromString(data.dup, filename);
        }
        /// Load  a char[].
        @safe unittest
        {
            assert(Loader.fromString("42".dup).load().as!int == 42);
        }
        /// Load a string.
        @safe unittest
        {
            assert(Loader.fromString("42").load().as!int == 42);
        }

        /** Construct a Loader to load YAML from a buffer.
         *
         * Params: yamlData = Buffer with YAML data to load. This may be e.g. a file
         *                    loaded to memory or a string with YAML data. Note that
         *                    buffer $(B will) be overwritten, as D:YAML minimizes
         *                    memory allocations by reusing the input _buffer.
         *                    $(B Must not be deleted or modified by the user  as long
         *                    as nodes loaded by this Loader are in use!) - Nodes may
         *                    refer to data in this buffer.
         *
         * Note that D:YAML looks for byte-order-marks YAML files encoded in
         * UTF-16/UTF-32 (and sometimes UTF-8) use to specify the encoding and
         * endianness, so it should be enough to load an entire file to a buffer and
         * pass it to D:YAML, regardless of Unicode encoding.
         *
         * Throws:  YAMLException if yamlData contains data illegal in YAML.
         */
        static Loader fromBuffer(ubyte[] yamlData) @safe
        {
            return Loader(yamlData);
        }
        /// Ditto
        static Loader fromBuffer(void[] yamlData) @system
        {
            return Loader(yamlData);
        }
        /// Ditto
        private this(void[] yamlData, string name = "<unknown>") @system
        {
            this(cast(ubyte[])yamlData, name);
        }
        /// Ditto
        private this(ubyte[] yamlData, string name = "<unknown>") @safe
        {
            try
            {
                auto reader = Reader(yamlData, name);
                auto parser = new Parser(Scanner(reader));
                composer_ = Composer(parser, Resolver.withDefaultResolvers);
            }
            catch(MarkedYAMLException e)
            {
                throw new LoaderException("Unable to open %s for YAML loading: %s"
                                        .format(name, e.msg), e.mark, e.file, e.line);
            }
        }


        /// Set stream _name. Used in debugging messages.
        ref inout(string) name() inout @safe return pure nothrow @nogc
        {
            return composer_.name;
        }

        /// Specify custom Resolver to use.
        auto ref resolver() pure @safe nothrow @nogc
        {
            return composer_.resolver;
        }

        /** Load single YAML document.
         *
         * If none or more than one YAML document is found, this throws a YAMLException.
         *
         * This can only be called once; this is enforced by contract.
         *
         * Returns: Root node of the document.
         *
         * Throws:  YAMLException if there wasn't exactly one document
         *          or on a YAML parsing error.
         */
        Node load() @safe
        {
            enforce(!empty,
                new LoaderException("Zero documents in stream", composer_.mark));
            auto output = front;
            popFront();
            enforce(empty,
                new LoaderException("More than one document in stream", composer_.mark));
            return output;
        }

        /** Implements the empty range primitive.
        *
        * If there's no more documents left in the stream, this will be true.
        *
        * Returns: `true` if no more documents left, `false` otherwise.
        */
        bool empty() @safe
        {
            // currentNode and done_ are both invalid until popFront is called once
            if (!rangeInitialized)
            {
                popFront();
            }
            return done_;
        }
        /** Implements the popFront range primitive.
        *
        * Reads the next document from the stream, if possible.
        */
        void popFront() @safe
        {
            scope(success) rangeInitialized = true;
            assert(!done_, "Loader.popFront called on empty range");
            try
            {
                if (composer_.checkNode())
                {
                    currentNode = composer_.getNode();
                }
                else
                {
                    done_ = true;
                }
            }
            catch(MarkedYAMLException e)
            {
                throw new LoaderException("Unable to load %s: %s"
                                        .format(name, e.msg), e.mark, e.mark2Label, e.mark2, e.file, e.line);
            }
        }
        /** Implements the front range primitive.
        *
        * Returns: the current document as a Node.
        */
        Node front() @safe
        {
            // currentNode and done_ are both invalid until popFront is called once
            if (!rangeInitialized)
            {
                popFront();
            }
            return currentNode;
        }
}
/// Load single YAML document from a file:
@safe unittest
{
    write("example.yaml", "Hello world!");
    auto rootNode = Loader.fromFile("example.yaml").load();
    assert(rootNode == "Hello world!");
}
/// Load single YAML document from an already-opened file:
@system unittest
{
    // Open a temporary file
    auto file = File.tmpfile;
    // Write valid YAML
    file.write("Hello world!");
    // Return to the beginning
    file.seek(0);
    // Load document
    auto rootNode = Loader.fromFile(file).load();
    assert(rootNode == "Hello world!");
}
/// Load all YAML documents from a file:
@safe unittest
{
    import std.array : array;
    import std.file : write;
    write("example.yaml",
        "---\n"~
        "Hello world!\n"~
        "...\n"~
        "---\n"~
        "Hello world 2!\n"~
        "...\n"
    );
    auto nodes = Loader.fromFile("example.yaml").array;
    assert(nodes.length == 2);
}
/// Iterate over YAML documents in a file, lazily loading them:
@safe unittest
{
    import std.file : write;
    write("example.yaml",
        "---\n"~
        "Hello world!\n"~
        "...\n"~
        "---\n"~
        "Hello world 2!\n"~
        "...\n"
    );
    auto loader = Loader.fromFile("example.yaml");

    foreach(ref node; loader)
    {
        //Do something
    }
}
/// Load YAML from a string:
@safe unittest
{
    string yaml_input = ("red:   '#ff0000'\n" ~
                        "green: '#00ff00'\n" ~
                        "blue:  '#0000ff'");

    auto colors = Loader.fromString(yaml_input).load();

    foreach(string color, string value; colors)
    {
        // Do something with the color and its value...
    }
}

/// Load a file into a buffer in memory and then load YAML from that buffer:
@safe unittest
{
    import std.file : read, write;
    import std.stdio : writeln;
    // Create a yaml document
    write("example.yaml",
        "---\n"~
        "Hello world!\n"~
        "...\n"~
        "---\n"~
        "Hello world 2!\n"~
        "...\n"
    );
    try
    {
        string buffer = readText("example.yaml");
        auto yamlNode = Loader.fromString(buffer);

        // Read data from yamlNode here...
    }
    catch(FileException e)
    {
        writeln("Failed to read file 'example.yaml'");
    }
}
/// Use a custom resolver to support custom data types and/or implicit tags:
@safe unittest
{
    import std.file : write;
    // Create a yaml document
    write("example.yaml",
        "---\n"~
        "Hello world!\n"~
        "...\n"
    );

    auto loader = Loader.fromFile("example.yaml");

    // Add resolver expressions here...
    // loader.resolver.addImplicitResolver(...);

    auto rootNode = loader.load();
}

//Issue #258 - https://github.com/dlang-community/D-YAML/issues/258
@safe unittest
{
    auto yaml = "{\n\"root\": {\n\t\"key\": \"value\"\n    }\n}";
    auto doc = Loader.fromString(yaml).load();
    assert(doc.isValid);
}

@safe unittest
{
    import std.exception : collectException;

    auto yaml = q"EOS
    value: invalid: string
EOS";
    auto filename = "invalid.yml";
    auto loader = Loader.fromString(yaml);
    loader.name = filename;

    Node unused;
    auto e = loader.load().collectException!LoaderException(unused);
    assert(e.mark.name == filename);
}
/// https://github.com/dlang-community/D-YAML/issues/325
@safe unittest
{
    assert(Loader.fromString("--- {x: a}").load()["x"] == "a");
}

// Ensure exceptions are thrown as appropriate
@safe unittest
{
    LoaderException e;
    // No documents
    e = collectException!LoaderException(Loader.fromString("", "filename.yaml").load());
    assert(e);
    with(e)
    {
        assert(mark.name == "filename.yaml");
        assert(mark.line == 0);
        assert(mark.column == 0);
    }
    // Too many documents
    e = collectException!LoaderException(Loader.fromString("--- 4\n--- 6\n--- 5", "filename.yaml").load());
    assert(e, "No exception thrown");
    with(e)
    {
        assert(mark.name == "filename.yaml");
        // FIXME: should be position of second document, not end of file
        //assert(mark.line == 1);
        //assert(mark.column == 0);
    }
    // Invalid document
    e = collectException!LoaderException(Loader.fromString("[", "filename.yaml").load());
    assert(e, "No exception thrown");
    with(e)
    {
        assert(mark.name == "filename.yaml");
        // FIXME: should be position of second document, not end of file
        assert(mark.line == 0);
        assert(mark.column == 1);
    }
}
