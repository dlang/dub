module dub.packagesuppliers.fallback;

import dub.packagesuppliers.packagesupplier;
import std.typecons : AutoImplement;

package abstract class AbstractFallbackPackageSupplier : PackageSupplier
{
	protected PackageSupplier m_default;
	protected PackageSupplier[] m_fallbacks;

	this(PackageSupplier default_, PackageSupplier[] fallbacks)
	{
		m_default = default_;
		m_fallbacks = fallbacks;
	}

	override @property string description()
	{
		import std.algorithm.iteration : map;
		import std.format : format;
		return format("%s (fallback %s)", m_default.description, m_fallbacks.map!(x => x.description));
	}

	// Workaround https://issues.dlang.org/show_bug.cgi?id=2525
	abstract override Version[] getVersions(string package_id);
	abstract override void fetchPackage(NativePath path, string package_id, Dependency dep, bool pre_release);
	abstract override Json fetchPackageRecipe(string package_id, Dependency dep, bool pre_release);
	abstract override SearchResult[] searchPackages(string query);
}


/**
	Combines two package suppliers and uses the second as fallback to handle failures.

	Assumes that both registries serve the same packages (--mirror).
*/
package(dub) alias FallbackPackageSupplier = AutoImplement!(AbstractFallbackPackageSupplier, fallback);

private template fallback(T, alias func)
{
	import std.format : format;
	enum fallback = q{
		import std.range : back, dropBackOne;
		import dub.logging : logDebug;
		scope (failure)
		{
			foreach (m_fallback; m_fallbacks.dropBackOne)
			{
				try
					return m_fallback.%1$s(args);
				catch(Exception)
					logDebug("Package supplier %s failed. Trying next fallback.", m_fallback);
			}
			return m_fallbacks.back.%1$s(args);
		}
		return m_default.%1$s(args);
	}.format(__traits(identifier, func));
}
