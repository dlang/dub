module dub.packagesuppliers.filesystem;

public import dub.dependency : PackageName;
import dub.packagesuppliers.packagesupplier;

/**
	File system based package supplier.

	This package supplier searches a certain directory for files with names of
	the form "[package name]-[version].zip".
*/
class FileSystemPackageSupplier : PackageSupplier {
	import dub.internal.vibecompat.core.log;
	version (Have_vibe_core) import dub.internal.vibecompat.inet.path : toNativeString;
	import std.exception : enforce;
	private {
		NativePath m_path;
	}

	this(NativePath root) { m_path = root; }

	override @property string description() { return "file repository at "~m_path.toNativeString(); }

	Version[] getVersions(PackageName package_name)
	{
		import std.algorithm.sorting : sort;
		import std.file : dirEntries, DirEntry, SpanMode;
		import std.conv : to;
		Version[] ret;
		foreach (DirEntry d; dirEntries(m_path.toNativeString(), package_name~"*", SpanMode.shallow)) {
			NativePath p = NativePath(d.name);
			logDebug("Entry: %s", p);
			enforce(to!string(p.head)[$-4..$] == ".zip");
			auto vers = p.head.name[package_name.length+1..$-4];
			logDebug("Version: %s", vers);
			ret ~= Version(vers);
		}
		ret.sort();
		return ret;
	}

	void fetchPackage(NativePath path, PackageName package_name, Dependency dep, bool pre_release)
	{
		import dub.internal.vibecompat.core.file : copyFile, existsFile;
		enforce(path.absolute);
		logInfo("Storing package '"~package_name~"', version requirements: %s", dep);
		auto filename = bestPackageFile(package_name, dep, pre_release);
		enforce(existsFile(filename));
		copyFile(filename, path);
	}

	Json fetchPackageRecipe(PackageName package_name, Dependency dep, bool pre_release)
	{
		import std.array : split;
		import std.path : stripExtension;
		import dub.internal.utils : packageInfoFileFromZip;
		import dub.recipe.io : parsePackageRecipe;
		import dub.recipe.json : toJson;

		auto filePath = bestPackageFile(package_name, dep, pre_release);
		string packageFileName;
		string packageFileContent = packageInfoFileFromZip(filePath, packageFileName);
		auto recipe = parsePackageRecipe(packageFileContent, packageFileName);
		Json json = toJson(recipe);
		json["version"] = filePath.toNativeString().split("-")[$-1].stripExtension();
		return json;
	}

	SearchResult[] searchPackages(string query)
	{
		// TODO!
		return null;
	}

	private NativePath bestPackageFile(PackageName package_name, Dependency dep, bool pre_release)
	{
		import std.algorithm.iteration : filter;
		import std.array : array;
		import std.format : format;
		NativePath toPath(Version ver) {
			return m_path ~ (package_name ~ "-" ~ ver.toString() ~ ".zip");
		}
		auto versions = getVersions(package_name).filter!(v => dep.matches(v)).array;
		enforce(versions.length > 0, format("No package %s found matching %s", package_name, dep));
		foreach_reverse (ver; versions) {
			if (pre_release || !ver.isPreRelease)
				return toPath(ver);
		}
		return toPath(versions[$-1]);
	}
}
