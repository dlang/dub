module dub.packagesuppliers.filesystem;

import dub.packagesuppliers.packagesupplier;

/**
	File system based package supplier.

	This package supplier searches a certain directory for files with names of
	the form "[package name]-[version].zip".
*/
class FileSystemPackageSupplier : PackageSupplier {
	import dub.internal.logging;

	version (Have_vibe_core) import dub.internal.vibecompat.inet.path : toNativeString;
	import std.exception : enforce;
	private {
		NativePath m_path;
	}

	this(NativePath root) { m_path = root; }

	override @property string description() { return "file repository at "~m_path.toNativeString(); }

	Version[] getVersions(PackageName name)
	{
		import std.algorithm.sorting : sort;
		import std.file : dirEntries, DirEntry, SpanMode;
		import std.conv : to;
		Version[] ret;
		foreach (DirEntry d; dirEntries(m_path.toNativeString(), name[]~"*", SpanMode.shallow)) {
			NativePath p = NativePath(d.name);
			logDebug("Entry: %s", p);
			enforce(to!string(p.head)[$-4..$] == ".zip");
			auto vers = p.head.name[name.length+1..$-4];
			logDebug("Version: %s", vers);
			ret ~= Version(vers);
		}
		ret.sort();
		return ret;
	}

	void fetchPackage(NativePath path, PackageName name, Dependency dep, bool pre_release)
	{
		import dub.internal.vibecompat.core.file : copyFile, existsFile;
		enforce(path.absolute);
		logInfo("Storing package '%s', version requirements: %s", name, dep);
		auto filename = bestPackageFile(name, dep, pre_release);
		enforce(existsFile(filename));
		copyFile(filename, path);
	}

	Json fetchPackageRecipe(PackageName name, Dependency dep, bool pre_release)
	{
		import std.array : split;
		import std.path : stripExtension;
		import std.algorithm : startsWith, endsWith;
		import dub.internal.utils : packageInfoFileFromZip;
		import dub.recipe.io : parsePackageRecipe;
		import dub.recipe.json : toJson;

		auto filePath = bestPackageFile(name, dep, pre_release);
		string packageFileName;
		string packageFileContent = packageInfoFileFromZip(filePath, packageFileName);
		auto recipe = parsePackageRecipe(packageFileContent, packageFileName);
		Json json = toJson(recipe);
		auto basename = filePath.head.name;
		enforce(basename.endsWith(".zip"), "Malformed package filename: " ~ filePath.toNativeString);
		enforce(basename.startsWith(name[]), "Malformed package filename: " ~ filePath.toNativeString);
		json["version"] = basename[name.length + 1 .. $-4];
		return json;
	}

	SearchResult[] searchPackages(string query)
	{
		// TODO!
		return null;
	}

	private NativePath bestPackageFile(PackageName name, Dependency dep, bool pre_release)
	{
		import std.algorithm.iteration : filter;
		import std.array : array;
		import std.format : format;
		NativePath toPath(Version ver) {
			return m_path ~ (name[] ~ "-" ~ ver.toString() ~ ".zip");
		}
		auto versions = getVersions(name).filter!(v => dep.matches(v)).array;
		enforce(versions.length > 0, format("No package %s found matching %s", name, dep));
		foreach_reverse (ver; versions) {
			if (pre_release || !ver.isPreRelease)
				return toPath(ver);
		}
		return toPath(versions[$-1]);
	}
}
