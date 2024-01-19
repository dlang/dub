/*******************************************************************************

    An unittest implementation of `Filesystem`

*******************************************************************************/

module dub.internal.io.mockfs;

public import dub.internal.io.filesystem;

static import dub.internal.vibecompat.core.file;

import std.algorithm;
import std.exception;
import std.range;
import std.string;

/// Ditto
public final class MockFS : Filesystem {
    ///
    private FSEntry cwd;

    ///
    private FSEntry root;

    /***************************************************************************

        Instantiate a `MockFS` with a given root

        A parameter-less overload exists for POSIX, while on Windows a parameter
        needs to be provided, as Windows' root has a drive letter.

        Params:
          root = The name of the root, e.g. "C:\"

    ***************************************************************************/

    version (Windows) {
        public this (char dir = 'C') scope
        {
            this.root = this.cwd = new FSEntry();
            this.root.name = [ dir, ':' ];
        }
    } else {
        public this () scope
        {
            this.root = this.cwd = new FSEntry();
        }
    }

    public override NativePath getcwd () const scope
    {
        return this.cwd.path();
    }

    public override void chdir (in NativePath path) scope
    {
        auto tmp = this.lookup(path);
        enforce(tmp !is null, "No such directory: " ~ path.toNativeString());
        enforce(tmp.isDirectory(), "Cannot chdir into non-directory: " ~ path.toNativeString());
        this.cwd = tmp;
    }

    ///
    public override bool existsDirectory (in NativePath path) const scope
    {
        auto entry = this.lookup(path);
        return entry !is null && entry.isDirectory();
    }

    /// Ditto
    public override void mkdir (in NativePath path) scope
    {
        import std.algorithm.iteration : reduce;

        const abs = path.absolute();
        auto segments = this.adaptPath(path);
        reduce!((FSEntry dir, segment) => dir.mkdir(segment.name))(
            (abs ? this.root : this.cwd), segments);
    }

    /// Ditto
    public override bool existsFile (in NativePath path) const scope
    {
        auto entry = this.lookup(path);
        return entry !is null && entry.isFile();
    }

    /// Ditto
    public override void writeFile (in NativePath path, const(ubyte)[] data)
        scope
    {
        enforce(!path.endsWithSlash(),
            "Cannot write to directory: " ~ path.toNativeString());
        if (auto file = this.lookup(path)) {
            // If the file already exists, override it
            enforce(file.isFile(),
                "Trying to write to directory: " ~ path.toNativeString());
            file.content = data.dup;
        } else {
            auto p = this.getParent(path);
            auto file = new FSEntry(p, FSEntry.Type.File, path.head.name());
            file.content = data.dup;
            p.children ~= file;
        }
    }

    /// Reads a file, returns the content as `ubyte[]`
    public override ubyte[] readFile (in NativePath path) const scope
    {
        auto entry = this.lookup(path);
        enforce(entry !is null, "No such file: " ~ path.toNativeString());
        enforce(entry.isFile(), "Trying to read a directory");
        // This is a hack to make poisoning a file possible.
        // However, it is rather crude and doesn't allow to poison directory.
        // Consider introducing a derived type to allow it.
        assert(entry.content != "poison".representation,
            "Trying to access poisoned path: " ~ path.toNativeString());
        return entry.content.dup;
    }

    /// Reads a file, returns the content as text
    public override string readText (in NativePath path) const scope
    {
        import std.utf : validate;

        const content = this.readFile(path);
        // Ignore BOM: If it's needed for a test, add support for it.
        validate(cast(const(char[])) content);
        // `readFile` just `dup` the content, so it's safe to cast.
        return cast(string) content;
    }

    /// Ditto
    public override IterateDirDg iterateDirectory (in NativePath path) scope
    {
        enforce(this.existsDirectory(path),
            path.toNativeString() ~ " does not exists or is not a directory");
        auto dir = this.lookup(path);
        int iterator(scope int delegate(ref dub.internal.vibecompat.core.file.FileInfo) del) {
            foreach (c; dir.children) {
                dub.internal.vibecompat.core.file.FileInfo fi;
                fi.name = c.name;
                fi.timeModified = c.attributes.modification;
                final switch (c.attributes.type) {
                case FSEntry.Type.File:
                    fi.size = c.content.length;
                    break;
                case FSEntry.Type.Directory:
                    fi.isDirectory = true;
                    break;
                }
                if (auto res = del(fi))
                    return res;
            }
            return 0;
        }
        return &iterator;
    }

    /** Remove a file
     *
     * Always error if the target is a directory.
     * Does not error if the target does not exists
     * and `force` is set to `true`.
     *
     * Params:
     *   path = Path to the file to remove
     *   force = Whether to ignore non-existing file,
     *           default to `false`.
     */
    public override void removeFile (in NativePath path, bool force = false)
    {
        import std.algorithm.searching : countUntil;

        assert(!path.empty, "Empty path provided to `removeFile`");
        enforce(!path.endsWithSlash(),
            "Cannot remove file with directory path: " ~ path.toNativeString());
        auto p = this.getParent(path, force);
        const idx = p.children.countUntil!(e => e.name == path.head.name());
        if (idx < 0) {
            enforce(force,
                "removeFile: No such file: " ~ path.toNativeString());
        } else {
            enforce(p.children[idx].attributes.type == FSEntry.Type.File,
                "removeFile called on a directory: " ~ path.toNativeString());
            p.children = p.children[0 .. idx] ~ p.children[idx + 1 .. $];
        }
    }

    /** Remove a directory
     *
     * Remove an existing empty directory.
     * If `force` is set to `true`, no error will be thrown
     * if the directory is empty or non-existing.
     *
     * Params:
     *   path = Path to the directory to remove
     *   force = Whether to ignore non-existing / non-empty directories,
     *           default to `false`.
     */
    public override void removeDir (in NativePath path, bool force = false)
    {
        import std.algorithm.searching : countUntil;

        assert(!path.empty, "Empty path provided to `removeFile`");
        auto p = this.getParent(path, force);
        const idx = p.children.countUntil!(e => e.name == path.head.name());
        if (idx < 0) {
            enforce(force,
                "removeDir: No such directory: " ~ path.toNativeString());
        } else {
            enforce(p.children[idx].attributes.type == FSEntry.Type.Directory,
                "removeDir called on a file: " ~ path.toNativeString());
            enforce(force || p.children[idx].children.length == 0,
                "removeDir called on non-empty directory: " ~ path.toNativeString());
            p.children = p.children[0 .. idx] ~ p.children[idx + 1 .. $];
        }
    }

    /// Ditto
    public override void setTimes (in NativePath path, in SysTime accessTime,
        in SysTime modificationTime)
    {
        auto e = this.lookup(path);
        enforce(e !is null,
            "setTimes: No such file or directory: " ~ path.toNativeString());
        e.setTimes(accessTime, modificationTime);
    }

    /// Ditto
    public override void setAttributes (in NativePath path, uint attributes)
    {
        auto e = this.lookup(path);
        enforce(e !is null,
            "setAttributes: No such file or directory: " ~ path.toNativeString());
        e.setAttributes(attributes);
    }

    /**
     * Converts an `Filesystem` and its children to a `ZipFile`
     *
     * Because a Zip file always contains a POSIX filesystem, this takes
     * the root path as PosixPath and uses it through the whole function.
     */
    public ubyte[] serializeToZip (PosixPath rootPath) {
        import std.path;
        import std.zip;

        scope z = new ZipArchive();
        void addToZip(scope PosixPath dir, scope FSEntry e) {
            if (e is this.root) {
                foreach (c; e.children)
                    addToZip(rootPath, c);
                return;
            }

            auto m = new ArchiveMember();
            const archivePath = dir ~ PosixPath(e.name);
            m.name = archivePath.toString();
            m.fileAttributes = e.attributes.attrs;
            m.time = e.attributes.modification;

            final switch (e.attributes.type) {
            case FSEntry.Type.Directory:
                // We need to ensure the directory entry ends with a slash
                // otherwise it will be considered as a file.
                if (m.name[$-1] != '/')
                    m.name ~= '/';
                z.addMember(m);
                foreach (c; e.children)
                    addToZip(archivePath, c);
                break;
            case FSEntry.Type.File:
                m.expandedData = e.content;
                z.addMember(m);
            }
        }
        addToZip(rootPath, this.cwd);
        return cast(ubyte[]) z.build();
    }

    /** Get the parent `FSEntry` of a `NativePath`
     *
     * If the parent doesn't exist, an `Exception` will be thrown
     * unless `silent` is provided. If the parent path is a file,
     * an `Exception` will be thrown regardless of `silent`.
     *
     * Params:
     *   path = The path to look up the parent for
     *   silent = Whether to error on non-existing parent,
     *            default to `false`.
     */
    protected inout(FSEntry) getParent(NativePath path, bool silent = false)
        inout return scope
    {
        // Relative path in the current directory
        if (!path.hasParentPath())
            return this.cwd;

        // If we're not in the right `FSEntry`, recurse
        const parentPath = path.parentPath();
        auto p = this.lookup(parentPath);
        enforce(silent || p !is null,
            "No such directory: " ~ parentPath.toNativeString());
        enforce(p is null || p.attributes.type == FSEntry.Type.Directory,
            "Parent path is not a directory: " ~ parentPath.toNativeString());
        return p;
    }

    /// Get an arbitrarily nested children node
    protected inout(FSEntry) lookup(NativePath path) inout return scope
    {
        import std.algorithm.iteration : reduce;

        const abs = path.absolute();
        auto segments = this.adaptPath(path);
        // Casting away constness because no good way to do this with `inout`,
        // but `FSEntry.lookup` is `inout` too.
        return cast(inout(FSEntry)) reduce!(
            (FSEntry dir, segment) => dir ? dir.lookup(segment.name) : null)
            (cast() (abs ? this.root : this.cwd), segments);
    }

    /// helper function for code common between `mkdir` and `lookup`
    private auto adaptPath (in NativePath path) const scope {
        if (!path.absolute()) return path.bySegment;
        auto segments = path.bySegment;
        // `library-nonet` (using vibe.d) has an empty front for absolute path,
        // while our built-in module (in vibecompat) does not.
        if (segments.front.name.length == 0)
            segments.popFront();
        // A path such as `C:\foo` gets turned into `[ "", "C:", "foo" ]`,
        // so after dropping the empty segment we need to drop the drive
        version (Windows) if (!segments.empty) {
            enforce(this.root.name == segments.front.name,
                "Cannot mkdir new drive '" ~ segments.front.name ~ '"');
            segments.popFront();
        }
        return segments;
    }
}

/*******************************************************************************

    Represents a node on the filesystem

    This class encapsulates operations which are node specific, such as looking
    up a child node, adding one, or setting properties.

*******************************************************************************/

public class FSEntry
{
    /// Type of file system entry
    public enum Type : ubyte {
        Directory,
        File,
    }

    /// List FSEntry attributes
    protected struct Attributes {
        /// The type of FSEntry, see `FSEntry.Type`
        public Type type;
        /// System-specific attributes for this `FSEntry`
        public uint attrs;
        /// Last access time
        public SysTime access;
        /// Last modification time
        public SysTime modification;
    }
    /// Ditto
    protected Attributes attributes;

    /// The name of this node
    protected string name;
    /// The parent of this entry (can be null for the root)
    protected FSEntry parent;
    union {
        /// Children for this FSEntry (with type == Directory)
        protected FSEntry[] children;
        /// Content for this FDEntry (with type == File)
        protected ubyte[] content;
    }

    /// Creates a new FSEntry
    package(dub) this (FSEntry p, Type t, string n)
    {
        assert(n.length);

        // Avoid 'DOS File Times cannot hold dates prior to 1980.' exception
        import std.datetime.date;
        SysTime DefaultTime = SysTime(DateTime(2020, 01, 01));

        assert(n.length > 0,
            "FSentry.this(%s, %s, %s) called with empty name"
            .format(p.path(), t, n));

        this.attributes.type = t;
        this.parent = p;
        this.name = n;
        this.attributes.access = DefaultTime;
        this.attributes.modification = DefaultTime;
    }

    /// Create the root of the filesystem, only usable from this module
    package(dub) this ()
    {
        import std.datetime.date;
        SysTime DefaultTime = SysTime(DateTime(2020, 01, 01));

        this.attributes.type = Type.Directory;
        this.attributes.access = DefaultTime;
        this.attributes.modification = DefaultTime;
    }

    /// Get a direct children node, returns `null` if it can't be found
    protected inout(FSEntry) lookup(string name) inout return scope
    {
        assert(!name.canFind('/'));
        if (name == ".")  return this;
        if (name == "..") return this.parent;
        foreach (c; this.children)
            if (c.name == name)
                return c;
        return null;
    }

    /*+*************************************************************************

        Utility function

        Below this banners are functions that are provided for the convenience
        of writing tests for `Dub`.

    ***************************************************************************/

    /// Prints a visual representation of the filesystem to stdout for debugging
    public void print(bool content = false) const scope
    {
        import std.range : repeat;
        static import std.stdio;

        size_t indent;
        for (auto p = &this.parent; (*p) !is null; p = &p.parent)
            indent++;
        // Don't print anything (even a newline) for root
        if (this.parent is null)
            std.stdio.write('/');
        else
            std.stdio.write('|', '-'.repeat(indent), ' ', this.name, ' ');

        final switch (this.attributes.type) {
        case Type.Directory:
            std.stdio.writeln('(', this.children.length, " entries):");
            foreach (c; this.children)
                c.print(content);
            break;
        case Type.File:
            if (!content)
                std.stdio.writeln('(', this.content.length, " bytes)");
            else if (this.name.endsWith(".json") || this.name.endsWith(".sdl"))
                std.stdio.writeln('(', this.content.length, " bytes): ",
                    cast(string) this.content);
            else
                std.stdio.writeln('(', this.content.length, " bytes): ",
                    this.content);
            break;
        }
    }

    /*+*************************************************************************

        Public filesystem functions

        Below this banners are functions which mimic the behavior of a file
        system.

    ***************************************************************************/

    /// Returns: The `path` of this FSEntry
    public NativePath path () const scope
    {
        if (this.parent is null)
            // The first runtime branch is for Windows, the second for POSIX
            return this.name ? NativePath(this.name) : NativePath("/");
        auto thisPath = this.parent.path ~ this.name;
        thisPath.endsWithSlash = (this.attributes.type == Type.Directory);
        return thisPath;
    }

    /// Implements `mkdir -p`, returns the created directory
    public FSEntry mkdir (string name) scope
    {
        // Check if the child already exists
        if (auto child = this.lookup(name))
            return child;

        this.children ~= new FSEntry(this, Type.Directory, name);
        return this.children[$-1];
    }

    ///
    public bool isFile () const scope
    {
        return this.attributes.type == Type.File;
    }

    ///
    public bool isDirectory () const scope
    {
        return this.attributes.type == Type.Directory;
    }

    /// Implement `std.file.setTimes`
    public void setTimes (in SysTime accessTime, in SysTime modificationTime)
    {
        this.attributes.access = accessTime;
        this.attributes.modification = modificationTime;
    }

    /// Implement `std.file.setAttributes`
    public void setAttributes (uint attributes)
    {
        this.attributes.attrs = attributes;
    }
}

unittest {
    alias P = NativePath;
    scope fs = new MockFS();

    version (Windows) immutable NativePath root = NativePath(`C:`);
    else              immutable NativePath root = NativePath(`/`);

    assert(fs.getcwd == root, fs.getcwd.toString());
    // We shouldn't be able to chdir into a non-existent directory
    assertThrown(fs.chdir(P("foo/bar")));
    // Even with an absolute path
    assertThrown(fs.chdir(root ~ "foo/bar"));
    // Now we should be
    fs.mkdir(P("foo/bar"));
    fs.chdir(P("foo/bar"));
    assert(fs.getcwd == root ~ "foo/bar/", fs.getcwd.toNativeString());
    // chdir with absolute path
    fs.chdir(root ~ "foo");
    assert(fs.getcwd == root ~ "foo/", fs.getcwd.toNativeString());
    // This still does not exists
    assertThrown(fs.chdir(root ~ "bar"));
    // Test pseudo entries / meta locations
    version (POSIX) {
        fs.chdir(P("."));
        assert(fs.getcwd == P("/foo/"));
        fs.chdir(P(".."));
        assert(fs.getcwd == P("/"));
        fs.chdir(P("."));
        assert(fs.getcwd == P("/"));
        fs.chdir(NativePath("/foo/bar/../"));
        assert(fs.getcwd == P("/foo/"));
    }
}
