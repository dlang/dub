/**
	A package manager.

	Copyright: © 2012-2013 Matthias Dondorff, 2012-2016 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff, Sönke Ludwig
*/
module dub.dub;

import dub.compilers.compiler;
import dub.data.settings : SPS = SkipPackageSuppliers, Settings;
import dub.dependency;
import dub.dependencyresolver;
import dub.internal.utils;
import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.data.json;
import dub.internal.vibecompat.inet.url;
import dub.internal.logging;
import dub.package_;
import dub.packagemanager;
import dub.packagesuppliers;
import dub.project;
import dub.generators.generator;
import dub.init;

import std.algorithm;
import std.array : array, replace;
import std.conv : text, to;
import std.encoding : sanitize;
import std.exception : enforce;
import std.file;
import std.process : environment;
import std.range : assumeSorted, empty;
import std.string;

// Set output path and options for coverage reports
version (DigitalMars) version (D_Coverage)
{
	shared static this()
	{
		import core.runtime, std.file, std.path, std.stdio;
		dmd_coverSetMerge(true);
		auto path = buildPath(dirName(thisExePath()), "../cov");
		if (!path.exists)
			mkdir(path);
		dmd_coverDestPath(path);
	}
}

static this()
{
	import dub.compilers.dmd : DMDCompiler;
	import dub.compilers.gdc : GDCCompiler;
	import dub.compilers.ldc : LDCCompiler;
	registerCompiler(new DMDCompiler);
	registerCompiler(new GDCCompiler);
	registerCompiler(new LDCCompiler);
}

deprecated("use defaultRegistryURLs") enum defaultRegistryURL = defaultRegistryURLs[0];

/// The URL to the official package registry and it's default fallback registries.
static immutable string[] defaultRegistryURLs = [
	"https://code.dlang.org/",
	"https://codemirror.dlang.org/",
	"https://dub.bytecraft.nl/",
	"https://code-mirror.dlang.io/",
];

/** Returns a default list of package suppliers.

	This will contain a single package supplier that points to the official
	package registry.

	See_Also: `defaultRegistryURLs`
*/
PackageSupplier[] defaultPackageSuppliers()
{
	logDiagnostic("Using dub registry url '%s'", defaultRegistryURLs[0]);
	return [new FallbackPackageSupplier(defaultRegistryURLs.map!getRegistryPackageSupplier.array)];
}

/** Returns a registry package supplier according to protocol.

	Allowed protocols are dub+http(s):// and maven+http(s)://.
*/
PackageSupplier getRegistryPackageSupplier(string url)
{
	switch (url.startsWith("dub+", "mvn+", "file://"))
	{
		case 1:
			return new RegistryPackageSupplier(URL(url[4..$]));
		case 2:
			return new MavenRegistryPackageSupplier(URL(url[4..$]));
		case 3:
			return new FileSystemPackageSupplier(NativePath(url[7..$]));
		default:
			return new RegistryPackageSupplier(URL(url));
	}
}

unittest
{
	auto dubRegistryPackageSupplier = getRegistryPackageSupplier("dub+https://code.dlang.org");
	assert(dubRegistryPackageSupplier.description.canFind(" https://code.dlang.org"));

	dubRegistryPackageSupplier = getRegistryPackageSupplier("https://code.dlang.org");
	assert(dubRegistryPackageSupplier.description.canFind(" https://code.dlang.org"));

	auto mavenRegistryPackageSupplier = getRegistryPackageSupplier("mvn+http://localhost:8040/maven/libs-release/dubpackages");
	assert(mavenRegistryPackageSupplier.description.canFind(" http://localhost:8040/maven/libs-release/dubpackages"));

	auto fileSystemPackageSupplier = getRegistryPackageSupplier("file:///etc/dubpackages");
	assert(fileSystemPackageSupplier.description.canFind(" " ~ NativePath("/etc/dubpackages").toNativeString));
}

/** Provides a high-level entry point for DUB's functionality.

	This class provides means to load a certain project (a root package with
	all of its dependencies) and to perform high-level operations as found in
	the command line interface.
*/
class Dub {
	private {
		bool m_dryRun = false;
		PackageManager m_packageManager;
		PackageSupplier[] m_packageSuppliers;
		NativePath m_rootPath;
		SpecialDirs m_dirs;
		Settings m_config;
		Project m_project;
		string m_defaultCompiler;
	}

	/** The default placement location of fetched packages.

		This property can be altered, so that packages which are downloaded as part
		of the normal upgrade process are stored in a certain location. This is
		how the "--local" and "--system" command line switches operate.
	*/
	PlacementLocation defaultPlacementLocation = PlacementLocation.user;


	/** Initializes the instance for use with a specific root package.

		Note that a package still has to be loaded using one of the
		`loadPackage` overloads.

		Params:
			root_path = Path to the root package
			additional_package_suppliers = A list of package suppliers to try
				before the suppliers found in the configurations files and the
				`defaultPackageSuppliers`.
			skip_registry = Can be used to skip using the configured package
				suppliers, as well as the default suppliers.
	*/
	this(string root_path = ".", PackageSupplier[] additional_package_suppliers = null,
			SkipPackageSuppliers skip_registry = SkipPackageSuppliers.none)
	{
		m_rootPath = NativePath(root_path);
		if (!m_rootPath.absolute) m_rootPath = getWorkingDirectory() ~ m_rootPath;

		init();

		m_packageSuppliers = this.computePkgSuppliers(additional_package_suppliers,
			skip_registry, environment.get("DUB_REGISTRY", null));
		m_packageManager = new PackageManager(m_rootPath, m_dirs.userPackages, m_dirs.systemSettings, false);

		auto ccps = m_config.customCachePaths;
		if (ccps.length)
			m_packageManager.customCachePaths = ccps;

		// TODO: Move this environment read out of the ctor
		if (auto p = environment.get("DUBPATH")) {
			version(Windows) enum pathsep = ";";
			else enum pathsep = ":";
			NativePath[] paths = p.split(pathsep)
				.map!(p => NativePath(p))().array();
			m_packageManager.searchPath = paths;
		}
	}

	/** Initializes the instance with a single package search path, without
		loading a package.

		This constructor corresponds to the "--bare" option of the command line
		interface.

		Params:
		  root = The root path of the Dub instance itself.
		  pkg_root = The root of the location where packages are located
					 Only packages under this location will be accessible.
					 Note that packages at the top levels will be ignored.
	*/
	this(NativePath root, NativePath pkg_root)
	{
		// Note: We're doing `init()` before setting the `rootPath`,
		// to prevent `init` from reading the project's settings.
		init();
		this.m_rootPath = root;
		m_packageManager = new PackageManager(pkg_root);
	}

	deprecated("Use the overload that takes `(NativePath pkg_root, NativePath root)`")
	this(NativePath pkg_root)
	{
		this(pkg_root, pkg_root);
	}

	private void init()
	{
		this.m_dirs = SpecialDirs.make();
		this.loadConfig();
		this.determineDefaultCompiler();
	}

	/**
	 * Load user configuration for this instance
	 *
	 * This can be overloaded in child classes to prevent library / unittest
	 * dub from doing any kind of file IO.
	 */
	protected void loadConfig()
	{
		import dub.internal.configy.Read;

		void readSettingsFile (NativePath path_)
		{
			// TODO: Remove `StrictMode.Warn` after v1.40 release
			// The default is to error, but as the previous parser wasn't
			// complaining, we should first warn the user.
			const path = path_.toNativeString();
			if (path.exists) {
				auto newConf = parseConfigFileSimple!Settings(path, StrictMode.Warn);
				if (!newConf.isNull())
					this.m_config = this.m_config.merge(newConf.get());
			}
		}

		const dubFolderPath = NativePath(thisExePath).parentPath;

		// override default userSettings + userPackages if a $DPATH or
		// $DUB_HOME environment variable is set.
		bool overrideDubHomeFromEnv;
		{
			string dubHome = environment.get("DUB_HOME");
			if (!dubHome.length) {
				auto dpath = environment.get("DPATH");
				if (dpath.length)
					dubHome = (NativePath(dpath) ~ "dub/").toNativeString();

			}
			if (dubHome.length) {
				overrideDubHomeFromEnv = true;

				m_dirs.userSettings = NativePath(dubHome);
				m_dirs.userPackages = m_dirs.userSettings;
				m_dirs.cache = m_dirs.userPackages ~ "cache";
			}
		}

		readSettingsFile(m_dirs.systemSettings ~ "settings.json");
		readSettingsFile(dubFolderPath ~ "../etc/dub/settings.json");
		version (Posix) {
			if (dubFolderPath.absolute && dubFolderPath.startsWith(NativePath("usr")))
				readSettingsFile(NativePath("/etc/dub/settings.json"));
		}

		// Override user + local package path from system / binary settings
		// Then continues loading local settings from these folders. (keeping
		// global /etc/dub/settings.json settings intact)
		//
		// Don't use it if either $DPATH or $DUB_HOME are set, as environment
		// variables usually take precedence over configuration.
		if (!overrideDubHomeFromEnv && this.m_config.dubHome.set) {
			m_dirs.userSettings = NativePath(this.m_config.dubHome.expandEnvironmentVariables);
		}

		// load user config:
		readSettingsFile(m_dirs.userSettings ~ "settings.json");

		// load per-package config:
		if (!this.m_rootPath.empty)
			readSettingsFile(this.m_rootPath ~ "dub.settings.json");

		// same as userSettings above, but taking into account the
		// config loaded from user settings and per-package config as well.
		if (!overrideDubHomeFromEnv && this.m_config.dubHome.set) {
			m_dirs.userPackages = NativePath(this.m_config.dubHome.expandEnvironmentVariables);
			m_dirs.cache = m_dirs.userPackages ~ "cache";
		}
	}

	unittest
	{
		scope (exit) environment.remove("DUB_REGISTRY");
		auto dub = new TestDub(".", null, SkipPackageSuppliers.configured);
		assert(dub.m_packageSuppliers.length == 0);
		environment["DUB_REGISTRY"] = "http://example.com/";
		dub = new TestDub(".", null, SkipPackageSuppliers.configured);
		assert(dub.m_packageSuppliers.length == 1);
		environment["DUB_REGISTRY"] = "http://example.com/;http://foo.com/";
		dub = new TestDub(".", null, SkipPackageSuppliers.configured);
		assert(dub.m_packageSuppliers.length == 2);
		dub = new TestDub(".", [new RegistryPackageSupplier(URL("http://bar.com/"))], SkipPackageSuppliers.configured);
		assert(dub.m_packageSuppliers.length == 3);
	}

	/** Get the list of package suppliers.

		Params:
			additional_package_suppliers = A list of package suppliers to try
				before the suppliers found in the configurations files and the
				`defaultPackageSuppliers`.
			skip_registry = Can be used to skip using the configured package
				suppliers, as well as the default suppliers.
	*/
	deprecated("This is an implementation detail. " ~
		"Use `packageSuppliers` to get the computed list of package " ~
		"suppliers once a `Dub` instance has been constructed.")
	public PackageSupplier[] getPackageSuppliers(PackageSupplier[] additional_package_suppliers, SkipPackageSuppliers skip_registry)
	{
		return this.computePkgSuppliers(additional_package_suppliers, skip_registry, environment.get("DUB_REGISTRY", null));
	}

	/// Ditto
	private PackageSupplier[] computePkgSuppliers(
		PackageSupplier[] additional_package_suppliers, SkipPackageSuppliers skip_registry,
		string dub_registry_var)
	{
		PackageSupplier[] ps = additional_package_suppliers;

		if (skip_registry < SkipPackageSuppliers.all)
		{
			ps ~= dub_registry_var
				.splitter(";")
				.map!(url => getRegistryPackageSupplier(url))
				.array;
		}

		if (skip_registry < SkipPackageSuppliers.configured)
		{
			ps ~= m_config.registryUrls
				.map!(url => getRegistryPackageSupplier(url))
				.array;
		}

		if (skip_registry < SkipPackageSuppliers.standard)
			ps ~= defaultPackageSuppliers();

		return ps;
	}

	/// ditto
	deprecated("This is an implementation detail. " ~
		"Use `packageSuppliers` to get the computed list of package " ~
		"suppliers once a `Dub` instance has been constructed.")
	public PackageSupplier[] getPackageSuppliers(PackageSupplier[] additional_package_suppliers)
	{
		return getPackageSuppliers(additional_package_suppliers, m_config.skipRegistry);
	}

	unittest
	{
		auto dub = new TestDub();

		assert(dub.computePkgSuppliers(null, SkipPackageSuppliers.none, null).length == 1);
		assert(dub.computePkgSuppliers(null, SkipPackageSuppliers.configured, null).length == 0);
		assert(dub.computePkgSuppliers(null, SkipPackageSuppliers.standard, null).length == 0);

		assert(dub.computePkgSuppliers(null, SkipPackageSuppliers.standard, "http://example.com/")
			.length == 1);
	}

	@property bool dryRun() const { return m_dryRun; }
	@property void dryRun(bool v) { m_dryRun = v; }

	/** Returns the root path (usually the current working directory).
	*/
	@property NativePath rootPath() const { return m_rootPath; }
	/// ditto
	deprecated("Changing the root path is deprecated as it has non-obvious pitfalls " ~
			   "(e.g. settings aren't reloaded). Instantiate a new `Dub` instead")
	@property void rootPath(NativePath root_path)
	{
		m_rootPath = root_path;
		if (!m_rootPath.absolute) m_rootPath = getWorkingDirectory() ~ m_rootPath;
	}

	/// Returns the name listed in the dub.json of the current
	/// application.
	@property string projectName() const { return m_project.name; }

	@property NativePath projectPath() const { return this.m_project.rootPackage.path; }

	@property string[] configurations() const { return m_project.configurations; }

	@property inout(PackageManager) packageManager() inout { return m_packageManager; }

	@property inout(Project) project() inout { return m_project; }

	@property inout(PackageSupplier)[] packageSuppliers() inout { return m_packageSuppliers; }

	/** Returns the default compiler binary to use for building D code.

		If set, the "defaultCompiler" field of the DUB user or system
		configuration file will be used. Otherwise the PATH environment variable
		will be searched for files named "dmd", "gdc", "gdmd", "ldc2", "ldmd2"
		(in that order, taking into account operating system specific file
		extensions) and the first match is returned. If no match is found, "dmd"
		will be used.
	*/
	@property string defaultCompiler() const { return m_defaultCompiler; }

	/** Returns the default architecture to use for building D code.

		If set, the "defaultArchitecture" field of the DUB user or system
		configuration file will be used. Otherwise null will be returned.
	*/
	@property string defaultArchitecture() const { return this.m_config.defaultArchitecture; }

	/** Returns the default low memory option to use for building D code.

		If set, the "defaultLowMemory" field of the DUB user or system
		configuration file will be used. Otherwise false will be returned.
	*/
	@property bool defaultLowMemory() const { return this.m_config.defaultLowMemory; }

	@property const(string[string]) defaultEnvironments() const { return this.m_config.defaultEnvironments; }
	@property const(string[string]) defaultBuildEnvironments() const { return this.m_config.defaultBuildEnvironments; }
	@property const(string[string]) defaultRunEnvironments() const { return this.m_config.defaultRunEnvironments; }
	@property const(string[string]) defaultPreGenerateEnvironments() const { return this.m_config.defaultPreGenerateEnvironments; }
	@property const(string[string]) defaultPostGenerateEnvironments() const { return this.m_config.defaultPostGenerateEnvironments; }
	@property const(string[string]) defaultPreBuildEnvironments() const { return this.m_config.defaultPreBuildEnvironments; }
	@property const(string[string]) defaultPostBuildEnvironments() const { return this.m_config.defaultPostBuildEnvironments; }
	@property const(string[string]) defaultPreRunEnvironments() const { return this.m_config.defaultPreRunEnvironments; }
	@property const(string[string]) defaultPostRunEnvironments() const { return this.m_config.defaultPostRunEnvironments; }

	/** Loads the package that resides within the configured `rootPath`.
	*/
	void loadPackage()
	{
		loadPackage(m_rootPath);
	}

	/// Loads the package from the specified path as the main project package.
	void loadPackage(NativePath path)
	{
		m_project = new Project(m_packageManager, path);
	}

	/// Loads a specific package as the main project package (can be a sub package)
	void loadPackage(Package pack)
	{
		m_project = new Project(m_packageManager, pack);
	}

	/** Loads a single file package.

		Single-file packages are D files that contain a package receipe comment
		at their top. A recipe comment must be a nested `/+ ... +/` style
		comment, containing the virtual recipe file name and a colon, followed by the
		recipe contents (what would normally be in dub.sdl/dub.json).

		Example:
		---
		/+ dub.sdl:
		   name "test"
		   dependency "vibe-d" version="~>0.7.29"
		+/
		import vibe.http.server;

		void main()
		{
			auto settings = new HTTPServerSettings;
			settings.port = 8080;
			listenHTTP(settings, &hello);
		}

		void hello(HTTPServerRequest req, HTTPServerResponse res)
		{
			res.writeBody("Hello, World!");
		}
		---

		The script above can be invoked with "dub --single test.d".
	*/
	void loadSingleFilePackage(NativePath path)
	{
		import dub.recipe.io : parsePackageRecipe;
		import std.file : readText;
		import std.path : baseName, stripExtension;

		path = makeAbsolute(path);

		string file_content = readText(path.toNativeString());

		if (file_content.startsWith("#!")) {
			auto idx = file_content.indexOf('\n');
			enforce(idx > 0, "The source fine doesn't contain anything but a shebang line.");
			file_content = file_content[idx+1 .. $];
		}

		file_content = file_content.strip();

		string recipe_content;

		if (file_content.startsWith("/+")) {
			file_content = file_content[2 .. $];
			auto idx = file_content.indexOf("+/");
			enforce(idx >= 0, "Missing \"+/\" to close comment.");
			recipe_content = file_content[0 .. idx].strip();
		} else throw new Exception("The source file must start with a recipe comment.");

		auto nidx = recipe_content.indexOf('\n');

		auto idx = recipe_content.indexOf(':');
		enforce(idx > 0 && (nidx < 0 || nidx > idx),
			"The first line of the recipe comment must list the recipe file name followed by a colon (e.g. \"/+ dub.sdl:\").");
		auto recipe_filename = recipe_content[0 .. idx];
		recipe_content = recipe_content[idx+1 .. $];
		auto recipe_default_package_name = path.toString.baseName.stripExtension.strip;

		auto recipe = parsePackageRecipe(recipe_content, recipe_filename, null, recipe_default_package_name);
		enforce(recipe.buildSettings.sourceFiles.length == 0, "Single-file packages are not allowed to specify source files.");
		enforce(recipe.buildSettings.sourcePaths.length == 0, "Single-file packages are not allowed to specify source paths.");
		enforce(recipe.buildSettings.importPaths.length == 0, "Single-file packages are not allowed to specify import paths.");
		recipe.buildSettings.sourceFiles[""] = [path.toNativeString()];
		recipe.buildSettings.sourcePaths[""] = [];
		recipe.buildSettings.importPaths[""] = [];
		recipe.buildSettings.mainSourceFile = path.toNativeString();
		if (recipe.buildSettings.targetType == TargetType.autodetect)
			recipe.buildSettings.targetType = TargetType.executable;

		auto pack = new Package(recipe, path.parentPath, null, "~master");
		loadPackage(pack);
	}
	/// ditto
	void loadSingleFilePackage(string path)
	{
		loadSingleFilePackage(NativePath(path));
	}

	/** Gets the default configuration for a particular build platform.

		This forwards to `Project.getDefaultConfiguration` and requires a
		project to be loaded.
	*/
	string getDefaultConfiguration(in BuildPlatform platform, bool allow_non_library_configs = true) const { return m_project.getDefaultConfiguration(platform, allow_non_library_configs); }

	/** Attempts to upgrade the dependency selection of the loaded project.

		Params:
			options = Flags that control how the upgrade is carried out
			packages_to_upgrade = Optional list of packages. If this list
				contains one or more packages, only those packages will
				be upgraded. Otherwise, all packages will be upgraded at
				once.
	*/
	void upgrade(UpgradeOptions options, string[] packages_to_upgrade = null)
	{
		// clear non-existent version selections
		if (!(options & UpgradeOptions.upgrade)) {
			next_pack:
			foreach (p; m_project.selections.selectedPackages) {
				auto dep = m_project.selections.getSelectedVersion(p);
				if (!dep.path.empty) {
					auto path = dep.path;
					if (!path.absolute) path = this.rootPath ~ path;
					try if (m_packageManager.getOrLoadPackage(path)) continue;
					catch (Exception e) { logDebug("Failed to load path based selection: %s", e.toString().sanitize); }
				} else if (!dep.repository.empty) {
					if (m_packageManager.loadSCMPackage(getBasePackageName(p), dep.repository))
						continue;
				} else {
					if (m_packageManager.getPackage(p, dep.version_)) continue;
					foreach (ps; m_packageSuppliers) {
						try {
							auto versions = ps.getVersions(p);
							if (versions.canFind!(v => dep.matches(v, VersionMatchMode.strict)))
								continue next_pack;
						} catch (Exception e) {
							logWarn("Error querying versions for %s, %s: %s", p, ps.description, e.msg);
							logDebug("Full error: %s", e.toString().sanitize());
						}
					}
				}

				logWarn("Selected package %s %s doesn't exist. Using latest matching version instead.", p, dep);
				m_project.selections.deselectVersion(p);
			}
		}

		auto resolver = new DependencyVersionResolver(
			this, options, m_project.rootPackage, m_project.selections);
		Dependency[string] versions = resolver.resolve(packages_to_upgrade);

		if (options & UpgradeOptions.dryRun) {
			bool any = false;
			string rootbasename = getBasePackageName(m_project.rootPackage.name);

			foreach (p, ver; versions) {
				if (!ver.path.empty || !ver.repository.empty) continue;

				auto basename = getBasePackageName(p);
				if (basename == rootbasename) continue;

				if (!m_project.selections.hasSelectedVersion(basename)) {
					logInfo("Upgrade", Color.cyan,
						"Package %s would be selected with version %s", basename, ver);
					any = true;
					continue;
				}
				auto sver = m_project.selections.getSelectedVersion(basename);
				if (!sver.path.empty || !sver.repository.empty) continue;
				if (ver.version_ <= sver.version_) continue;
				logInfo("Upgrade", Color.cyan,
					"%s would be upgraded from %s to %s.",
					basename.color(Mode.bold), sver, ver);
				any = true;
			}
			if (any) logInfo("Use \"%s\" to perform those changes", "dub upgrade".color(Mode.bold));
			return;
		}

		foreach (p, ver; versions) {
			assert(!p.canFind(":"), "Resolved packages contain a sub package!?: "~p);
			Package pack;
			if (!ver.path.empty) {
				try pack = m_packageManager.getOrLoadPackage(ver.path);
				catch (Exception e) {
					logDebug("Failed to load path based selection: %s", e.toString().sanitize);
					continue;
				}
			} else if (!ver.repository.empty) {
				pack = m_packageManager.loadSCMPackage(p, ver.repository);
			} else {
				assert(ver.isExactVersion, "Resolved dependency is neither path, nor repository, nor exact version based!?");
				pack = m_packageManager.getPackage(p, ver.version_);
				if (pack && m_packageManager.isManagedPackage(pack)
					&& ver.version_.isBranch && (options & UpgradeOptions.upgrade) != 0)
				{
					// TODO: only re-install if there is actually a new commit available
					logInfo("Re-installing branch based dependency %s %s", p, ver.toString());
					m_packageManager.remove(pack);
					pack = null;
				}
			}

			FetchOptions fetchOpts;
			fetchOpts |= (options & UpgradeOptions.preRelease) != 0 ? FetchOptions.usePrerelease : FetchOptions.none;
			if (!pack) fetch(p, ver.version_, defaultPlacementLocation, fetchOpts, "getting selected version");
			if ((options & UpgradeOptions.select) && p != m_project.rootPackage.name) {
				if (!ver.repository.empty) {
					m_project.selections.selectVersion(p, ver.repository);
				} else if (ver.path.empty) {
					m_project.selections.selectVersion(p, ver.version_);
				} else {
					NativePath relpath = ver.path;
					if (relpath.absolute) relpath = relpath.relativeTo(m_project.rootPackage.path);
					m_project.selections.selectVersion(p, relpath);
				}
			}
		}

		string[] missingDependenciesBeforeReinit = m_project.missingDependencies;
		m_project.reinit();

		if (!m_project.hasAllDependencies) {
			auto resolvedDependencies = setDifference(
					assumeSorted(missingDependenciesBeforeReinit),
					assumeSorted(m_project.missingDependencies)
				);
			if (!resolvedDependencies.empty)
				upgrade(options, m_project.missingDependencies);
		}

		if ((options & UpgradeOptions.select) && !(options & (UpgradeOptions.noSaveSelections | UpgradeOptions.dryRun)))
			m_project.saveSelections();
	}

	/** Generate project files for a specified generator.

		Any existing project files will be overridden.
	*/
	void generateProject(string ide, GeneratorSettings settings)
	{
		settings.cache = this.m_dirs.cache;
		if (settings.overrideToolWorkingDirectory is NativePath.init)
			settings.overrideToolWorkingDirectory = m_rootPath;
		// With a requested `unittest` config, switch to the special test runner
		// config (which doesn't require an existing `unittest` configuration).
		if (settings.config == "unittest") {
			const test_config = m_project.addTestRunnerConfiguration(settings, !m_dryRun);
			if (test_config) settings.config = test_config;
		}

		auto generator = createProjectGenerator(ide, m_project);
		if (m_dryRun) return; // TODO: pass m_dryRun to the generator
		generator.generate(settings);
	}

	/** Generate project files using the special test runner (`dub test`) configuration.

		Any existing project files will be overridden.
	*/
	void testProject(GeneratorSettings settings, string config, NativePath custom_main_file)
	{
		settings.cache = this.m_dirs.cache;
		if (settings.overrideToolWorkingDirectory is NativePath.init)
			settings.overrideToolWorkingDirectory = m_rootPath;
		if (!custom_main_file.empty && !custom_main_file.absolute) custom_main_file = m_rootPath ~ custom_main_file;

		const test_config = m_project.addTestRunnerConfiguration(settings, !m_dryRun, config, custom_main_file);
		if (!test_config) return; // target type "none"

		settings.config = test_config;

		auto generator = createProjectGenerator("build", m_project);
		generator.generate(settings);
	}

	/** Executes D-Scanner tests on the current project. **/
	void lintProject(string[] args)
	{
		import std.path : buildPath, buildNormalizedPath;

		if (m_dryRun) return;

		auto tool = "dscanner";

		auto tool_pack = m_packageManager.getBestPackage(tool);
		if (!tool_pack) {
			logInfo("Hint", Color.light_blue, "%s is not present, getting and storing it user wide", tool);
			tool_pack = fetch(tool, VersionRange.Any, defaultPlacementLocation, FetchOptions.none);
		}

		auto dscanner_dub = new Dub(null, m_packageSuppliers);
		dscanner_dub.loadPackage(tool_pack);
		dscanner_dub.upgrade(UpgradeOptions.select);

		GeneratorSettings settings = this.makeAppSettings();
		foreach (dependencyPackage; m_project.dependencies)
		{
			auto cfgs = m_project.getPackageConfigs(settings.platform, null, true);
			auto buildSettings = dependencyPackage.getBuildSettings(settings.platform, cfgs[dependencyPackage.name]);
			foreach (importPath; buildSettings.importPaths) {
				settings.runArgs ~= ["-I", buildNormalizedPath(dependencyPackage.path.toNativeString(), importPath.idup)];
			}
		}

		string configFilePath = buildPath(m_project.rootPackage.path.toNativeString(), "dscanner.ini");
		if (!args.canFind("--config") && exists(configFilePath)) {
			settings.runArgs ~= ["--config", configFilePath];
		}

		settings.runArgs ~= args ~ [m_project.rootPackage.path.toNativeString()];
		dscanner_dub.generateProject("build", settings);
	}

	/** Prints the specified build settings necessary for building the root package.
	*/
	void listProjectData(GeneratorSettings settings, string[] requestedData, ListBuildSettingsFormat list_type)
	{
		import std.stdio;
		import std.ascii : newline;

		if (settings.overrideToolWorkingDirectory is NativePath.init)
			settings.overrideToolWorkingDirectory = m_rootPath;

		// Split comma-separated lists
		string[] requestedDataSplit =
			requestedData
			.map!(a => a.splitter(",").map!strip)
			.joiner()
			.array();

		auto data = m_project.listBuildSettings(settings, requestedDataSplit, list_type);

		string delimiter;
		final switch (list_type) with (ListBuildSettingsFormat) {
			case list: delimiter = newline ~ newline; break;
			case listNul: delimiter = "\0\0"; break;
			case commandLine: delimiter = " "; break;
			case commandLineNul: delimiter = "\0\0"; break;
		}

		write(data.joiner(delimiter));
		if (delimiter != "\0\0") writeln();
	}

	/// Cleans intermediate/cache files of the given package (or all packages)
	deprecated("Use `clean(Package)` instead")
	void cleanPackage(NativePath path)
	{
		auto ppack = Package.findPackageFile(path);
		enforce(!ppack.empty, "No package found.", path.toNativeString());
		this.clean(Package.load(path, ppack));
	}

	/// Ditto
	void clean()
	{
		const cache = this.m_dirs.cache;
		logInfo("Cleaning", Color.green, "all artifacts at %s",
			cache.toNativeString().color(Mode.bold));
		if (existsFile(cache))
			rmdirRecurse(cache.toNativeString());
	}

	/// Ditto
	void clean(Package pack)
	{
		const cache = this.packageCache(pack);
		logInfo("Cleaning", Color.green, "artifacts for package %s at %s",
			pack.name.color(Mode.bold),
			cache.toNativeString().color(Mode.bold));

		// TODO: clear target files and copy files
		if (existsFile(cache))
			rmdirRecurse(cache.toNativeString());
	}

	/// Fetches the package matching the dependency and places it in the specified location.
	deprecated("Use the overload that accepts either a `Version` or a `VersionRange` as second argument")
	Package fetch(string packageId, const Dependency dep, PlacementLocation location, FetchOptions options, string reason = "")
	{
		const vrange = dep.visit!(
			(VersionRange range) => range,
			function VersionRange (any) { throw new Exception("Cannot call `dub.fetch` with a " ~ typeof(any).stringof ~ " dependency"); }
		);
		return this.fetch(packageId, vrange, location, options, reason);
	}

	/// Ditto
	Package fetch(string packageId, in Version vers, PlacementLocation location, FetchOptions options, string reason = "")
	{
		return this.fetch(packageId, VersionRange(vers, vers), location, options, reason);
	}

	/// Ditto
	Package fetch(string packageId, in VersionRange range, PlacementLocation location, FetchOptions options, string reason = "")
	{
		auto basePackageName = getBasePackageName(packageId);
		Json pinfo;
		PackageSupplier supplier;
		foreach(ps; m_packageSuppliers){
			try {
				pinfo = ps.fetchPackageRecipe(basePackageName, Dependency(range), (options & FetchOptions.usePrerelease) != 0);
				if (pinfo.type == Json.Type.null_)
					continue;
				supplier = ps;
				break;
			} catch(Exception e) {
				logWarn("Package %s not found for %s: %s", packageId, ps.description, e.msg);
				logDebug("Full error: %s", e.toString().sanitize());
			}
		}
		enforce(pinfo.type != Json.Type.undefined, "No package "~packageId~" was found matching the dependency " ~ range.toString());
		Version ver = Version(pinfo["version"].get!string);

		// always upgrade branch based versions - TODO: actually check if there is a new commit available
		Package existing = m_packageManager.getPackage(packageId, ver, location);
		if (options & FetchOptions.printOnly) {
			if (existing && existing.version_ != ver)
				logInfo("A new version for %s is available (%s -> %s). Run \"%s\" to switch.",
					packageId.color(Mode.bold), existing.version_, ver,
					text("dub upgrade ", packageId).color(Mode.bold));
			return null;
		}

		if (existing) {
			if (!ver.isBranch() || !(options & FetchOptions.forceBranchUpgrade) || location == PlacementLocation.local) {
				// TODO: support git working trees by performing a "git pull" instead of this
				logDiagnostic("Package %s %s (in %s packages) is already present with the latest version, skipping upgrade.",
					packageId, ver, location.toString);
				return existing;
			} else {
				logInfo("Removing", Color.yellow, "%s %s to prepare replacement with a new version", packageId.color(Mode.bold), ver);
				if (!m_dryRun) m_packageManager.remove(existing);
			}
		}

		if (reason.length) logInfo("Fetching", Color.yellow, "%s %s (%s)", packageId.color(Mode.bold), ver, reason);
		else logInfo("Fetching", Color.yellow, "%s %s", packageId.color(Mode.bold), ver);
		if (m_dryRun) return null;

		logDebug("Acquiring package zip file");

		// repeat download on corrupted zips, see #1336
		foreach_reverse (i; 0..3)
		{
			import std.zip : ZipException;

			auto path = getTempFile(basePackageName, ".zip");
			supplier.fetchPackage(path, basePackageName, Dependency(range), (options & FetchOptions.usePrerelease) != 0); // Q: continue on fail?
			scope(exit) removeFile(path);
			logDiagnostic("Placing to %s...", location.toString());

			try {
				return m_packageManager.store(path, location, basePackageName, ver);
			} catch (ZipException e) {
				logInfo("Failed to extract zip archive for %s %s...", packageId, ver);
				// rethrow the exception at the end of the loop
				if (i == 0)
					throw e;
			}
		}
		assert(0, "Should throw a ZipException instead.");
	}

	/** Removes a specific locally cached package.

		This will delete the package files from disk and removes the
		corresponding entry from the list of known packages.

		Params:
			pack = Package instance to remove
	*/
	void remove(in Package pack)
	{
		logInfo("Removing", Color.yellow, "%s (in %s)", pack.name.color(Mode.bold), pack.path.toNativeString());
		if (!m_dryRun) m_packageManager.remove(pack);
	}

	/// Compatibility overload. Use the version without a `force_remove` argument instead.
	deprecated("Use `remove(pack)` directly instead, the boolean has no effect")
	void remove(in Package pack, bool force_remove)
	{
		remove(pack);
	}

	/// @see remove(string, string, RemoveLocation)
	enum RemoveVersionWildcard = "*";

	/** Removes one or more versions of a locally cached package.

		This will remove a given package with a specified version from the
		given location. It will remove at most one package, unless `version_`
		is set to `RemoveVersionWildcard`.

		Params:
			package_id = Name of the package to be removed
			location_ = Specifies the location to look for the given package
				name/version.
			resolve_version = Callback to select package version.
	*/
	void remove(string package_id, PlacementLocation location,
				scope size_t delegate(in Package[] packages) resolve_version)
	{
		enforce(!package_id.empty);
		if (location == PlacementLocation.local) {
			logInfo("To remove a locally placed package, make sure you don't have any data"
					~ "\nleft in it's directory and then simply remove the whole directory.");
			throw new Exception("dub cannot remove locally installed packages.");
		}

		Package[] packages;

		// Retrieve packages to be removed.
		foreach(pack; m_packageManager.getPackageIterator(package_id))
			if (m_packageManager.isManagedPackage(pack))
				packages ~= pack;

		// Check validity of packages to be removed.
		if(packages.empty) {
			throw new Exception("Cannot find package to remove. ("
				~ "id: '" ~ package_id ~ "', location: '" ~ to!string(location) ~ "'"
				~ ")");
		}

		// Sort package list in ascending version order
		packages.sort!((a, b) => a.version_ < b.version_);

		immutable idx = resolve_version(packages);
		if (idx == size_t.max)
			return;
		else if (idx != packages.length)
			packages = packages[idx .. idx + 1];

		logDebug("Removing %s packages.", packages.length);
		foreach(pack; packages) {
			try {
				remove(pack);
			} catch (Exception e) {
				logError("Failed to remove %s %s: %s", package_id, pack.version_, e.msg);
				logInfo("Continuing with other packages (if any).");
			}
		}
	}

	/// Compatibility overload. Use the version without a `force_remove` argument instead.
	deprecated("Use the overload without the 3rd argument (`force_remove`) instead")
	void remove(string package_id, PlacementLocation location, bool force_remove,
				scope size_t delegate(in Package[] packages) resolve_version)
	{
		remove(package_id, location, resolve_version);
	}

	/** Removes a specific version of a package.

		Params:
			package_id = Name of the package to be removed
			version_ = Identifying a version or a wild card. If an empty string
				is passed, the package will be removed from the location, if
				there is only one version retrieved. This will throw an
				exception, if there are multiple versions retrieved.
			location_ = Specifies the location to look for the given package
				name/version.
	 */
	void remove(string package_id, string version_, PlacementLocation location)
	{
		remove(package_id, location, (in packages) {
			if (version_ == RemoveVersionWildcard || version_.empty)
				return packages.length;

			foreach (i, p; packages) {
				if (p.version_ == Version(version_))
					return i;
			}
			throw new Exception("Cannot find package to remove. ("
				~ "id: '" ~ package_id ~ "', version: '" ~ version_ ~ "', location: '" ~ to!string(location) ~ "'"
				~ ")");
		});
	}

	/// Compatibility overload. Use the version without a `force_remove` argument instead.
	deprecated("Use the overload without force_remove instead")
	void remove(string package_id, string version_, PlacementLocation location, bool force_remove)
	{
		remove(package_id, version_, location);
	}

	/** Adds a directory to the list of locally known packages.

		Forwards to `PackageManager.addLocalPackage`.

		Params:
			path = Path to the package
			ver = Optional version to associate with the package (can be left
				empty)
			system = Make the package known system wide instead of user wide
				(requires administrator privileges).

		See_Also: `removeLocalPackage`
	*/
	void addLocalPackage(string path, string ver, bool system)
	{
		if (m_dryRun) return;
		m_packageManager.addLocalPackage(makeAbsolute(path), ver, system ? PlacementLocation.system : PlacementLocation.user);
	}

	/** Removes a directory from the list of locally known packages.

		Forwards to `PackageManager.removeLocalPackage`.

		Params:
			path = Path to the package
			system = Make the package known system wide instead of user wide
				(requires administrator privileges).

		See_Also: `addLocalPackage`
	*/
	void removeLocalPackage(string path, bool system)
	{
		if (m_dryRun) return;
		m_packageManager.removeLocalPackage(makeAbsolute(path), system ? PlacementLocation.system : PlacementLocation.user);
	}

	/** Registers a local directory to search for packages to use for satisfying
		dependencies.

		Params:
			path = Path to a directory containing package directories
			system = Make the package known system wide instead of user wide
				(requires administrator privileges).

		See_Also: `removeSearchPath`
	*/
	void addSearchPath(string path, bool system)
	{
		if (m_dryRun) return;
		m_packageManager.addSearchPath(makeAbsolute(path), system ? PlacementLocation.system : PlacementLocation.user);
	}

	/** Unregisters a local directory search path.

		Params:
			path = Path to a directory containing package directories
			system = Make the package known system wide instead of user wide
				(requires administrator privileges).

		See_Also: `addSearchPath`
	*/
	void removeSearchPath(string path, bool system)
	{
		if (m_dryRun) return;
		m_packageManager.removeSearchPath(makeAbsolute(path), system ? PlacementLocation.system : PlacementLocation.user);
	}

	/** Queries all package suppliers with the given query string.

		Returns a list of tuples, where the first entry is the human readable
		name of the package supplier and the second entry is the list of
		matched packages.

		Params:
		  query = the search term to match packages on

		See_Also: `PackageSupplier.searchPackages`
	*/
	auto searchPackages(string query)
	{
		import std.typecons : Tuple, tuple;
		Tuple!(string, PackageSupplier.SearchResult[])[] results;
		foreach (ps; this.m_packageSuppliers) {
			try
				results ~= tuple(ps.description, ps.searchPackages(query));
			catch (Exception e) {
				logWarn("Searching %s for '%s' failed: %s", ps.description, query, e.msg);
			}
		}
		return results.filter!(tup => tup[1].length);
	}

	/** Returns a list of all available versions (including branches) for a
		particular package.

		The list returned is based on the registered package suppliers. Local
		packages are not queried in the search for versions.

		See_also: `getLatestVersion`
	*/
	Version[] listPackageVersions(string name)
	{
		Version[] versions;
		auto basePackageName = getBasePackageName(name);
		foreach (ps; this.m_packageSuppliers) {
			try versions ~= ps.getVersions(basePackageName);
			catch (Exception e) {
				logWarn("Failed to get versions for package %s on provider %s: %s", name, ps.description, e.msg);
			}
		}
		return versions.sort().uniq.array;
	}

	/** Returns the latest available version for a particular package.

		This function returns the latest numbered version of a package. If no
		numbered versions are available, it will return an available branch,
		preferring "~master".

		Params:
			package_name: The name of the package in question.
			prefer_stable: If set to `true` (the default), returns the latest
				stable version, even if there are newer pre-release versions.

		See_also: `listPackageVersions`
	*/
	Version getLatestVersion(string package_name, bool prefer_stable = true)
	{
		auto vers = listPackageVersions(package_name);
		enforce(!vers.empty, "Failed to find any valid versions for a package name of '"~package_name~"'.");
		auto final_versions = vers.filter!(v => !v.isBranch && !v.isPreRelease).array;
		if (prefer_stable && final_versions.length) return final_versions[$-1];
		else return vers[$-1];
	}

	/** Initializes a directory with a package skeleton.

		Params:
			path = Path of the directory to create the new package in. The
				directory will be created if it doesn't exist.
			deps = List of dependencies to add to the package recipe.
			type = Specifies the type of the application skeleton to use.
			format = Determines the package recipe format to use.
			recipe_callback = Optional callback that can be used to
				customize the recipe before it gets written.
	*/
	void createEmptyPackage(NativePath path, string[] deps, string type,
		PackageFormat format = PackageFormat.sdl,
		scope void delegate(ref PackageRecipe, ref PackageFormat) recipe_callback = null,
		string[] app_args = [])
	{
		if (!path.absolute) path = m_rootPath ~ path;
		path.normalize();

		VersionRange[string] depVers;
		string[] notFound; // keep track of any failed packages in here
		foreach (dep; deps) {
			try {
				Version ver = getLatestVersion(dep);
				if (ver.isBranch())
					depVers[dep] = VersionRange(ver);
				else
					depVers[dep] = VersionRange.fromString("~>" ~ ver.toString());
			} catch (Exception e) {
				notFound ~= dep;
			}
		}

		if(notFound.length > 1){
			throw new Exception(.format("Couldn't find packages: %-(%s, %).", notFound));
		}
		else if(notFound.length == 1){
			throw new Exception(.format("Couldn't find package: %-(%s, %).", notFound));
		}

		if (m_dryRun) return;

		initPackage(path, depVers, type, format, recipe_callback);

		if (!["vibe.d", "deimos", "minimal"].canFind(type)) {
			runCustomInitialization(path, type, app_args);
		}

		//Act smug to the user.
		logInfo("Success", Color.green, "created empty project in %s", path.toNativeString().color(Mode.bold));
	}

	private void runCustomInitialization(NativePath path, string type, string[] runArgs)
	{
		string packageName = type;
		auto template_pack = m_packageManager.getBestPackage(packageName);
		if (!template_pack) {
			logInfo("%s is not present, getting and storing it user wide", packageName);
			template_pack = fetch(packageName, VersionRange.Any, defaultPlacementLocation, FetchOptions.none);
		}

		Package initSubPackage = m_packageManager.getSubPackage(template_pack, "init-exec", false);
		auto template_dub = new Dub(null, m_packageSuppliers);
		template_dub.loadPackage(initSubPackage);

		GeneratorSettings settings = this.makeAppSettings();
		settings.runArgs = runArgs;

		initSubPackage.recipe.buildSettings.workingDirectory = path.toNativeString();
		template_dub.generateProject("build", settings);
	}

	/** Converts the package recipe of the loaded root package to the given format.

		Params:
			destination_file_ext = The file extension matching the desired
				format. Possible values are "json" or "sdl".
			print_only = Print the converted recipe instead of writing to disk
	*/
	void convertRecipe(string destination_file_ext, bool print_only = false)
	{
		import std.path : extension;
		import std.stdio : stdout;
		import dub.recipe.io : serializePackageRecipe, writePackageRecipe;

		if (print_only) {
			auto dst = stdout.lockingTextWriter;
			serializePackageRecipe(dst, m_project.rootPackage.rawRecipe, "dub."~destination_file_ext);
			return;
		}

		auto srcfile = m_project.rootPackage.recipePath;
		auto srcext = srcfile.head.name.extension;
		if (srcext == "."~destination_file_ext) {
			// no logging before this point
			tagWidth.push(5);
			logError("Package format is already %s.", destination_file_ext);
			return;
		}

		writePackageRecipe(srcfile.parentPath ~ ("dub."~destination_file_ext), m_project.rootPackage.rawRecipe);
		removeFile(srcfile);
	}

	/** Runs DDOX to generate or serve documentation.

		Params:
			run = If set to true, serves documentation on a local web server.
				Otherwise generates actual HTML files.
			generate_args = Additional command line arguments to pass to
				"ddox generate-html" or "ddox serve-html".
	*/
	void runDdox(bool run, string[] generate_args = null)
	{
		import std.process : browse;

		if (m_dryRun) return;

		// allow to choose a custom ddox tool
		auto tool = m_project.rootPackage.recipe.ddoxTool;
		if (tool.empty) tool = "ddox";

		auto tool_pack = m_packageManager.getBestPackage(tool);
		if (!tool_pack) {
			logInfo("%s is not present, getting and storing it user wide", tool);
			tool_pack = fetch(tool, VersionRange.Any, defaultPlacementLocation, FetchOptions.none);
		}

		auto ddox_dub = new Dub(null, m_packageSuppliers);
		ddox_dub.loadPackage(tool_pack);
		ddox_dub.upgrade(UpgradeOptions.select);

		GeneratorSettings settings = this.makeAppSettings();

		auto filterargs = m_project.rootPackage.recipe.ddoxFilterArgs.dup;
		if (filterargs.empty) filterargs = ["--min-protection=Protected", "--only-documented"];

		settings.runArgs = "filter" ~ filterargs ~ "docs.json";
		ddox_dub.generateProject("build", settings);

		auto p = tool_pack.path;
		p.endsWithSlash = true;
		auto tool_path = p.toNativeString();

		if (run) {
			settings.runArgs = ["serve-html", "--navigation-type=ModuleTree", "docs.json", "--web-file-dir="~tool_path~"public"] ~ generate_args;
			browse("http://127.0.0.1:8080/");
		} else {
			settings.runArgs = ["generate-html", "--navigation-type=ModuleTree", "docs.json", "docs"] ~ generate_args;
		}
		ddox_dub.generateProject("build", settings);

		if (!run) {
			// TODO: ddox should copy those files itself
			version(Windows) runCommand(`xcopy /S /D "`~tool_path~`public\*" docs\`, null, m_rootPath.toNativeString());
			else runCommand("rsync -ru '"~tool_path~"public/' docs/", null, m_rootPath.toNativeString());
		}
	}

	/**
	 * Compute and returns the path were artifacts are stored
	 *
	 * Expose `dub.generator.generator : packageCache` with this instance's
	 * configured cache.
	 */
	protected NativePath packageCache (Package pkg) const
	{
		return .packageCache(this.m_dirs.cache, pkg);
	}

	/// Exposed because `commandLine` replicates `generateProject` for `dub describe`
	/// instead of treating it like a regular generator... Remove this once the
	/// flaw is fixed, and don't add more calls to this function!
	package(dub) NativePath cachePathDontUse () const @safe pure nothrow @nogc
	{
		return this.m_dirs.cache;
	}

	/// Make a `GeneratorSettings` suitable to generate tools (DDOC, DScanner, etc...)
	private GeneratorSettings makeAppSettings () const
	{
		GeneratorSettings settings;
		auto compiler_binary = this.defaultCompiler;

		settings.config = "application";
		settings.buildType = "debug";
		settings.compiler = getCompiler(compiler_binary);
		settings.platform = settings.compiler.determinePlatform(
			settings.buildSettings, compiler_binary, this.defaultArchitecture);
		if (this.defaultLowMemory)
			settings.buildSettings.options |= BuildOption.lowmem;
		if (this.defaultEnvironments)
			settings.buildSettings.addEnvironments(this.defaultEnvironments);
		if (this.defaultBuildEnvironments)
			settings.buildSettings.addBuildEnvironments(this.defaultBuildEnvironments);
		if (this.defaultRunEnvironments)
			settings.buildSettings.addRunEnvironments(this.defaultRunEnvironments);
		if (this.defaultPreGenerateEnvironments)
			settings.buildSettings.addPreGenerateEnvironments(this.defaultPreGenerateEnvironments);
		if (this.defaultPostGenerateEnvironments)
			settings.buildSettings.addPostGenerateEnvironments(this.defaultPostGenerateEnvironments);
		if (this.defaultPreBuildEnvironments)
			settings.buildSettings.addPreBuildEnvironments(this.defaultPreBuildEnvironments);
		if (this.defaultPostBuildEnvironments)
			settings.buildSettings.addPostBuildEnvironments(this.defaultPostBuildEnvironments);
		if (this.defaultPreRunEnvironments)
			settings.buildSettings.addPreRunEnvironments(this.defaultPreRunEnvironments);
		if (this.defaultPostRunEnvironments)
			settings.buildSettings.addPostRunEnvironments(this.defaultPostRunEnvironments);
		settings.run = true;
		settings.overrideToolWorkingDirectory = m_rootPath;

		return settings;
	}

	private void determineDefaultCompiler()
	{
		import std.file : thisExePath;
		import std.path : buildPath, dirName, expandTilde, isAbsolute, isDirSeparator;
		import std.range : front;

		// Env takes precedence
		if (auto envCompiler = environment.get("DC"))
			m_defaultCompiler = envCompiler;
		else
			m_defaultCompiler = m_config.defaultCompiler.expandTilde;
		if (m_defaultCompiler.length && m_defaultCompiler.isAbsolute)
			return;

		static immutable BinaryPrefix = `$DUB_BINARY_PATH`;
		if(m_defaultCompiler.startsWith(BinaryPrefix))
		{
			m_defaultCompiler = thisExePath().dirName() ~ m_defaultCompiler[BinaryPrefix.length .. $];
			return;
		}

		if (!find!isDirSeparator(m_defaultCompiler).empty)
			throw new Exception("defaultCompiler specified in a DUB config file cannot use an unqualified relative path:\n\n" ~ m_defaultCompiler ~
			"\n\nUse \"$DUB_BINARY_PATH/../path/you/want\" instead.");

		version (Windows) enum sep = ";", exe = ".exe";
		version (Posix) enum sep = ":", exe = "";

		auto compilers = ["dmd", "gdc", "gdmd", "ldc2", "ldmd2"];
		// If a compiler name is specified, look for it next to dub.
		// Otherwise, look for any of the common compilers adjacent to dub.
		if (m_defaultCompiler.length)
		{
			string compilerPath = buildPath(thisExePath().dirName(), m_defaultCompiler ~ exe);
			if (existsFile(compilerPath))
			{
				m_defaultCompiler = compilerPath;
				return;
			}
		}
		else
		{
			auto nextFound = compilers.find!(bin => existsFile(buildPath(thisExePath().dirName(), bin ~ exe)));
			if (!nextFound.empty)
			{
				m_defaultCompiler = buildPath(thisExePath().dirName(),  nextFound.front ~ exe);
				return;
			}
		}

		// If nothing found next to dub, search the user's PATH, starting
		// with the compiler name from their DUB config file, if specified.
		auto paths = environment.get("PATH", "").splitter(sep).map!NativePath;
		if (m_defaultCompiler.length && paths.canFind!(p => existsFile(p ~ (m_defaultCompiler~exe))))
			return;
		foreach (p; paths) {
			auto res = compilers.find!(bin => existsFile(p ~ (bin~exe)));
			if (!res.empty) {
				m_defaultCompiler = res.front;
				return;
			}
		}
		m_defaultCompiler = compilers[0];
	}

	unittest
	{
		import std.path: buildPath, absolutePath;
		auto dub = new TestDub(".", null, SkipPackageSuppliers.configured);
		immutable olddc = environment.get("DC", null);
		immutable oldpath = environment.get("PATH", null);
		immutable testdir = "test-determineDefaultCompiler";
		void repairenv(string name, string var)
		{
			if (var !is null)
				environment[name] = var;
			else if (name in environment)
				environment.remove(name);
		}
		scope (exit) repairenv("DC", olddc);
		scope (exit) repairenv("PATH", oldpath);
		scope (exit) rmdirRecurse(testdir);

		version (Windows) enum sep = ";", exe = ".exe";
		version (Posix) enum sep = ":", exe = "";

		immutable dmdpath = testdir.buildPath("dmd", "bin");
		immutable ldcpath = testdir.buildPath("ldc", "bin");
		mkdirRecurse(dmdpath);
		mkdirRecurse(ldcpath);
		immutable dmdbin = dmdpath.buildPath("dmd"~exe);
		immutable ldcbin = ldcpath.buildPath("ldc2"~exe);
		std.file.write(dmdbin, null);
		std.file.write(ldcbin, null);

		environment["DC"] = dmdbin.absolutePath();
		dub.determineDefaultCompiler();
		assert(dub.m_defaultCompiler == dmdbin.absolutePath());

		environment["DC"] = "dmd";
		environment["PATH"] = dmdpath ~ sep ~ ldcpath;
		dub.determineDefaultCompiler();
		assert(dub.m_defaultCompiler == "dmd");

		environment["DC"] = "ldc2";
		environment["PATH"] = dmdpath ~ sep ~ ldcpath;
		dub.determineDefaultCompiler();
		assert(dub.m_defaultCompiler == "ldc2");

		environment.remove("DC");
		environment["PATH"] = ldcpath ~ sep ~ dmdpath;
		dub.determineDefaultCompiler();
		assert(dub.m_defaultCompiler == "ldc2");
	}

	private NativePath makeAbsolute(NativePath p) const { return p.absolute ? p : m_rootPath ~ p; }
	private NativePath makeAbsolute(string p) const { return makeAbsolute(NativePath(p)); }
}


/// Option flags for `Dub.fetch`
enum FetchOptions
{
	none = 0,
	forceBranchUpgrade = 1<<0,
	usePrerelease = 1<<1,
	forceRemove = 1<<2, /// Deprecated, does nothing.
	printOnly = 1<<3,
}

/// Option flags for `Dub.upgrade`
enum UpgradeOptions
{
	none = 0,
	upgrade = 1<<1, /// Upgrade existing packages
	preRelease = 1<<2, /// inclde pre-release versions in upgrade
	forceRemove = 1<<3, /// Deprecated, does nothing.
	select = 1<<4, /// Update the dub.selections.json file with the upgraded versions
	dryRun = 1<<5, /// Instead of downloading new packages, just print a message to notify the user of their existence
	/*deprecated*/ printUpgradesOnly = dryRun, /// deprecated, use dryRun instead
	/*deprecated*/ useCachedResult = 1<<6, /// deprecated, has no effect
	noSaveSelections = 1<<7, /// Don't store updated selections on disk
}

/// Determines which of the default package suppliers are queried for packages.
public alias SkipPackageSuppliers = SPS;

private class DependencyVersionResolver : DependencyResolver!(Dependency, Dependency) {
	protected {
		Dub m_dub;
		UpgradeOptions m_options;
		Dependency[][string] m_packageVersions;
		Package[string] m_remotePackages;
		SelectedVersions m_selectedVersions;
		Package m_rootPackage;
		bool[string] m_packagesToUpgrade;
		Package[PackageDependency] m_packages;
		TreeNodes[][TreeNode] m_children;
	}


	this(Dub dub, UpgradeOptions options, Package root, SelectedVersions selected_versions)
	{
		assert(dub !is null);
		assert(root !is null);
		assert(selected_versions !is null);

		if (environment.get("DUB_NO_RESOLVE_LIMIT") !is null)
			super(ulong.max);
		else
		    super(1_000_000);

		m_dub = dub;
		m_options = options;
		m_rootPackage = root;
		m_selectedVersions = selected_versions;
	}

	Dependency[string] resolve(string[] filter)
	{
		foreach (name; filter)
			m_packagesToUpgrade[name] = true;
		return super.resolve(TreeNode(m_rootPackage.name, Dependency(m_rootPackage.version_)),
			(m_options & UpgradeOptions.dryRun) == 0);
	}

	protected bool isFixedPackage(string pack)
	{
		return m_packagesToUpgrade !is null && pack !in m_packagesToUpgrade;
	}

	protected override Dependency[] getAllConfigs(string pack)
	{
		if (auto pvers = pack in m_packageVersions)
			return *pvers;

		if ((!(m_options & UpgradeOptions.upgrade) || isFixedPackage(pack)) && m_selectedVersions.hasSelectedVersion(pack)) {
			auto ret = [m_selectedVersions.getSelectedVersion(pack)];
			logDiagnostic("Using fixed selection %s %s", pack, ret[0]);
			m_packageVersions[pack] = ret;
			return ret;
		}

		logDiagnostic("Search for versions of %s (%s package suppliers)", pack, m_dub.m_packageSuppliers.length);
		Version[] versions;
		foreach (p; m_dub.packageManager.getPackageIterator(pack))
			versions ~= p.version_;

		foreach (ps; m_dub.m_packageSuppliers) {
			try {
				auto vers = ps.getVersions(pack);
				vers.reverse();
				if (!vers.length) {
					logDiagnostic("No versions for %s for %s", pack, ps.description);
					continue;
				}

				versions ~= vers;
				break;
			} catch (Exception e) {
				logWarn("Package %s not found in %s: %s", pack, ps.description, e.msg);
				logDebug("Full error: %s", e.toString().sanitize);
			}
		}

		// sort by version, descending, and remove duplicates
		versions = versions.sort!"a>b".uniq.array;

		// move pre-release versions to the back of the list if no preRelease flag is given
		if (!(m_options & UpgradeOptions.preRelease))
			versions = versions.filter!(v => !v.isPreRelease).array ~ versions.filter!(v => v.isPreRelease).array;

		// filter out invalid/unreachable dependency specs
		versions = versions.filter!((v) {
				bool valid = getPackage(pack, Dependency(v)) !is null;
				if (!valid) logDiagnostic("Excluding invalid dependency specification %s %s from dependency resolution process.", pack, v);
				return valid;
			}).array;

		if (!versions.length) logDiagnostic("Nothing found for %s", pack);
		else logDiagnostic("Return for %s: %s", pack, versions);

		auto ret = versions.map!(v => Dependency(v)).array;
		m_packageVersions[pack] = ret;
		return ret;
	}

	protected override Dependency[] getSpecificConfigs(string pack, TreeNodes nodes)
	{
		if (!nodes.configs.path.empty || !nodes.configs.repository.empty) {
			if (getPackage(pack, nodes.configs)) return [nodes.configs];
			else return null;
		}
		else return null;
	}


	protected override TreeNodes[] getChildren(TreeNode node)
	{
		if (auto pc = node in m_children)
			return *pc;
		auto ret = getChildrenRaw(node);
		m_children[node] = ret;
		return ret;
	}

	private final TreeNodes[] getChildrenRaw(TreeNode node)
	{
		import std.array : appender;
		auto ret = appender!(TreeNodes[]);
		auto pack = getPackage(node.pack, node.config);
		if (!pack) {
			// this can hapen when the package description contains syntax errors
			logDebug("Invalid package in dependency tree: %s %s", node.pack, node.config);
			return null;
		}
		auto basepack = pack.basePackage;

		foreach (d; pack.getAllDependenciesRange()) {
			auto dbasename = getBasePackageName(d.name);

			// detect dependencies to the root package (or sub packages thereof)
			if (dbasename == basepack.name) {
				auto absdeppath = d.spec.mapToPath(pack.path).path;
				absdeppath.endsWithSlash = true;
				auto subpack = m_dub.m_packageManager.getSubPackage(basepack, getSubPackageName(d.name), true);
				if (subpack) {
					auto desireddeppath = basepack.path;
					desireddeppath.endsWithSlash = true;

					auto altdeppath = d.name == dbasename ? basepack.path : subpack.path;
					altdeppath.endsWithSlash = true;

					if (!d.spec.path.empty && absdeppath != desireddeppath)
						logWarn("Sub package %s, referenced by %s %s must be referenced using the path to its base package",
							subpack.name, pack.name, pack.version_);

					enforce(d.spec.path.empty || absdeppath == desireddeppath || absdeppath == altdeppath,
						format("Dependency from %s to %s uses wrong path: %s vs. %s",
							node.pack, subpack.name, absdeppath.toNativeString(), desireddeppath.toNativeString()));
				}
				ret ~= TreeNodes(d.name, node.config);
				continue;
			}

			DependencyType dt;
			if (d.spec.optional) {
				if (d.spec.default_) dt = DependencyType.optionalDefault;
				else dt = DependencyType.optional;
			} else dt = DependencyType.required;

			Dependency dspec = d.spec.mapToPath(pack.path);

			// if not upgrading, use the selected version
			if (!(m_options & UpgradeOptions.upgrade) && m_selectedVersions.hasSelectedVersion(dbasename))
				dspec = m_selectedVersions.getSelectedVersion(dbasename);

			// keep selected optional dependencies and avoid non-selected optional-default dependencies by default
			if (!m_selectedVersions.bare) {
				if (dt == DependencyType.optionalDefault && !m_selectedVersions.hasSelectedVersion(dbasename))
					dt = DependencyType.optional;
				else if (dt == DependencyType.optional && m_selectedVersions.hasSelectedVersion(dbasename))
					dt = DependencyType.optionalDefault;
			}

			ret ~= TreeNodes(d.name, dspec, dt);
		}
		return ret.data;
	}

	protected override bool matches(Dependency configs, Dependency config)
	{
		if (!configs.path.empty) return configs.path == config.path;
		return configs.merge(config).valid;
	}

	private Package getPackage(string name, Dependency dep)
	{
		auto key = PackageDependency(name, dep);
		if (auto pp = key in m_packages)
			return *pp;
		auto p = getPackageRaw(name, dep);
		m_packages[key] = p;
		return p;
	}

	private Package getPackageRaw(string name, Dependency dep)
	{
		auto basename = getBasePackageName(name);

		// for sub packages, first try to get them from the base package
		if (basename != name) {
			auto subname = getSubPackageName(name);
			auto basepack = getPackage(basename, dep);
			if (!basepack) return null;
			if (auto sp = m_dub.m_packageManager.getSubPackage(basepack, subname, true)) {
				return sp;
			} else if (!basepack.subPackages.canFind!(p => p.path.length)) {
				// note: external sub packages are handled further below
				auto spr = basepack.getInternalSubPackage(subname);
				if (!spr.isNull) {
					auto sp = new Package(spr.get, basepack.path, basepack);
					m_remotePackages[sp.name] = sp;
					return sp;
				} else {
					logDiagnostic("Sub package %s doesn't exist in %s %s.", name, basename, dep.version_);
					return null;
				}
			} else {
				logDiagnostic("External sub package %s %s not found.", name, dep.version_);
				return null;
			}
		}

		// shortcut if the referenced package is the root package
		if (basename == m_rootPackage.basePackage.name)
			return m_rootPackage.basePackage;

		if (!dep.repository.empty) {
			auto ret = m_dub.packageManager.loadSCMPackage(name, dep.repository);
			return ret !is null && dep.matches(ret.version_) ? ret : null;
		} else if (!dep.path.empty) {
			try {
				return m_dub.packageManager.getOrLoadPackage(dep.path);
			} catch (Exception e) {
				logDiagnostic("Failed to load path based dependency %s: %s", name, e.msg);
				logDebug("Full error: %s", e.toString().sanitize);
				return null;
			}
		}
		const vers = dep.version_;

		if (auto ret = m_dub.m_packageManager.getBestPackage(name, vers))
			return ret;

		auto key = name ~ ":" ~ vers.toString();
		if (auto ret = key in m_remotePackages)
			return *ret;

		auto prerelease = (m_options & UpgradeOptions.preRelease) != 0;

		auto rootpack = name.split(":")[0];

		foreach (ps; m_dub.m_packageSuppliers) {
			if (rootpack == name) {
				try {
					auto desc = ps.fetchPackageRecipe(name, dep, prerelease);
					if (desc.type == Json.Type.null_)
						continue;
					auto ret = new Package(desc);
					m_remotePackages[key] = ret;
					return ret;
				} catch (Exception e) {
					logDiagnostic("Metadata for %s %s could not be downloaded from %s: %s", name, vers, ps.description, e.msg);
					logDebug("Full error: %s", e.toString().sanitize);
				}
			} else {
				logDiagnostic("Package %s not found in base package description (%s). Downloading whole package.", name, vers.toString());
				try {
					FetchOptions fetchOpts;
					fetchOpts |= prerelease ? FetchOptions.usePrerelease : FetchOptions.none;
					m_dub.fetch(rootpack, vers, m_dub.defaultPlacementLocation, fetchOpts, "need sub package description");
					auto ret = m_dub.m_packageManager.getBestPackage(name, vers);
					if (!ret) {
						logWarn("Package %s %s doesn't have a sub package %s", rootpack, dep.version_, name);
						return null;
					}
					m_remotePackages[key] = ret;
					return ret;
				} catch (Exception e) {
					logDiagnostic("Package %s could not be downloaded from %s: %s", rootpack, ps.description, e.msg);
					logDebug("Full error: %s", e.toString().sanitize);
				}
			}
		}

		m_remotePackages[key] = null;

		logWarn("Package %s %s could not be loaded either locally, or from the configured package registries.", name, dep);
		return null;
	}
}

/**
 * An instance of Dub that does not rely on the environment
 *
 * This instance of dub should not read any environment variables,
 * nor should it do any file IO, to make it usable and reliable in unittests.
 * Currently it reads environment variables but does not read the configuration.
 */
package final class TestDub : Dub
{
    /// Forward to base constructor
    public this (string root = ".", PackageSupplier[] extras = null,
                 SkipPackageSuppliers skip = SkipPackageSuppliers.none)
    {
        super(root, extras, skip);
    }

    /// Avoid loading user configuration
    protected override void loadConfig() { /* No-op */ }
}

private struct SpecialDirs {
	/// The path where to store temporary files and directory
	NativePath temp;
	/// The system-wide dub-specific folder
	NativePath systemSettings;
	/// The dub-specific folder in the user home directory
	NativePath userSettings;
	/**
	 * User location where to install packages
	 *
	 * On Windows, this folder, unlike `userSettings`, does not roam,
	 * so an account on a company network will not save the content of this data,
	 * unlike `userSettings`.
	 *
	 * On Posix, this is currently equivalent to `userSettings`.
	 *
	 * See_Also: https://docs.microsoft.com/en-us/windows/win32/shell/knownfolderid
	 */
	NativePath userPackages;

	/**
	 * Location at which build/generation artifact will be written
	 *
	 * All build artifacts are stored under a single build cache,
	 * which is usually located under `$HOME/.dub/cache/` on POSIX,
	 * and `%LOCALAPPDATA%/dub/cache` on Windows.
	 *
	 * Versions of dub prior to v1.31.0 used to store  artifact under the
	 * project directory, but this led to issues with packages stored on
	 * read-only filesystem / location, and lingering artifacts scattered
	 * through the filesystem.
	 */
	NativePath cache;

	/// Returns: An instance of `SpecialDirs` initialized from the environment
	public static SpecialDirs make () {
		import std.file : tempDir;

		SpecialDirs result;
		result.temp = NativePath(tempDir);

		version(Windows) {
			result.systemSettings = NativePath(environment.get("ProgramData")) ~ "dub/";
			immutable appDataDir = environment.get("APPDATA");
			result.userSettings = NativePath(appDataDir) ~ "dub/";
			// LOCALAPPDATA is not defined before Windows Vista
			result.userPackages = NativePath(environment.get("LOCALAPPDATA", appDataDir)) ~ "dub";
		} else version(Posix) {
			result.systemSettings = NativePath("/var/lib/dub/");
			result.userSettings = NativePath(environment.get("HOME")) ~ ".dub/";
			if (!result.userSettings.absolute)
				result.userSettings = getWorkingDirectory() ~ result.userSettings;
			result.userPackages = result.userSettings;
		}
		result.cache = result.userPackages ~ "cache";
		return result;
	}
}
