/**
	Provides methods to generate temporary file names and folders and
	automatically clean them up on program exit.

	Copyright: © 2012 Matthias Dondorff, © 2012-2023 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff, Sönke Ludwig, Jan Jurzitza
*/
module dub.internal.temp_files;

import std.file;

import dub.internal.vibecompat.core.file;

NativePath getTempDir()
{
	return NativePath(std.file.tempDir());
}

NativePath getTempFile(string prefix, string extension = null)
{
	import std.uuid : randomUUID;
	import std.array: replace;

	string fileName = prefix ~ "-" ~ randomUUID.toString() ~ extension;

	if (extension !is null && extension == ".d")
		fileName = fileName.replace("-", "_");

	auto path = getTempDir() ~ fileName;
	temporary_files ~= path;
	return path;
}

private NativePath[] temporary_files;

static ~this()
{
	foreach (path; temporary_files)
	{
		auto spath = path.toNativeString();
		if (spath.exists)
			std.file.remove(spath);
	}
}
