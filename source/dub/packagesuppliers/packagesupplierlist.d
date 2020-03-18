module dub.packagesuppliers.packagesupplierlist;

import dub.internal.vibecompat.core.log;
import dub.packagesuppliers;

import std.format;
import std.encoding : sanitize;

/** Helper struct to wrap a list of PackageSupplier instances and run actions
	on multiple package suppliers safely.

	Provides utility iterator to wrap common try-catch loops with providers.

	Contains common patterns used with multiple package suppliers.
*/
struct PackageSupplierList {
	private {
		PackageSupplier[] m_suppliers;
	}

	this(PackageSupplier[] suppliers)
	{
		m_suppliers = suppliers;
	}

	inout(PackageSupplier[]) all() inout @property
	{
		return m_suppliers;
	}

	/** Returns an iterator to perform a foreach action on all suppliers,
		wrapping them inside a try-catch block, automatically logging failure
		messages using logWarn and the specified "doingWhat" parameter and also
		logging full error information using logDebug for development.

		The "what" part is being logged in the logWarn message as
		$(D "Error {what} using {supplier.description}: {error.msg}")

		Params:
			args = format arguments
	*/
	auto tryAllOrWarn(string formatDoingWhat, Args...)(Args args)
	{
		return tryAllOrWarn(format!formatDoingWhat(args));
	}

	/// ditto
	auto tryAllOrWarn(lazy string doingWhat)
	{
		return tryAllOrCall(delegate(ref ps, e) {
			logWarn("Error %s using %s: %s", doingWhat, ps.description, e.msg);
			logDebug("Full error: %s", e.toString().sanitize);
		});
	}

	/// Same as $(LREF tryAllOrWarn) but the what part is formatted using
	/// $(D "{what} using {supplier.description}: {error.msg}")
	auto tryAllOrWarnRaw(string formatDoingWhat, Args...)(Args args)
	{
		return tryAllOrWarnRaw(format!formatDoingWhat(args));
	}

	/// ditto
	auto tryAllOrWarnRaw(lazy string doingWhat)
	{
		return tryAllOrCall(delegate(ref ps, e) {
			logWarn("%s using %s: %s", doingWhat, ps.description, e.msg);
			logDebug("Full error: %s", e.toString().sanitize);
		});
	}

	/// Same as $(LREF tryAllOrWarn) but calls an error action instead of logging.
	auto tryAllOrCall(void delegate(ref PackageSupplier, Exception) errorCallback)
	{
		static struct TryForeach
		{
			PackageSupplier[] supp;
			void delegate(ref PackageSupplier, Exception) errorCallback;

			int opApply(int delegate(ref PackageSupplier) dg)
			{
				int result;
				foreach (ps; supp) {
					try {
						result = dg(ps);
					} catch (Exception e) {
						errorCallback(ps, e);
					}

					if (result) {
						break;
					}
				}
				return result;
			}
		}

		return TryForeach(m_suppliers, errorCallback);
	}

	/** Fetches a package recipe using the given arguments on the first
		package supplier that returns a non-null recipe.

		Calls $(REF fetchPackageRecipe, dub,packagesuppliers,packagesupplier,PackageSupplier) on all suppliers.

		Params:
			package_id = Name of the package of which to retrieve the recipe.
			dep = Version constraint to match against.
			pre_release = If true, matches the latest pre-release version.
				Otherwise prefers stable versions.
			supplier = the PackageSupplier which returned the package recipe.
	*/
	Json getFirstPackageRecipe(string package_id, Dependency dep, bool pre_release, out PackageSupplier supplier)
	{
		foreach (ps; m_suppliers) {
			try {
				auto pinfo = ps.fetchPackageRecipe(package_id, dep, pre_release);
				if (pinfo.type == Json.Type.null_)
					continue;
				supplier = ps;
				return pinfo;
			} catch(Exception e) {
				logWarn("Package metadata for %s %s could not be downloaded from %s: %s", package_id, dep, ps.description, e.msg);
				logDebug("Full error: %s", e.toString().sanitize());
			}
		}
		return Json.init;
	}

	alias all this;
}
