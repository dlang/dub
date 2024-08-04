module dub.packagesuppliers.filesystem;

import dub.internal.logging;
import dub.internal.vibecompat.inet.path;
import dub.packagesuppliers.packagesupplier;

import std.exception : enforce;

/**
	File system based package supplier.

	This package supplier searches a certain directory for files with names of
	the form "[package name]-[version].zip".
*/
class FileSystemPackageSupplier : PackageSupplier {
	private {
		NativePath m_path;
	}

	this(NativePath root) { m_path = root; }

	override @property string description() { return "file repository at "~m_path.toNativeString(); }

	Version[] getVersions(in PackageName name)
	{
		import std.algorithm.sorting : sort;
		import std.file : dirEntries, DirEntry, SpanMode;
		import std.conv : to;
		import dub.semver : isValidVersion;
		Version[] ret;
        const zipFileGlob = name.main.toString() ~ "*.zip";
		foreach (DirEntry d; dirEntries(m_path.toNativeString(), zipFileGlob, SpanMode.shallow)) {
			NativePath p = NativePath(d.name);
			auto vers = p.head.name[name.main.toString().length+1..$-4];
			if (!isValidVersion(vers)) {
				logDebug("Ignoring entry '%s' because it isn't a version of package '%s'", p, name.main);
				continue;
			}
			logDebug("Entry: %s", p);
			logDebug("Version: %s", vers);
			ret ~= Version(vers);
		}
		ret.sort();
		return ret;
	}

	override ubyte[] fetchPackage(in PackageName name,
		in VersionRange dep, bool pre_release)
	{
		import dub.internal.vibecompat.core.file : readFile, existsFile;
		logInfo("Storing package '%s', version requirements: %s", name.main, dep);
		auto filename = bestPackageFile(name, dep, pre_release);
		enforce(existsFile(filename));
		return readFile(filename);
	}

	override Json fetchPackageRecipe(in PackageName name, in VersionRange dep,
		bool pre_release)
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
		enforce(basename.startsWith(name.main.toString()),
			"Malformed package filename: " ~ filePath.toNativeString);
		json["version"] = basename[name.main.toString().length + 1 .. $-4];
		return json;
	}

	SearchResult[] searchPackages(string query)
	{
		// TODO!
		return null;
	}

	private NativePath bestPackageFile(in PackageName name, in VersionRange dep,
		bool pre_release)
	{
		import std.algorithm.iteration : filter;
		import std.array : array;
		import std.format : format;
		NativePath toPath(Version ver) {
			return m_path ~ "%s-%s.zip".format(name.main, ver);
		}
		auto versions = getVersions(name).filter!(v => dep.matches(v)).array;
		enforce(versions.length > 0, format("No package %s found matching %s", name.main, dep));
		foreach_reverse (ver; versions) {
			if (pre_release || !ver.isPreRelease)
				return toPath(ver);
		}
		return toPath(versions[$-1]);
	}
}
