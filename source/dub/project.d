/**
	Representing a full project, with a root Package and several dependencies.

	Copyright: © 2012-2013 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff, Sönke Ludwig
*/
module dub.project;

import dub.compilers.compiler;
import dub.dependency;
import dub.description;
import dub.internal.utils;
import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.data.json;
import dub.internal.vibecompat.inet.url;
import dub.package_;
import dub.packagemanager;
import dub.packagesupplier;
import dub.generators.generator;


// todo: cleanup imports.
import std.algorithm;
import std.array;
import std.conv;
import std.datetime;
import std.exception;
import std.file;
import std.process;
import std.string;
import std.typecons;
import std.zip;
import std.encoding : sanitize;

/// Representing a full project, with a root Package and several dependencies.
class Project {
	private {
		PackageManager m_packageManager;
		Json m_packageSettings;
		Package m_rootPackage;
		Package[] m_dependencies;
		Package[][Package] m_dependees;
		SelectedVersions m_selections;
	}

	this(PackageManager package_manager, Path project_path)
	{
		Package pack;
		auto packageFile = Package.findPackageFile(project_path);
		if (packageFile.empty) {
			logWarn("There was no package description found for the application in '%s'.", project_path.toNativeString());
			pack = new Package(null, project_path);
		} else {
			pack = package_manager.getOrLoadPackage(project_path, packageFile);
		}

		this(package_manager, pack);
	}

	this(PackageManager package_manager, Package pack)
	{
		m_packageManager = package_manager;
		m_rootPackage = pack;
		m_packageSettings = Json.emptyObject;

		try m_packageSettings = jsonFromFile(m_rootPackage.path ~ ".dub/dub.json", true);
		catch(Exception t) logDiagnostic("Failed to read .dub/dub.json: %s", t.msg);

		auto selverfile = m_rootPackage.path ~ SelectedVersions.defaultFile;
		if (existsFile(selverfile)) {
			try m_selections = new SelectedVersions(selverfile);
			catch(Exception e) {
				logDiagnostic("A " ~ SelectedVersions.defaultFile ~ " file was not found or failed to load:\n%s", e.msg);
				m_selections = new SelectedVersions;
			}
		} else m_selections = new SelectedVersions;

		reinit();
	}

	/// Gathers information
	@property string info()
	const {
		if(!m_rootPackage)
			return "-Unrecognized application in '"~m_rootPackage.path.toNativeString()~"' (probably no dub.json in this directory)";
		string s = "-Application identifier: " ~ m_rootPackage.name;
		s ~= "\n" ~ m_rootPackage.generateInfoString();
		s ~= "\n-Retrieved dependencies:";
		foreach(p; m_dependencies)
			s ~= "\n" ~ p.generateInfoString();
		return s;
	}

	/// Gets all retrieved packages as a "packageId" = "version" associative array
	@property string[string] cachedPackagesIDs() const {
		string[string] pkgs;
		foreach(p; m_dependencies)
			pkgs[p.name] = p.vers;
		return pkgs;
	}

	/// List of retrieved dependency Packages
	@property const(Package[]) dependencies() const { return m_dependencies; }

	/// Main package.
	@property inout(Package) rootPackage() inout { return m_rootPackage; }

	/// The versions to use for all dependencies. Call reinit() after changing these.
	@property inout(SelectedVersions) selections() inout { return m_selections; }

	/// Package manager instance used by the project.
	@property inout(PackageManager) packageManager() inout { return m_packageManager; }

	/** Allows iteration of the dependency tree in topological order
	*/
	int delegate(int delegate(ref const Package)) getTopologicalPackageList(bool children_first = false, in Package root_package = null, string[string] configs = null)
	const {
		const(Package) rootpack = root_package ? root_package : m_rootPackage;

		int iterator(int delegate(ref const Package) del)
		{
			int ret = 0;
			bool[const(Package)] visited;
			void perform_rec(in Package p){
				if( p in visited ) return;
				visited[p] = true;

				if( !children_first ){
					ret = del(p);
					if( ret ) return;
				}

				auto cfg = configs.get(p.name, null);

				foreach (dn, dv; p.dependencies) {
					// filter out dependencies not in the current configuration set
					if (!p.hasDependency(dn, cfg)) continue;
					auto dependency = getDependency(dn, dv.optional);
					if(dependency) perform_rec(dependency);
					if( ret ) return;
				}

				if( children_first ){
					ret = del(p);
					if( ret ) return;
				}
			}
			perform_rec(rootpack);
			return ret;
		}

		return &iterator;
	}

	inout(Package) getDependency(string name, bool isOptional)
	inout {
		foreach(dp; m_dependencies)
			if( dp.name == name )
				return dp;
		if(!isOptional) throw new Exception("Unknown dependency: "~name);
		else return null;
	}

	string getDefaultConfiguration(BuildPlatform platform, bool allow_non_library_configs = true)
	const {
		auto cfgs = getPackageConfigs(platform, null, allow_non_library_configs);
		return cfgs[m_rootPackage.name];
	}

	void validate()
	{
		// some basic package lint
		m_rootPackage.warnOnSpecialCompilerFlags();
		if (m_rootPackage.name != m_rootPackage.name.toLower()) {
			logWarn(`WARNING: DUB package names should always be lower case, please change `
				~ `to {"name": "%s"}. You can use {"targetName": "%s"} to keep the current `
				~ `executable name.`,
				m_rootPackage.name.toLower(), m_rootPackage.name);
		} else if (!m_rootPackage.info.name.all!(ch => ch >= 'a' && ch <= 'z' || ch >= '0' && ch <= '9' || ch == '-' || ch == '_')) {
			logWarn(`WARNING: DUB package names may only contain alphanumeric characters, `
				~ `as well as '-' and '_', please modify the "name" field in %s `
				~ `accordingly. You can use {"targetName": "%s"} to keep the current `
				~ `executable name.`,
				m_rootPackage.packageInfoFilename.toNativeString(), m_rootPackage.name);
		}
		enforce(!m_rootPackage.name.canFind(' '), "Aborting due to the package name containing spaces.");

		foreach (dn, ds; m_rootPackage.dependencies)
			if (ds.isExactVersion && ds.version_.isBranch) {
				logWarn("WARNING: A deprecated branch based version specification is used "
					~ "for the dependency %s. Please use numbered versions instead. Also "
					~ "note that you can still use the %s file to override a certain "
					~ "dependency to use a branch instead.",
					dn, SelectedVersions.defaultFile);
			}

		bool[string] visited;
		void validateDependenciesRec(Package pack) {
			foreach (name, vspec_; pack.dependencies) {
				if (name in visited) continue;
				visited[name] = true;

				auto basename = getBasePackageName(name);
				if (m_selections.hasSelectedVersion(basename)) {
					auto selver = m_selections.getSelectedVersion(basename);
					if (vspec_.merge(selver) == Dependency.invalid) {
						logWarn("Selected package %s %s does not match the dependency specification %s in package %s. Need to \"dub upgrade\"?",
							basename, selver, vspec_, pack.name);
					}
				}

				auto deppack = getDependency(name, true);
				if (deppack) validateDependenciesRec(deppack);
			}
		}
		validateDependenciesRec(m_rootPackage);
	}

	/// Rereads the applications state.
	void reinit()
	{
		m_dependencies = null;
		m_packageManager.refresh(false);

		void collectDependenciesRec(Package pack)
		{
			logDebug("Collecting dependencies for %s", pack.name);
			foreach (name, vspec_; pack.dependencies) {
				Dependency vspec = vspec_;
				Package p;
				if (!vspec.path.empty) {
					Path path = vspec.path;
					if (!path.absolute) path = pack.path ~ path;
					logDiagnostic("Adding local %s", path);
					p = m_packageManager.getOrLoadPackage(path);
					if (name.canFind(':')) p = m_packageManager.getSubPackage(p, getSubPackageName(name), false);
					enforce(p.name == name,
						format("Path based dependency %s is referenced with a wrong name: %s vs. %s",
							path.toNativeString(), name, p.name));
				}

				if (!p) {
					auto basename = getBasePackageName(name);
					if (name == m_rootPackage.basePackage.name) {
						vspec = Dependency(m_rootPackage.ver);
						p = m_rootPackage.basePackage;
					} else if (basename == m_rootPackage.basePackage.name) {
						vspec = Dependency(m_rootPackage.ver);
						try p = m_packageManager.getSubPackage(m_rootPackage.basePackage, getSubPackageName(name), false);
						catch (Exception e) {
							logDiagnostic("Error getting sub package %s: %s", name, e.msg);
							continue;
						}
					} else if (m_selections.hasSelectedVersion(basename)) {
						vspec = m_selections.getSelectedVersion(basename);
						p = m_packageManager.getBestPackage(name, vspec);
					} else if (m_dependencies.canFind!(d => getBasePackageName(d.name) == basename)) {
						auto idx = m_dependencies.countUntil!(d => getBasePackageName(d.name) == basename);
						auto bp = m_dependencies[idx].basePackage;
						vspec = Dependency(bp.path);
						p = m_packageManager.getSubPackage(bp, getSubPackageName(name), false);
					} else {
						logDiagnostic("Version selection for dependency %s (%s) of %s is missing.",
							basename, name, pack.name);
						continue;
					}
				}

				if (!p) {
					logDiagnostic("Missing dependency %s %s of %s", name, vspec, pack.name);
					continue;
				}

				if (!m_dependencies.canFind(p)) {
					logDiagnostic("Found dependency %s %s", name, vspec.toString());
					m_dependencies ~= p;
					p.warnOnSpecialCompilerFlags();
					collectDependenciesRec(p);
				}

				m_dependees[p] ~= pack;
				//enforce(p !is null, "Failed to resolve dependency "~name~" "~vspec.toString());
			}
		}
		collectDependenciesRec(m_rootPackage);
	}

	/// Returns the applications name.
	@property string name() const { return m_rootPackage ? m_rootPackage.name : "app"; }

	@property string[] configurations() const { return m_rootPackage.configurations; }

	/// Returns a map with the configuration for all packages in the dependency tree.
	string[string] getPackageConfigs(in BuildPlatform platform, string config, bool allow_non_library = true)
	const {
		struct Vertex { string pack, config; }
		struct Edge { size_t from, to; }

		Vertex[] configs;
		Edge[] edges;
		string[][string] parents;
		parents[m_rootPackage.name] = null;
		foreach (p; getTopologicalPackageList())
			foreach (d; p.dependencies.byKey)
				parents[d] ~= p.name;


		size_t createConfig(string pack, string config) {
			foreach (i, v; configs)
				if (v.pack == pack && v.config == config)
					return i;
			logDebug("Add config %s %s", pack, config);
			configs ~= Vertex(pack, config);
			return configs.length-1;
		}

		bool haveConfig(string pack, string config) {
			return configs.any!(c => c.pack == pack && c.config == config);
		}

		size_t createEdge(size_t from, size_t to) {
			auto idx = edges.countUntil(Edge(from, to));
			if (idx >= 0) return idx;
			logDebug("Including %s %s -> %s %s", configs[from].pack, configs[from].config, configs[to].pack, configs[to].config);
			edges ~= Edge(from, to);
			return edges.length-1;
		}

		void removeConfig(size_t i) {
			logDebug("Eliminating config %s for %s", configs[i].config, configs[i].pack);
			configs = configs.remove(i);
			edges = edges.filter!(e => e.from != i && e.to != i).array();
			foreach (ref e; edges) {
				if (e.from > i) e.from--;
				if (e.to > i) e.to--;
			}
		}

		bool isReachable(string pack, string conf) {
			if (pack == configs[0].pack && configs[0].config == conf) return true;
			foreach (e; edges)
				if (configs[e.to].pack == pack && configs[e.to].config == conf)
					return true;
			return false;
			//return (pack == configs[0].pack && conf == configs[0].config) || edges.canFind!(e => configs[e.to].pack == pack && configs[e.to].config == config);
		}

		bool isReachableByAllParentPacks(size_t cidx) {
			bool[string] r;
			foreach (p; parents[configs[cidx].pack]) r[p] = false;
			foreach (e; edges) {
				if (e.to != cidx) continue;
				if (auto pp = configs[e.from].pack in r) *pp = true;
			}
			foreach (bool v; r) if (!v) return false;
			return true;
		}

		string[] allconfigs_path;
		// create a graph of all possible package configurations (package, config) -> (subpackage, subconfig)
		void determineAllConfigs(in Package p)
		{
			auto idx = allconfigs_path.countUntil(p.name);
			enforce(idx < 0, format("Detected dependency cycle: %s", (allconfigs_path[idx .. $] ~ p.name).join("->")));
			allconfigs_path ~= p.name;
			scope (exit) allconfigs_path.length--;

			// first, add all dependency configurations
			foreach (dn; p.dependencies.byKey) {
				auto dp = getDependency(dn, true);
				if (!dp) continue;
				determineAllConfigs(dp);
			}

			// for each configuration, determine the configurations usable for the dependencies
			outer: foreach (c; p.getPlatformConfigurations(platform, p is m_rootPackage && allow_non_library)) {
				string[][string] depconfigs;
				foreach (dn; p.dependencies.byKey) {
					auto dp = getDependency(dn, true);
					if (!dp) continue;

					string[] cfgs;
					auto subconf = p.getSubConfiguration(c, dp, platform);
					if (!subconf.empty) cfgs = [subconf];
					else cfgs = dp.getPlatformConfigurations(platform);
					cfgs = cfgs.filter!(c => haveConfig(dn, c)).array;

					// if no valid configuration was found for a dependency, don't include the
					// current configuration
					if (!cfgs.length) {
						logDebug("Skip %s %s (missing configuration for %s)", p.name, c, dp.name);
						continue outer;
					}
					depconfigs[dn] = cfgs;
				}

				// add this configuration to the graph
				size_t cidx = createConfig(p.name, c);
				foreach (dn; p.dependencies.byKey)
					foreach (sc; depconfigs.get(dn, null))
						createEdge(cidx, createConfig(dn, sc));
			}
		}
		if (config.length) createConfig(m_rootPackage.name, config);
		determineAllConfigs(m_rootPackage);

		// successively remove configurations until only one configuration per package is left
		bool changed;
		do {
			// remove all configs that are not reachable by all parent packages
			changed = false;
			for (size_t i = 0; i < configs.length; ) {
				if (!isReachableByAllParentPacks(i)) {
					logDebug("NOT REACHABLE by (%s):", parents[configs[i].pack]);
					removeConfig(i);
					changed = true;
				} else i++;
			}

			// when all edges are cleaned up, pick one package and remove all but one config
			if (!changed) {
				foreach (p; getTopologicalPackageList()) {
					size_t cnt = 0;
					for (size_t i = 0; i < configs.length; ) {
						if (configs[i].pack == p.name) {
							if (++cnt > 1) {
								logDebug("NON-PRIMARY:");
								removeConfig(i);
							} else i++;
						} else i++;
					}
					if (cnt > 1) {
						changed = true;
						break;
					}
				}
			}
		} while (changed);

		// print out the resulting tree
		foreach (e; edges) logDebug("    %s %s -> %s %s", configs[e.from].pack, configs[e.from].config, configs[e.to].pack, configs[e.to].config);

		// return the resulting configuration set as an AA
		string[string] ret;
		foreach (c; configs) {
			assert(ret.get(c.pack, c.config) == c.config, format("Conflicting configurations for %s found: %s vs. %s", c.pack, c.config, ret[c.pack]));
			logDebug("Using configuration '%s' for %s", c.config, c.pack);
			ret[c.pack] = c.config;
		}

		// check for conflicts (packages missing in the final configuration graph)
		void checkPacksRec(in Package pack) {
			auto pc = pack.name in ret;
			enforce(pc !is null, "Could not resolve configuration for package "~pack.name);
			foreach (p, dep; pack.getDependencies(*pc)) {
				auto deppack = getDependency(p, dep.optional);
				if (deppack) checkPacksRec(deppack);
			}
		}
		checkPacksRec(m_rootPackage);

		return ret;
	}

	/**
	 * Fills dst with values from this project.
	 *
	 * dst gets initialized according to the given platform and config.
	 *
	 * Params:
	 *   dst = The BuildSettings struct to fill with data.
	 *   platform = The platform to retrieve the values for.
	 *   config = Values of the given configuration will be retrieved.
	 *   root_package = If non null, use it instead of the project's real root package.
	 *   shallow = If true, collects only build settings for the main package (including inherited settings) and doesn't stop on target type none and sourceLibrary.
	 */
	void addBuildSettings(ref BuildSettings dst, in BuildPlatform platform, string config, in Package root_package = null, bool shallow = false)
	const {
		auto configs = getPackageConfigs(platform, config);

		foreach (pkg; this.getTopologicalPackageList(false, root_package, configs)) {
			auto pkg_path = pkg.path.toNativeString();
			dst.addVersions(["Have_" ~ stripDlangSpecialChars(pkg.name)]);

			assert(pkg.name in configs, "Missing configuration for "~pkg.name);
			logDebug("Gathering build settings for %s (%s)", pkg.name, configs[pkg.name]);

			auto psettings = pkg.getBuildSettings(platform, configs[pkg.name]);
			if (psettings.targetType != TargetType.none) {
				if (shallow && pkg !is m_rootPackage)
					psettings.sourceFiles = null;
				processVars(dst, this, pkg, psettings);
				if (psettings.importPaths.empty)
					logWarn(`Package %s (configuration "%s") defines no import paths, use {"importPaths": [...]} or the default package directory structure to fix this.`, pkg.name, configs[pkg.name]);
				if (psettings.mainSourceFile.empty && pkg is m_rootPackage && psettings.targetType == TargetType.executable)
					logWarn(`Executable configuration "%s" of package %s defines no main source file, this may cause certain build modes to fail. Add an explicit "mainSourceFile" to the package description to fix this.`, configs[pkg.name], pkg.name);
			}
			if (pkg is m_rootPackage) {
				if (!shallow) {
					enforce(psettings.targetType != TargetType.none, "Main package has target type \"none\" - stopping build.");
					enforce(psettings.targetType != TargetType.sourceLibrary, "Main package has target type \"sourceLibrary\" which generates no target - stopping build.");
				}
				dst.targetType = psettings.targetType;
				dst.targetPath = psettings.targetPath;
				dst.targetName = psettings.targetName;
				if (!psettings.workingDirectory.empty)
					dst.workingDirectory = processVars(psettings.workingDirectory, this, pkg, true);
				if (psettings.mainSourceFile.length)
					dst.mainSourceFile = processVars(psettings.mainSourceFile, this, pkg, true);
			}
		}

		// always add all version identifiers of all packages
		foreach (pkg; this.getTopologicalPackageList(false, null, configs)) {
			auto psettings = pkg.getBuildSettings(platform, configs[pkg.name]);
			dst.addVersions(psettings.versions);
		}
	}

	void addBuildTypeSettings(ref BuildSettings dst, in BuildPlatform platform, string build_type)
	{
		bool usedefflags = !(dst.requirements & BuildRequirement.noDefaultFlags);
		if (usedefflags) {
			BuildSettings btsettings;
			m_rootPackage.addBuildTypeSettings(btsettings, platform, build_type);
			processVars(dst, this, m_rootPackage, btsettings);
		}
	}

	/// Determines if the given dependency is already indirectly referenced by other dependencies of pack.
	bool isRedundantDependency(in Package pack, in Package dependency)
	const {
		foreach (dep; pack.dependencies.byKey) {
			auto dp = getDependency(dep, true);
			if (!dp) continue;
			if (dp is dependency) continue;
			foreach (ddp; getTopologicalPackageList(false, dp))
				if (ddp is dependency) return true;
		}
		return false;
	}

	/*bool iterateDependencies(bool delegate(Package pack, string dep_name, Dependency dep_spec) del)
	{
		bool all_found = true;

		bool[string] visited;
		void iterate(Package pack)
		{
			if (pack.name in visited) return;
			visited[pack.name] = true;

			foreach (dn, ds; pack.dependencies) {
				auto dep = del(pack, dn, ds);
				if (dep) iterateDependencies(dep);
				else all_found = false;
			}
		}

		return all_found;
	}*/

	/// Outputs a build description of the project, including its dependencies.
	ProjectDescription describe(BuildPlatform platform, string config, string build_type = null)
	{
		import dub.generators.targetdescription;

		// store basic build parameters
		ProjectDescription ret;
		ret.rootPackage = m_rootPackage.name;
		ret.configuration = config;
		ret.buildType = build_type;
		ret.compiler = platform.compiler;
		ret.architecture = platform.architecture;
		ret.platform = platform.platform;

		// collect high level information about projects (useful for IDE display)
		auto configs = getPackageConfigs(platform, config);
		ret.packages ~= m_rootPackage.describe(platform, config);
		foreach (dep; m_dependencies)
			ret.packages ~= dep.describe(platform, configs[dep.name]);

		if (build_type.length) {
			// collect build target information (useful for build tools)
			GeneratorSettings settings;
			settings.platform = platform;
			settings.compiler = getCompiler(platform.compilerBinary);
			settings.config = config;
			settings.buildType = build_type;
			auto gen = new TargetDescriptionGenerator(this);
			try {
				gen.generate(settings);
				ret.targets = gen.targetDescriptions;
				ret.targetLookup = gen.targetDescriptionLookup;
			} catch (Exception e) {
				logDiagnostic("Skipping targets description: %s", e.msg);
				logDebug("Full error: %s", e.toString().sanitize);
			}
		}

		return ret;
	}
	/// ditto
	deprecated void describe(ref Json dst, BuildPlatform platform, string config)
	{
		auto desc = describe(platform, config);
		foreach (string key, value; desc.serializeToJson())
			dst[key] = value;
	}

	private string[] listBuildSetting(string attributeName)(BuildPlatform platform, string config, ProjectDescription projectDescription)
	{
		return listBuildSetting!attributeName(platform, getPackageConfigs(platform, config), projectDescription);
	}
	
	private string[] listBuildSetting(string attributeName)(BuildPlatform platform, string[string] configs, ProjectDescription projectDescription)
	{
		import std.path : buildPath, dirSeparator;
		import std.range : only;

		string[] list;
		
		auto targetDescription = projectDescription.targetLookup[projectDescription.rootPackage];
		auto buildSettings = targetDescription.buildSettings;
		
		// Return any BuildSetting member attributeName as a range of strings. Don't attempt to fixup values.
		// allowEmptyString: When the value is a string (as opposed to string[]),
		//                   is empty string an actual permitted value instead of
		//                   a missing value?
		auto getRawBuildSetting(Package pack, bool allowEmptyString) {
			auto value = __traits(getMember, buildSettings, attributeName);
			
			static if( is(typeof(value) == string[]) )
				return value;
			else static if( is(typeof(value) == string) )
			{
				auto ret = only(value);

				// only() has a different return type from only(value), so we
				// have to empty the range rather than just returning only().
				if(value.empty && !allowEmptyString) {
					ret.popFront();
					assert(ret.empty);
				}

				return ret;
			}
			else static if( is(typeof(value) == enum) )
				return only(value);
			else static if( is(typeof(value) == BuildRequirements) )
				return only(cast(BuildRequirement) cast(int) value.values);
			else static if( is(typeof(value) == BuildOptions) )
				return only(cast(BuildOption) cast(int) value.values);
			else
				static assert(false, "Type of BuildSettings."~attributeName~" is unsupported.");
		}
		
		// Adjust BuildSetting member attributeName as needed.
		// Returns a range of strings.
		auto getFixedBuildSetting(Package pack) {
			// Is relative path(s) to a directory?
			enum isRelativeDirectory =
				attributeName == "importPaths" || attributeName == "stringImportPaths" ||
				attributeName == "targetPath" || attributeName == "workingDirectory";

			// Is relative path(s) to a file?
			enum isRelativeFile =
				attributeName == "sourceFiles" || attributeName == "importFiles" ||
				attributeName == "stringImportFiles" || attributeName == "copyFiles" ||
				attributeName == "mainSourceFile";
			
			// For these, empty string means "main project directory", not "missing value"
			enum allowEmptyString =
				attributeName == "targetPath" || attributeName == "workingDirectory";
			
			enum isEnumBitfield =
				attributeName == "targetType" || attributeName == "requirements" ||
				attributeName == "options";
			
			auto values = getRawBuildSetting(pack, allowEmptyString);
			auto fixRelativePath = (string importPath) => buildPath(pack.path.toString(), importPath);
			auto ensureTrailingSlash = (string path) => path.endsWith(dirSeparator) ? path : path ~ dirSeparator;

			static if(isRelativeDirectory) {
				// Return full paths for the paths, making sure a
				// directory separator is on the end of each path.
				return values.map!(fixRelativePath).map!(ensureTrailingSlash);
			}
			else static if(isRelativeFile) {
				// Return full paths.
				return values.map!(fixRelativePath);
			}
			else static if(isEnumBitfield)
				return bitFieldNames(values.front);
			else
				return values;
		}

		foreach(value; getFixedBuildSetting(m_rootPackage)) {
			list ~= value;
		}

		return list;
	}

	private string[] listBuildSetting(BuildPlatform platform, string[string] configs, ProjectDescription projectDescription, string requestedData)
	{
		switch(requestedData)
		{
		case "target-type":            return listBuildSetting!"targetType"(platform, configs, projectDescription);
		case "target-path":            return listBuildSetting!"targetPath"(platform, configs, projectDescription);
		case "target-name":            return listBuildSetting!"targetName"(platform, configs, projectDescription);
		case "working-directory":      return listBuildSetting!"workingDirectory"(platform, configs, projectDescription);
		case "main-source-file":       return listBuildSetting!"mainSourceFile"(platform, configs, projectDescription);
		case "dflags":                 return listBuildSetting!"dflags"(platform, configs, projectDescription);
		case "lflags":                 return listBuildSetting!"lflags"(platform, configs, projectDescription);
		case "libs":                   return listBuildSetting!"libs"(platform, configs, projectDescription);
		case "source-files":           return listBuildSetting!"sourceFiles"(platform, configs, projectDescription);
		case "copy-files":             return listBuildSetting!"copyFiles"(platform, configs, projectDescription);
		case "versions":               return listBuildSetting!"versions"(platform, configs, projectDescription);
		case "debug-versions":         return listBuildSetting!"debugVersions"(platform, configs, projectDescription);
		case "import-paths":           return listBuildSetting!"importPaths"(platform, configs, projectDescription);
		case "string-import-paths":    return listBuildSetting!"stringImportPaths"(platform, configs, projectDescription);
		case "import-files":           return listBuildSetting!"importFiles"(platform, configs, projectDescription);
		case "string-import-files":    return listBuildSetting!"stringImportFiles"(platform, configs, projectDescription);
		case "pre-generate-commands":  return listBuildSetting!"preGenerateCommands"(platform, configs, projectDescription);
		case "post-generate-commands": return listBuildSetting!"postGenerateCommands"(platform, configs, projectDescription);
		case "pre-build-commands":     return listBuildSetting!"preBuildCommands"(platform, configs, projectDescription);
		case "post-build-commands":    return listBuildSetting!"postBuildCommands"(platform, configs, projectDescription);
		case "requirements":           return listBuildSetting!"requirements"(platform, configs, projectDescription);
		case "options":                return listBuildSetting!"options"(platform, configs, projectDescription);

		default:
			enforce(false, "--data="~requestedData~
				" is not a valid option. See 'dub describe --help' for accepted --data= values.");
		}
		
		assert(0);
	}

	/// Outputs requested data for the project, optionally including its dependencies.
	string[] listBuildSettings(BuildPlatform platform, string config, string buildType, string[] requestedData)
	{
		auto projectDescription = describe(platform, config, buildType);
		auto configs = getPackageConfigs(platform, config);

		// Include link dependencies
		auto target = projectDescription.targetLookup[projectDescription.rootPackage];
		auto bs = target.buildSettings;
		foreach (ldep; target.linkDependencies) {
			auto dbs = projectDescription.targetLookup[ldep].buildSettings;
			if (bs.targetType != TargetType.staticLibrary) {
				bs.addLibs((Path(dbs.targetPath) ~ getTargetFileName(dbs, platform)).toNativeString());
			}
		}
		target.buildSettings = bs;

		// Update projectDescription.targets
		projectDescription.targetLookup[projectDescription.rootPackage] = target;
		foreach (ref t; projectDescription.targets) {
			if(t.rootPackage == target.rootPackage) {
				t = target;
				break;
			}
		}

		return requestedData
			.map!(dataName => listBuildSetting(platform, configs, projectDescription, dataName))
			.joiner([""]) // Blank line between each type of requestedData
			.array();
	}

	/// Outputs the import paths for the project, including its dependencies.
	string[] listImportPaths(BuildPlatform platform, string config, string buildType)
	{
		auto projectDescription = describe(platform, config, buildType);
		return listBuildSetting!"importPaths"(platform, config, projectDescription);
	}

	/// Outputs the string import paths for the project, including its dependencies.
	string[] listStringImportPaths(BuildPlatform platform, string config, string buildType)
	{
		auto projectDescription = describe(platform, config, buildType);
		return listBuildSetting!"stringImportPaths"(platform, config, projectDescription);
	}

	void saveSelections()
	{
		assert(m_selections !is null, "Cannot save selections for non-disk based project (has no selections).");
		if (m_selections.hasSelectedVersion(m_rootPackage.basePackage.name))
			m_selections.deselectVersion(m_rootPackage.basePackage.name);

		auto path = m_rootPackage.path ~ SelectedVersions.defaultFile;
		if (m_selections.dirty || !existsFile(path))
			m_selections.save(path);
	}

	bool isUpgradeCacheUpToDate()
	{
		try {
			auto datestr = m_packageSettings["dub"].opt!(Json[string]).get("lastUpgrade", Json("")).get!string;
			if (!datestr.length) return false;
			auto date = SysTime.fromISOExtString(datestr);
			if ((Clock.currTime() - date) > 1.days) return false;
			return true;
		} catch (Exception t) {
			logDebug("Failed to get the last upgrade time: %s", t.msg);
			return false;
		}
	}

	Dependency[string] getUpgradeCache()
	{
		try {
			Dependency[string] ret;
			foreach (string p, d; m_packageSettings["dub"].opt!(Json[string]).get("cachedUpgrades", Json.emptyObject))
				ret[p] = SelectedVersions.dependencyFromJson(d);
			return ret;
		} catch (Exception t) {
			logDebug("Failed to get cached upgrades: %s", t.msg);
			return null;
		}
	}

	void setUpgradeCache(Dependency[string] versions)
	{
		logDebug("markUpToDate");
		Json create(ref Json json, string object) {
			if (json[object].type == Json.Type.undefined) json[object] = Json.emptyObject;
			return json[object];
		}
		create(m_packageSettings, "dub");
		m_packageSettings["dub"]["lastUpgrade"] = Clock.currTime().toISOExtString();

		create(m_packageSettings["dub"], "cachedUpgrades");
		foreach (p, d; versions)
			m_packageSettings["dub"]["cachedUpgrades"][p] = SelectedVersions.dependencyToJson(d);

		writeDubJson();
	}

	private void writeDubJson() {
		// don't bother to write an empty file
		if( m_packageSettings.length == 0 ) return;

		try {
			logDebug("writeDubJson");
			auto dubpath = m_rootPackage.path~".dub";
			if( !exists(dubpath.toNativeString()) ) mkdir(dubpath.toNativeString());
			auto dstFile = openFile((dubpath~"dub.json").toString(), FileMode.CreateTrunc);
			scope(exit) dstFile.close();
			dstFile.writePrettyJsonString(m_packageSettings);
		} catch( Exception e ){
			logWarn("Could not write .dub/dub.json.");
		}
	}
}

/// Actions to be performed by the dub
struct Action {
	enum Type {
		fetch,
		remove,
		conflict,
		failure
	}

	immutable {
		Type type;
		string packageId;
		PlacementLocation location;
		Dependency vers;
		Version existingVersion;
	}
	const Package pack;
	const Dependency[string] issuer;

	static Action get(string pkg, PlacementLocation location, in Dependency dep, Dependency[string] context, Version old_version = Version.UNKNOWN)
	{
		return Action(Type.fetch, pkg, location, dep, context, old_version);
	}

	static Action remove(Package pkg, Dependency[string] context)
	{
		return Action(Type.remove, pkg, context);
	}

	static Action conflict(string pkg, in Dependency dep, Dependency[string] context)
	{
		return Action(Type.conflict, pkg, PlacementLocation.user, dep, context);
	}

	static Action failure(string pkg, in Dependency dep, Dependency[string] context)
	{
		return Action(Type.failure, pkg, PlacementLocation.user, dep, context);
	}

	private this(Type id, string pkg, PlacementLocation location, in Dependency d, Dependency[string] issue, Version existing_version = Version.UNKNOWN)
	{
		this.type = id;
		this.packageId = pkg;
		this.location = location;
		this.vers = d;
		this.issuer = issue;
		this.existingVersion = existing_version;
	}

	private this(Type id, Package pkg, Dependency[string] issue)
	{
		pack = pkg;
		type = id;
		packageId = pkg.name;
		vers = cast(immutable)Dependency(pkg.ver);
		issuer = issue;
	}

	string toString() const {
		return to!string(type) ~ ": " ~ packageId ~ ", " ~ to!string(vers);
	}
}


/// Indicates where a package has been or should be placed to.
enum PlacementLocation {
	/// Packages retrived with 'local' will be placed in the current folder
	/// using the package name as destination.
	local,
	/// Packages with 'userWide' will be placed in a folder accessible by
	/// all of the applications from the current user.
	user,
	/// Packages retrieved with 'systemWide' will be placed in a shared folder,
	/// which can be accessed by all users of the system.
	system
}

/// The default placement location of fetched packages. Can be changed by --local or --system.
auto defaultPlacementLocation = PlacementLocation.user;

void processVars(ref BuildSettings dst, in Project project, in Package pack, BuildSettings settings, bool include_target_settings = false)

{
	dst.addDFlags(processVars(project, pack, settings.dflags));
	dst.addLFlags(processVars(project, pack, settings.lflags));
	dst.addLibs(processVars(project, pack, settings.libs));
	dst.addSourceFiles(processVars(project, pack, settings.sourceFiles, true));
	dst.addImportFiles(processVars(project, pack, settings.importFiles, true));
	dst.addStringImportFiles(processVars(project, pack, settings.stringImportFiles, true));
	dst.addCopyFiles(processVars(project, pack, settings.copyFiles, true));
	dst.addVersions(processVars(project, pack, settings.versions));
	dst.addDebugVersions(processVars(project, pack, settings.debugVersions));
	dst.addImportPaths(processVars(project, pack, settings.importPaths, true));
	dst.addStringImportPaths(processVars(project, pack, settings.stringImportPaths, true));
	dst.addPreGenerateCommands(processVars(project, pack, settings.preGenerateCommands));
	dst.addPostGenerateCommands(processVars(project, pack, settings.postGenerateCommands));
	dst.addPreBuildCommands(processVars(project, pack, settings.preBuildCommands));
	dst.addPostBuildCommands(processVars(project, pack, settings.postBuildCommands));
	dst.addRequirements(settings.requirements);
	dst.addOptions(settings.options);

	if (include_target_settings) {
		dst.targetType = settings.targetType;
		dst.targetPath = processVars(settings.targetPath, project, pack, true);
		dst.targetName = settings.targetName;
		if (!settings.workingDirectory.empty)
			dst.workingDirectory = processVars(settings.workingDirectory, project, pack, true);
		if (settings.mainSourceFile.length)
			dst.mainSourceFile = processVars(settings.mainSourceFile, project, pack, true);
	}
}

private string[] processVars(in Project project, in Package pack, string[] vars, bool are_paths = false)
{
	auto ret = appender!(string[])();
	processVars(ret, project, pack, vars, are_paths);
	return ret.data;

}
private void processVars(ref Appender!(string[]) dst, in Project project, in Package pack, string[] vars, bool are_paths = false)
{
	foreach (var; vars) dst.put(processVars(var, project, pack, are_paths));
}

private string processVars(string var, in Project project, in Package pack, bool is_path)
{
	auto idx = std.string.indexOf(var, '$');
	if (idx >= 0) {
		auto vres = appender!string();
		while (idx >= 0) {
			if (idx+1 >= var.length) break;
			if (var[idx+1] == '$') {
				vres.put(var[0 .. idx+1]);
				var = var[idx+2 .. $];
			} else {
				vres.put(var[0 .. idx]);
				var = var[idx+1 .. $];

				size_t idx2 = 0;
				while( idx2 < var.length && isIdentChar(var[idx2]) ) idx2++;
				auto varname = var[0 .. idx2];
				var = var[idx2 .. $];

				vres.put(getVariable(varname, project, pack));
			}
			idx = std.string.indexOf(var, '$');
		}
		vres.put(var);
		var = vres.data;
	}
	if (is_path) {
		auto p = Path(var);
		if (!p.absolute) {
			logDebug("Fixing relative path: %s ~ %s", pack.path.toNativeString(), p.toNativeString());
			return (pack.path ~ p).toNativeString();
		} else return p.toNativeString();
	} else return var;
}

private string getVariable(string name, in Project project, in Package pack)
{
	if (name == "PACKAGE_DIR") return pack.path.toNativeString();
	if (name == "ROOT_PACKAGE_DIR") return project.rootPackage.path.toNativeString();

	if (name.endsWith("_PACKAGE_DIR")) {
		auto pname = name[0 .. $-12];
		foreach (prj; project.getTopologicalPackageList())
			if (prj.name.toUpper().replace("-", "_") == pname)
				return prj.path.toNativeString();
	}

	auto envvar = environment.get(name);
	if (envvar !is null) return envvar;

	throw new Exception("Invalid variable: "~name);
}

private bool isIdentChar(dchar ch)
{
	return ch >= 'A' && ch <= 'Z' || ch >= 'a' && ch <= 'z' || ch >= '0' && ch <= '9' || ch == '_';
}

string stripDlangSpecialChars(string s)
{
	import std.array;
	import std.uni;
	auto ret = appender!string();
	foreach(ch; s)
		ret.put(isIdentChar(ch) ? ch : '_');
	return ret.data;
}

final class SelectedVersions {
	private struct Selected {
		Dependency dep;
		//Dependency[string] packages;
	}
	private {
		enum FileVersion = 1;
		Selected[string] m_selections;
		bool m_dirty = false; // has changes since last save
	}

	enum defaultFile = "dub.selections.json";

	this() {}

	this(Json data)
	{
		deserialize(data);
		m_dirty = false;
	}

	this(Path path)
	{
		auto json = jsonFromFile(path);
		deserialize(json);
		m_dirty = false;
	}

	@property string[] selectedPackages() const { return m_selections.keys; }

	@property bool dirty() const { return m_dirty; }

	void clear()
	{
		m_selections = null;
		m_dirty = true;
	}

	void set(SelectedVersions versions)
	{
		m_selections = versions.m_selections.dup;
		m_dirty = true;
	}

	void selectVersion(string package_id, Version version_)
	{
		if (auto ps = package_id in m_selections) {
			if (ps.dep == Dependency(version_))
				return;
		}
		m_selections[package_id] = Selected(Dependency(version_)/*, issuer*/);
		m_dirty = true;
	}

	void selectVersion(string package_id, Path path)
	{
		if (auto ps = package_id in m_selections) {
			if (ps.dep == Dependency(path))
				return;
		}
		m_selections[package_id] = Selected(Dependency(path));
		m_dirty = true;
	}

	void deselectVersion(string package_id)
	{
		m_selections.remove(package_id);
		m_dirty = true;
	}

	bool hasSelectedVersion(string packageId)
	const {
		return (packageId in m_selections) !is null;
	}

	Dependency getSelectedVersion(string packageId)
	const {
		enforce(hasSelectedVersion(packageId));
		return m_selections[packageId].dep;
	}

	void save(Path path)
	{
		Json json = serialize();
		auto file = openFile(path, FileMode.CreateTrunc);
		scope(exit) file.close();
		file.writePrettyJsonString(json);
		file.put('\n');
		m_dirty = false;
	}

	static Json dependencyToJson(Dependency d)
	{
		if (d.path.empty) return Json(d.version_.toString());
		else return serializeToJson(["path": d.path.toString()]);
	}

	static Dependency dependencyFromJson(Json j)
	{
		if (j.type == Json.Type.string)
			return Dependency(Version(j.get!string));
		else if (j.type == Json.Type.object)
			return Dependency(Path(j.path.get!string));
		else throw new Exception(format("Unexpected type for dependency: %s", j.type));
	}

	Json serialize()
	const {
		Json json = serializeToJson(m_selections);
		Json serialized = Json.emptyObject;
		serialized.fileVersion = FileVersion;
		serialized.versions = Json.emptyObject;
		foreach (p, v; m_selections)
			serialized.versions[p] = dependencyToJson(v.dep);
		return serialized;
	}

	private void deserialize(Json json)
	{
		enforce(cast(int)json["fileVersion"] == FileVersion, "Mismatched dub.select.json version: " ~ to!string(cast(int)json["fileVersion"]) ~ "vs. " ~to!string(FileVersion));
		clear();
		scope(failure) clear();
		foreach (string p, v; json.versions)
			m_selections[p] = Selected(dependencyFromJson(v));
	}
}

