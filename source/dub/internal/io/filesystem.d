/**
 * An abstract filesystem representation
 *
 * This interface allows to represent the file system to various part of Dub.
 * Instead of direct use of `std.file`, an implementation of this interface can
 * be used, allowing to mock all I/O in unittest on a thread-local basis.
 */
module dub.internal.io.filesystem;

public import std.datetime.systime;

public import dub.internal.vibecompat.inet.path;

/// Ditto
public interface Filesystem
{
    static import dub.internal.vibecompat.core.file;

    /// TODO: Remove, the API should be improved
    public alias IterateDirDg = int delegate(
        scope int delegate(ref dub.internal.vibecompat.core.file.FileInfo));

    /// Ditto
    public IterateDirDg iterateDirectory (in NativePath path) scope;

    /// Returns: The `path` of this FSEntry
    public abstract NativePath getcwd () const scope;

    /// Change current directory to `path`. Equivalent to `cd` in shell.
    public abstract void chdir (in NativePath path) scope;

    /**
     * Implements `mkdir -p`: Create a directory and every intermediary
     *
     * There is no way to error out on intermediate directory,
     * like standard mkdir does. If you want this behavior,
     * simply check (`existsDirectory`) if the parent directory exists.
     *
     * Params:
     *   path = The path of the directory to be created.
     */
    public abstract void mkdir (in NativePath path) scope;

    /// Checks the existence of a file
    public abstract bool existsFile (in NativePath path) const scope;

    /// Checks the existence of a directory
    public abstract bool existsDirectory (in NativePath path) const scope;

    /// Reads a file, returns the content as `ubyte[]`
    public abstract ubyte[] readFile (in NativePath path) const scope;

    /// Reads a file, returns the content as text
    public abstract string readText (in NativePath path) const scope;

    /// Write to this file
    public final void writeFile (in NativePath path, const(char)[] data) scope
    {
        import std.string : representation;

        this.writeFile(path, data.representation);
    }

    /// Ditto
    public abstract void writeFile (in NativePath path, const(ubyte)[] data) scope;

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
    public void removeFile (in NativePath path, bool force = false);

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
    public void removeDir (in NativePath path, bool force = false);

    /// Implement `std.file.setTimes`
    public void setTimes (in NativePath path, in SysTime accessTime,
        in SysTime modificationTime);

    /// Implement `std.file.setAttributes`
    public void setAttributes (in NativePath path, uint attributes);
}
