/*******************************************************************************

    An implementation of `Filesystem` using vibe.d functions

*******************************************************************************/

module dub.internal.io.realfs;

public import dub.internal.io.filesystem;

/// Ditto
public final class RealFS : Filesystem {
    static import dub.internal.vibecompat.core.file;
    static import std.file;

    ///
    private NativePath path_;

    ///
    public this (NativePath cwd = NativePath(std.file.getcwd()))
        scope @safe pure nothrow @nogc
    {
        this.path_ = cwd;
    }

    public override NativePath getcwd () const scope
    {
        return this.path_;
    }

    ///
    public override void chdir (in NativePath path) scope
    {
        std.file.chdir(path.toNativeString());
    }

    ///
    protected override bool existsDirectory (in NativePath path) const scope
	{
		return dub.internal.vibecompat.core.file.existsDirectory(path);
	}

	/// Ditto
	protected override void mkdir (in NativePath path) scope
	{
		dub.internal.vibecompat.core.file.ensureDirectory(path);
	}

	/// Ditto
	protected override bool existsFile (in NativePath path) const scope
	{
		return dub.internal.vibecompat.core.file.existsFile(path);
	}

	/// Ditto
	protected override void writeFile (in NativePath path, const(ubyte)[] data)
        scope
	{
		return dub.internal.vibecompat.core.file.writeFile(path, data);
	}

    /// Reads a file, returns the content as `ubyte[]`
    public override ubyte[] readFile (in NativePath path) const scope
    {
        return cast(ubyte[]) std.file.read(path.toNativeString());
    }

	/// Ditto
	protected override string readText (in NativePath path) const scope
	{
		return dub.internal.vibecompat.core.file.readText(path);
	}

	/// Ditto
	protected override IterateDirDg iterateDirectory (in NativePath path) scope
	{
		return dub.internal.vibecompat.core.file.iterateDirectory(path);
	}

	/// Ditto
	protected override void removeFile (in NativePath path, bool force = false) scope
	{
		return std.file.remove(path.toNativeString());
	}

    ///
    public override void removeDir (in NativePath path, bool force = false)
    {
        if (force)
            std.file.rmdirRecurse(path.toNativeString());
        else
            std.file.rmdir(path.toNativeString());
    }

	/// Ditto
	protected override void setTimes (in NativePath path, in SysTime accessTime,
		in SysTime modificationTime)
	{
		std.file.setTimes(
			path.toNativeString(), accessTime, modificationTime);
	}

	/// Ditto
	protected override void setAttributes (in NativePath path, uint attributes)
	{
		std.file.setAttributes(path.toNativeString(), attributes);
	}
}
