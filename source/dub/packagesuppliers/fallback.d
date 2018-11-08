module dub.packagesuppliers.fallback;

import dub.packagesuppliers.packagesupplier;
import std.typecons : AutoImplement;

package abstract class AbstractFallbackPackageSupplier : PackageSupplier
{
	protected PackageSupplier[] m_suppliers;

	this(PackageSupplier[] suppliers)
	{
		assert(suppliers.length);
		m_suppliers = suppliers;
	}

	override @property string description()
	{
		import std.algorithm.iteration : map;
		import std.format : format;
		return format("%s (fallbacks %-(%s, %))", m_suppliers[0].description, m_suppliers[1 .. $].map!(x => x.description));
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
		import dub.internal.vibecompat.core.log : logDiagnostic;

		Exception firstEx;
		try
			return m_suppliers[0].%1$s(args);
		catch (Exception e)
		{
			logDiagnostic("Package supplier %%s failed with '%%s', trying fallbacks.",
				m_suppliers[0].description, e.msg);
			m_suppliers = m_suppliers[1 .. $];
			firstEx = e;
		}

		foreach (fallback; m_suppliers)
		{
			try
			{
				scope (success) logDiagnostic("Fallback %%s succeeded", fallback.description);
				return fallback.%1$s(args);
			}
			catch(Exception e)
			{
				logDiagnostic("Fallback package supplier %%s failed with '%%s'.",
					fallback.description, e.msg);
				m_suppliers = m_suppliers[1 .. $];
			}
		}
		throw firstEx;
	}.format(__traits(identifier, func));
}
