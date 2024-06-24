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
    public this () scope
    {
        this.cwd = new FSEntry();
    }

    public override NativePath getcwd () const scope
    {
        return this.cwd.path();
    }

    ///
    public override bool existsDirectory (in NativePath path) const scope
    {
        auto entry = this.cwd.lookup(path);
        return entry !is null && entry.isDirectory();
    }

    /// Ditto
    public override void mkdir (in NativePath path) scope
    {
        this.cwd.mkdir(path);
    }

    /// Ditto
    public override bool existsFile (in NativePath path) const scope
    {
        auto entry = this.cwd.lookup(path);
        return entry !is null && entry.isFile();
    }

    /// Ditto
    public override void writeFile (in NativePath path, const(ubyte)[] data)
        scope
    {
        enforce(!path.endsWithSlash(),
            "Cannot write to directory: " ~ path.toNativeString());
        if (auto file = this.cwd.lookup(path)) {
            // If the file already exists, override it
            enforce(file.isFile(),
                "Trying to write to directory: " ~ path.toNativeString());
            file.content = data.dup;
        } else {
            auto p = this.cwd.getParent(path);
            auto file = new FSEntry(p, FSEntry.Type.File, path.head.name());
            file.content = data.dup;
            p.children ~= file;
        }
    }

    /// Reads a file, returns the content as `ubyte[]`
    public override ubyte[] readFile (in NativePath path) const scope
    {
        auto entry = this.cwd.lookup(path);
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
        auto dir = this.cwd.lookup(path);
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

    /// Ditto
    public override void removeFile (in NativePath path, bool force = false) scope
    {
        return this.cwd.removeFile(path);
    }

    ///
    public override void removeDir (in NativePath path, bool force = false)
    {
        this.cwd.removeDir(path, force);
    }

    /// Ditto
    public override void setTimes (in NativePath path, in SysTime accessTime,
        in SysTime modificationTime)
    {
        auto e = this.cwd.lookup(path);
        enforce(e !is null,
            "setTimes: No such file or directory: " ~ path.toNativeString());
        e.setTimes(accessTime, modificationTime);
    }

    /// Ditto
    public override void setAttributes (in NativePath path, uint attributes)
    {
        auto e = this.cwd.lookup(path);
        enforce(e !is null,
            "setAttributes: No such file or directory: " ~ path.toNativeString());
        e.setAttributes(attributes);
    }

    /**
     * Converts an `Filesystem` and its children to a `ZipFile`
     */
    public ubyte[] serializeToZip (string rootPath) {
        import std.path;
        import std.zip;

        scope z = new ZipArchive();
        void addToZip(scope string dir, scope FSEntry e) {
            auto m = new ArchiveMember();
            m.name = dir.buildPath(e.name);
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
                    addToZip(m.name, c);
                break;
            case FSEntry.Type.File:
                m.expandedData = e.content;
                z.addMember(m);
            }
        }
        addToZip(rootPath, this.cwd);
        return cast(ubyte[]) z.build();
    }
}

/// The backing logic behind `MockFS`
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
        // Avoid 'DOS File Times cannot hold dates prior to 1980.' exception
        import std.datetime.date;
        SysTime DefaultTime = SysTime(DateTime(2020, 01, 01));

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
        foreach (c; this.children)
            if (c.name == name)
                return c;
        return null;
    }

    /// Get an arbitrarily nested children node
    protected inout(FSEntry) lookup(NativePath path) inout return scope
    {
        auto relp = this.relativePath(path);
        relp.normalize(); // try to get rid of `..`
        if (relp.empty)
            return this;
        auto segments = relp.bySegment;
        if (auto c = this.lookup(segments.front.name)) {
            segments.popFront();
            return !segments.empty ? c.lookup(NativePath(segments)) : c;
        }
        return null;
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
            return this;

        // If we're not in the right `FSEntry`, recurse
        const parentPath = path.parentPath();
        auto p = this.lookup(parentPath);
        enforce(silent || p !is null,
            "No such directory: " ~ parentPath.toNativeString());
        enforce(p is null || p.attributes.type == Type.Directory,
            "Parent path is not a directory: " ~ parentPath.toNativeString());
        return p;
    }

    /// Returns: A path relative to `this.path`
    protected NativePath relativePath(NativePath path) const scope
    {
        assert(!path.absolute() || path.startsWith(this.path),
               "Calling relativePath with a differently rooted path");
        return path.absolute() ? path.relativeTo(this.path) : path;
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
            return NativePath("/");
        auto thisPath = this.parent.path ~ this.name;
        thisPath.endsWithSlash = (this.attributes.type == Type.Directory);
        return thisPath;
    }

    /// Implements `mkdir -p`, returns the created directory
    public FSEntry mkdir (in NativePath path) scope
    {
        auto relp = this.relativePath(path);
        // Check if the child already exists
        auto segments = relp.bySegment;
        auto child = this.lookup(segments.front.name);
        if (child is null) {
            child = new FSEntry(this, Type.Directory, segments.front.name);
            this.children ~= child;
        }
        // Recurse if needed
        segments.popFront();
        return !segments.empty ? child.mkdir(NativePath(segments)) : child;
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
    public void removeFile (in NativePath path, bool force = false)
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
            enforce(p.children[idx].attributes.type == Type.File,
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
    public void removeDir (in NativePath path, bool force = false)
    {
        import std.algorithm.searching : countUntil;

        assert(!path.empty, "Empty path provided to `removeFile`");
        auto p = this.getParent(path, force);
        const idx = p.children.countUntil!(e => e.name == path.head.name());
        if (idx < 0) {
            enforce(force,
                "removeDir: No such directory: " ~ path.toNativeString());
        } else {
            enforce(p.children[idx].attributes.type == Type.Directory,
                "removeDir called on a file: " ~ path.toNativeString());
            enforce(force || p.children[idx].children.length == 0,
                "removeDir called on non-empty directory: " ~ path.toNativeString());
            p.children = p.children[0 .. idx] ~ p.children[idx + 1 .. $];
        }
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
