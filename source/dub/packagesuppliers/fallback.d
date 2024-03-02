module dub.packagesuppliers.fallback;

import dub.packagesuppliers.packagesupplier;
import std.typecons : AutoImplement;

package abstract class AbstractFallbackPackageSupplier : PackageSupplier
{
	protected import core.time : minutes;
	protected import std.datetime : Clock, SysTime;

	static struct Pair { PackageSupplier ps; SysTime failTime; }
	protected Pair[] m_suppliers;

	this(PackageSupplier[] suppliers)
	{
		assert(suppliers.length);
		m_suppliers.length = suppliers.length;
		foreach (i, ps; suppliers)
			m_suppliers[i].ps = ps;
	}

	override @property string description()
	{
		import std.algorithm.iteration : map;
		import std.format : format;
		return format("%s (fallbacks %-(%s, %))", m_suppliers[0].ps.description,
			m_suppliers[1 .. $].map!(pair => pair.ps.description));
	}

	// Workaround https://issues.dlang.org/show_bug.cgi?id=2525
	abstract override Version[] getVersions(in PackageName name);
	abstract override ubyte[] fetchPackage(in PackageName name, in VersionRange dep, bool pre_release);
	abstract override Json fetchPackageRecipe(in PackageName name, in VersionRange dep, bool pre_release);
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
		import dub.internal.logging : logDebug;

		Exception firstEx;
		try
			return m_suppliers[0].ps.%1$s(args);
		catch (Exception e)
		{
			logDebug("Package supplier %%s failed with '%%s', trying fallbacks.",
				m_suppliers[0].ps.description, e.msg);
			firstEx = e;
		}

		immutable now = Clock.currTime;
		foreach (ref pair; m_suppliers[1 .. $])
		{
			if (pair.failTime > now - 10.minutes)
				continue;
			try
			{
				scope (success) logDebug("Fallback %%s succeeded", pair.ps.description);
				return pair.ps.%1$s(args);
			}
			catch (Exception e)
			{
				pair.failTime = now;
				logDebug("Fallback package supplier %%s failed with '%%s'.",
					pair.ps.description, e.msg);
			}
		}
		throw firstEx;
	}.format(__traits(identifier, func));
}
