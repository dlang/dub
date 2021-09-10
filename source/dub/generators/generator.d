/**
	Generator for project files

	Copyright: © 2012-2013 Matthias Dondorff, © 2013-2016 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff
*/
module dub.generators.generator;

import dub.compilers.compiler;
import dub.generators.cmake;
import dub.generators.build;
import dub.generators.sublimetext;
import dub.generators.visuald;
import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.inet.path;
import dub.package_;
import dub.packagemanager;
import dub.project;

import std.algorithm : map, filter, canFind, balancedParens;
import std.array : array, appender, join;
import std.exception;
import std.file;
import std.string;


/**
	Common interface for project generators/builders.
*/
class ProjectGenerator
{
	/** Information about a single binary target.

		A binary target can either be an executable or a static/dynamic library.
		It consists of one or more packages.
	*/
	struct TargetInfo {
		/// The root package of this target
		Package pack;

		/// All packages compiled into this target
		Package[] packages;

		/// The configuration used for building the root package
		string config;

		/** Build settings used to build the target.

			The build settings include all sources of all contained packages.

			Depending on the specific generator implementation, it may be
			necessary to add any static or dynamic libraries generated for
			child targets ($(D linkDependencies)).
		*/
		BuildSettings buildSettings;

		/** List of all dependencies.

			This list includes dependencies that are not the root of a binary
			target.
		*/
		string[] dependencies;

		/** List of all binary dependencies.

			This list includes all dependencies that are the root of a binary
			target.
		*/
		string[] linkDependencies;
	}

	private struct EnvironmentVariables
	{
		string[string] environments;
		string[string] buildEnvironments;
		string[string] runEnvironments;
		string[string] preGenerateEnvironments;
		string[string] postGenerateEnvironments;
		string[string] preBuildEnvironments;
		string[string] postBuildEnvironments;
		string[string] preRunEnvironments;
		string[string] postRunEnvironments;

		this(const scope ref BuildSettings bs)
		{
			update(bs);
		}

		void update(Envs)(const scope auto ref Envs envs)
		{
			import std.algorithm: each;
			envs.environments.byKeyValue.each!(pair => environments[pair.key] = pair.value);
			envs.buildEnvironments.byKeyValue.each!(pair => buildEnvironments[pair.key] = pair.value);
			envs.runEnvironments.byKeyValue.each!(pair => runEnvironments[pair.key] = pair.value);
			envs.preGenerateEnvironments.byKeyValue.each!(pair => preGenerateEnvironments[pair.key] = pair.value);
			envs.postGenerateEnvironments.byKeyValue.each!(pair => postGenerateEnvironments[pair.key] = pair.value);
			envs.preBuildEnvironments.byKeyValue.each!(pair => preBuildEnvironments[pair.key] = pair.value);
			envs.postBuildEnvironments.byKeyValue.each!(pair => postBuildEnvironments[pair.key] = pair.value);
			envs.preRunEnvironments.byKeyValue.each!(pair => preRunEnvironments[pair.key] = pair.value);
			envs.postRunEnvironments.byKeyValue.each!(pair => postRunEnvironments[pair.key] = pair.value);
		}

		void updateBuildSettings(ref BuildSettings bs)
		{
			bs.updateEnvironments(environments);
			bs.updateBuildEnvironments(buildEnvironments);
			bs.updateRunEnvironments(runEnvironments);
			bs.updatePreGenerateEnvironments(preGenerateEnvironments);
			bs.updatePostGenerateEnvironments(postGenerateEnvironments);
			bs.updatePreBuildEnvironments(preBuildEnvironments);
			bs.updatePostBuildEnvironments(postBuildEnvironments);
			bs.updatePreRunEnvironments(preRunEnvironments);
			bs.updatePostRunEnvironments(postRunEnvironments);
		}
	}

	protected {
		Project m_project;
		NativePath m_tempTargetExecutablePath;
	}

	this(Project project)
	{
		m_project = project;
	}

	/** Performs the full generator process.
	*/
	final void generate(GeneratorSettings settings)
	{
		import dub.compilers.utils : enforceBuildRequirements;

		if (!settings.config.length) settings.config = m_project.getDefaultConfiguration(settings.platform);

		string[string] configs = m_project.getPackageConfigs(settings.platform, settings.config);
		TargetInfo[string] targets;
		EnvironmentVariables[string] envs;

		foreach (pack; m_project.getTopologicalPackageList(true, null, configs)) {
			auto config = configs[pack.name];
			auto bs = pack.getBuildSettings(settings.platform, config);
			targets[pack.name] = TargetInfo(pack, [pack], config, bs);
			envs[pack.name] = EnvironmentVariables(bs);
		}
		foreach (pack; m_project.getTopologicalPackageList(false, null, configs)) {
			auto ti = pack.name in targets;
			auto parentEnvs = ti.pack.name in envs;
			foreach (deppkgName, depInfo; pack.getDependencies(ti.config)) {
				if (auto childEnvs = deppkgName in envs) {
					childEnvs.update(ti.buildSettings);
					parentEnvs.update(childEnvs);
				}
			}
		}
		BuildSettings makeBuildSettings(in Package pack, ref BuildSettings src)
		{
			BuildSettings bs;
			if (settings.buildSettings.options & BuildOption.lowmem) bs.options |= BuildOption.lowmem;
			BuildSettings srcbs = src.dup;
			envs[pack.name].updateBuildSettings(srcbs);
			bs.processVars(m_project, pack, srcbs, settings, true);
			return bs;
		}

		foreach (pack; m_project.getTopologicalPackageList(true, null, configs)) {
			BuildSettings bs = makeBuildSettings(pack, targets[pack.name].buildSettings);
			prepareGeneration(pack, m_project, settings, bs);

			// Regenerate buildSettings.sourceFiles
			if (bs.preGenerateCommands.length)
				bs = makeBuildSettings(pack, targets[pack.name].buildSettings);
			targets[pack.name].buildSettings = bs;
		}
		configurePackages(m_project.rootPackage, targets, settings);

		addBuildTypeSettings(targets, settings);
		foreach (ref t; targets.byValue) enforceBuildRequirements(t.buildSettings);

		generateTargets(settings, targets);

		foreach (pack; m_project.getTopologicalPackageList(true, null, configs)) {
			auto config = configs[pack.name];
			auto pkgbs  = pack.getBuildSettings(settings.platform, config);
			BuildSettings buildsettings = makeBuildSettings(pack, pkgbs);
			bool generate_binary = !(buildsettings.options & BuildOption.syntaxOnly);
			auto bs = &targets[m_project.rootPackage.name].buildSettings;
			auto targetPath = !m_tempTargetExecutablePath.empty ? m_tempTargetExecutablePath :
							  !bs.targetPath.empty ? NativePath(bs.targetPath) :
							  NativePath(buildsettings.targetPath);

			finalizeGeneration(pack, m_project, settings, buildsettings, targetPath, generate_binary);
		}

		performPostGenerateActions(settings, targets);
	}

	/** Overridden in derived classes to implement the actual generator functionality.

		The function should go through all targets recursively. The first target
		(which is guaranteed to be there) is
		$(D targets[m_project.rootPackage.name]). The recursive descent is then
		done using the $(D TargetInfo.linkDependencies) list.

		This method is also potentially responsible for running the pre and post
		build commands, while pre and post generate commands are already taken
		care of by the $(D generate) method.

		Params:
			settings = The generator settings used for this run
			targets = A map from package name to TargetInfo that contains all
				binary targets to be built.
	*/
	protected abstract void generateTargets(GeneratorSettings settings, in TargetInfo[string] targets);

	/** Overridable method to be invoked after the generator process has finished.

		An examples of functionality placed here is to run the application that
		has just been built.
	*/
	protected void performPostGenerateActions(GeneratorSettings settings, in TargetInfo[string] targets) {}

	/** Configure `rootPackage` and all of it's dependencies.

		1. Merge versions, debugVersions, and inheritable build
		settings from dependents to their dependencies.

		2. Define version identifiers Have_dependency_xyz for all
		direct dependencies of all packages.

		3. Merge versions, debugVersions, and inheritable build settings from
		dependencies to their dependents, so that importer and importee are ABI
		compatible. This also transports all Have_dependency_xyz version
		identifiers to `rootPackage`.

		4. Filter unused versions and debugVersions from all targets. The
		filters have previously been upwards inherited (3.) so that versions
		used in a dependency are also applied to all dependents.

		Note: The upwards inheritance is done at last so that siblings do not
		influence each other, also see https://github.com/dlang/dub/pull/1128.

		Note: Targets without output are integrated into their
		dependents and removed from `targets`.
	 */
	private void configurePackages(Package rootPackage, TargetInfo[string] targets, GeneratorSettings genSettings)
	{
		import std.algorithm : remove, sort;
		import std.range : repeat;

		auto roottarget = &targets[rootPackage.name];

		// 0. do shallow configuration (not including dependencies) of all packages
		TargetType determineTargetType(const ref TargetInfo ti)
		{
			TargetType tt = ti.buildSettings.targetType;
			if (ti.pack is rootPackage) {
				if (tt == TargetType.autodetect || tt == TargetType.library) tt = TargetType.staticLibrary;
			} else {
				if (tt == TargetType.autodetect || tt == TargetType.library) tt = genSettings.combined ? TargetType.sourceLibrary : TargetType.staticLibrary;
				else if (tt == TargetType.dynamicLibrary) {
					logWarn("Dynamic libraries are not yet supported as dependencies - building as static library.");
					tt = TargetType.staticLibrary;
				}
			}
			if (tt != TargetType.none && tt != TargetType.sourceLibrary && ti.buildSettings.sourceFiles.empty) {
				logWarn(`Configuration '%s' of package %s contains no source files. Please add {"targetType": "none"} to its package description to avoid building it.`,
						ti.config, ti.pack.name);
				tt = TargetType.none;
			}
			return tt;
		}

		string[] mainSourceFiles;
		bool[string] hasOutput;

		foreach (ref ti; targets.byValue)
		{
			auto bs = &ti.buildSettings;
			// determine the actual target type
			bs.targetType = determineTargetType(ti);

			switch (bs.targetType)
			{
			case TargetType.none:
				// ignore any build settings for targetType none (only dependencies will be processed)
				*bs = BuildSettings.init;
				bs.targetType = TargetType.none;
				break;

			case TargetType.executable:
				break;

			case TargetType.dynamicLibrary:
				// set -fPIC for dynamic library builds
				ti.buildSettings.addOptions(BuildOption.pic);
				goto default;

			default:
				// remove any mainSourceFile from non-executable builds
				if (bs.mainSourceFile.length) {
					bs.sourceFiles = bs.sourceFiles.remove!(f => f == bs.mainSourceFile);
					mainSourceFiles ~= bs.mainSourceFile;
				}
				break;
			}
			bool generatesBinary = bs.targetType != TargetType.sourceLibrary && bs.targetType != TargetType.none;
			hasOutput[ti.pack.name] = generatesBinary || ti.pack is rootPackage;
		}

		// add main source files to root executable
		{
			auto bs = &roottarget.buildSettings;
			if (bs.targetType == TargetType.executable || genSettings.single) bs.addSourceFiles(mainSourceFiles);
		}

		if (genSettings.filterVersions)
			foreach (ref ti; targets.byValue)
				inferVersionFilters(ti);

		// mark packages as visited (only used during upwards propagation)
		void[0][Package] visited;

		// collect all dependencies
		void collectDependencies(Package pack, ref TargetInfo ti, TargetInfo[string] targets, size_t level = 0)
		{
			// use `visited` here as pkgs cannot depend on themselves
			if (pack in visited)
				return;
			// transitive dependencies must be visited multiple times, see #1350
			immutable transitive = !hasOutput[pack.name];
			if (!transitive)
				visited[pack] = typeof(visited[pack]).init;

			auto bs = &ti.buildSettings;
			if (hasOutput[pack.name])
				logDebug("%sConfiguring target %s (%s %s %s)", ' '.repeat(2 * level), pack.name, bs.targetType, bs.targetPath, bs.targetName);
			else
				logDebug("%sConfiguring target without output %s", ' '.repeat(2 * level), pack.name);

			// get specified dependencies, e.g. vibe-d ~0.8.1
			auto deps = pack.getDependencies(targets[pack.name].config);
			logDebug("Dependency is %s -> %(%s, %)", pack.name, deps.byKey);
			foreach (depname; deps.keys.sort())
			{
				auto depspec = deps[depname];
				// get selected package for that dependency, e.g. vibe-d 0.8.2-beta.2
				auto deppack = m_project.getDependency(depname, depspec.optional);
				if (deppack is null) continue; // optional and not selected

				// if dependency has no output
				if (!hasOutput[depname]) {
					// add itself
					ti.packages ~= deppack;
					// and it's transitive dependencies to current target
					collectDependencies(deppack, ti, targets, level + 1);
					continue;
				}
				auto depti = &targets[depname];
				const depbs = &depti.buildSettings;
				if (depbs.targetType == TargetType.executable && ti.buildSettings.targetType != TargetType.none)
					continue;

				// add to (link) dependencies
				ti.dependencies ~= depname;
				ti.linkDependencies ~= depname;

				// recurse
				collectDependencies(deppack, *depti, targets, level + 1);

				// also recursively add all link dependencies of static libraries
				// preserve topological sorting of dependencies for correct link order
				if (depbs.targetType == TargetType.staticLibrary)
					ti.linkDependencies = ti.linkDependencies.filter!(d => !depti.linkDependencies.canFind(d)).array ~ depti.linkDependencies;
			}

			enforce(!(ti.buildSettings.targetType == TargetType.none && ti.dependencies.empty),
				"Package with target type \"none\" must have dependencies to build.");
		}

		collectDependencies(rootPackage, *roottarget, targets);
		visited.clear();

		// 1. downwards inherits versions, debugVersions, and inheritable build settings
		static void configureDependencies(const scope ref TargetInfo ti, TargetInfo[string] targets,
											BuildSettings[string] dependBS, size_t level = 0)
		{

			static void applyForcedSettings(const scope ref BuildSettings forced, ref BuildSettings child) {
				child.addDFlags(forced.dflags);
			}

			// do not use `visited` here as dependencies must inherit
			// configurations from *all* of their parents
			logDebug("%sConfigure dependencies of %s, deps:%(%s, %)", ' '.repeat(2 * level), ti.pack.name, ti.dependencies);
			foreach (depname; ti.dependencies)
			{
				BuildSettings forcedSettings;
				auto pti = &targets[depname];
				mergeFromDependent(ti.buildSettings, pti.buildSettings);

				if (auto matchedSettings = depname in dependBS)
					forcedSettings = *matchedSettings;
				else if (auto matchedSettings = "*" in dependBS)
					forcedSettings = *matchedSettings;

				applyForcedSettings(forcedSettings, pti.buildSettings);
				configureDependencies(*pti, targets, ["*" : forcedSettings], level + 1);
			}
		}

		BuildSettings[string] dependencyBuildSettings;
		foreach (key, value; rootPackage.recipe.buildSettings.dependencyBuildSettings)
		{
			BuildSettings buildSettings;
			if (auto target = key in targets)
			{
				value.getPlatformSettings(buildSettings, genSettings.platform, target.pack.path);
				buildSettings.processVars(m_project, target.pack, buildSettings, genSettings, true);
				dependencyBuildSettings[key] = buildSettings;
			}
		}
		configureDependencies(*roottarget, targets, dependencyBuildSettings);

		// 2. add Have_dependency_xyz for all direct dependencies of a target
		// (includes incorporated non-target dependencies and their dependencies)
		foreach (ref ti; targets.byValue)
		{
			import std.range : chain;
			import dub.internal.utils : stripDlangSpecialChars;

			auto bs = &ti.buildSettings;
			auto pkgnames = ti.packages.map!(p => p.name).chain(ti.dependencies);
			bs.addVersions(pkgnames.map!(pn => "Have_" ~ stripDlangSpecialChars(pn)).array);
		}

		// 3. upwards inherit full build configurations (import paths, versions, debugVersions, versionFilters, importPaths, ...)
		void configureDependents(ref TargetInfo ti, TargetInfo[string] targets, size_t level = 0)
		{
			// use `visited` here as pkgs cannot depend on themselves
			if (ti.pack in visited)
				return;
			visited[ti.pack] = typeof(visited[ti.pack]).init;

			logDiagnostic("%sConfiguring dependent %s, deps:%(%s, %)", ' '.repeat(2 * level), ti.pack.name, ti.dependencies);
			// embedded non-binary dependencies
			foreach (deppack; ti.packages[1 .. $])
				ti.buildSettings.add(targets[deppack.name].buildSettings);
			// binary dependencies
			foreach (depname; ti.dependencies)
			{
				auto pdepti = &targets[depname];
				configureDependents(*pdepti, targets, level + 1);
				mergeFromDependency(pdepti.buildSettings, ti.buildSettings, genSettings.platform);
			}
		}

		configureDependents(*roottarget, targets);
		visited.clear();

		// 4. Filter applicable version and debug version identifiers
		if (genSettings.filterVersions)
		{
			foreach (name, ref ti; targets)
			{
				import std.algorithm.sorting : partition;

				auto bs = &ti.buildSettings;

				auto filtered = bs.versions.partition!(v => bs.versionFilters.canFind(v));
				logDebug("Filtering out unused versions for %s: %s", name, filtered);
				bs.versions = bs.versions[0 .. $ - filtered.length];

				filtered = bs.debugVersions.partition!(v => bs.debugVersionFilters.canFind(v));
				logDebug("Filtering out unused debug versions for %s: %s", name, filtered);
				bs.debugVersions = bs.debugVersions[0 .. $ - filtered.length];
			}
		}

		// 5. override string import files in dependencies
		static void overrideStringImports(ref TargetInfo target,
			ref TargetInfo parent, TargetInfo[string] targets, string[] overrides)
		{
			// Since string import paths are inherited from dependencies in the
			// inheritance step above (step 3), it is guaranteed that all
			// following dependencies will not have string import paths either,
			// so we can skip the recursion here
			if (!target.buildSettings.stringImportPaths.length)
				return;

			// do not use visited here as string imports can be overridden by *any* parent
			//
			// special support for overriding string imports in parent packages
			// this is a candidate for deprecation, once an alternative approach
			// has been found
			bool any_override = false;

			// override string import files (used for up to date checking)
			foreach (ref f; target.buildSettings.stringImportFiles)
			{
				foreach (o; overrides)
				{
					NativePath op;
					if (f != o && NativePath(f).head == (op = NativePath(o)).head) {
						logDebug("String import %s overridden by %s", f, o);
						f = o;
						any_override = true;
					}
				}
			}

			// override string import paths by prepending to the list, in
			// case there is any overlapping file
			if (any_override)
				target.buildSettings.prependStringImportPaths(parent.buildSettings.stringImportPaths);

			// add all files to overrides for recursion
			overrides ~= target.buildSettings.stringImportFiles;

			// recursively override all dependencies with the accumulated files/paths
			foreach (depname; target.dependencies)
				overrideStringImports(targets[depname], target, targets, overrides);
		}

		// push string import paths/files down to all direct and indirect
		// dependencies, overriding their own
		foreach (depname; roottarget.dependencies)
			overrideStringImports(targets[depname], *roottarget, targets,
				roottarget.buildSettings.stringImportFiles);

		// remove targets without output
		foreach (name; targets.keys)
		{
			if (!hasOutput[name])
				targets.remove(name);
		}
	}

	// infer applicable version identifiers
	private static void inferVersionFilters(ref TargetInfo ti)
	{
		import std.algorithm.searching : any;
		import std.file : timeLastModified;
		import std.path : extension;
		import std.range : chain;
		import std.regex : ctRegex, matchAll;
		import std.stdio : File;
		import std.datetime : Clock, SysTime, UTC;
		import dub.compilers.utils : isLinkerFile;
		import dub.internal.vibecompat.data.json : Json, JSONException;

		auto bs = &ti.buildSettings;

		// only infer if neither version filters are specified explicitly
		if (bs.versionFilters.length || bs.debugVersionFilters.length)
		{
			logDebug("Using specified versionFilters for %s: %s %s", ti.pack.name,
				bs.versionFilters, bs.debugVersionFilters);
			return;
		}

		// check all existing source files for version identifiers
		static immutable dexts = [".d", ".di"];
		auto srcs = chain(bs.sourceFiles, bs.importFiles, bs.stringImportFiles)
			.filter!(f => dexts.canFind(f.extension)).filter!exists;
		// try to load cached filters first
		auto cache = ti.pack.metadataCache;
		try
		{
			auto cachedFilters = cache["versionFilters"];
			if (cachedFilters.type != Json.Type.undefined)
				cachedFilters = cachedFilters[ti.config];
			if (cachedFilters.type != Json.Type.undefined)
			{
				immutable mtime = SysTime.fromISOExtString(cachedFilters["mtime"].get!string);
				if (!srcs.any!(src => src.timeLastModified > mtime))
				{
					auto versionFilters = cachedFilters["versions"][].map!(j => j.get!string).array;
					auto debugVersionFilters = cachedFilters["debugVersions"][].map!(j => j.get!string).array;
					logDebug("Using cached versionFilters for %s: %s %s", ti.pack.name,
						versionFilters, debugVersionFilters);
					bs.addVersionFilters(versionFilters);
					bs.addDebugVersionFilters(debugVersionFilters);
					return;
				}
			}
		}
		catch (JSONException e)
		{
			logWarn("Exception during loading invalid package cache %s.\n%s",
				ti.pack.path ~ ".dub/metadata_cache.json", e);
		}

		// use ctRegex for performance reasons, only small compile time increase
		enum verRE = ctRegex!`(?:^|\s)version\s*\(\s*([^\s]*?)\s*\)`;
		enum debVerRE = ctRegex!`(?:^|\s)debug\s*\(\s*([^\s]*?)\s*\)`;

		auto versionFilters = appender!(string[]);
		auto debugVersionFilters = appender!(string[]);

		foreach (file; srcs)
		{
			foreach (line; File(file).byLine)
			{
				foreach (m; line.matchAll(verRE))
					if (!versionFilters.data.canFind(m[1]))
						versionFilters.put(m[1].idup);
				foreach (m; line.matchAll(debVerRE))
					if (!debugVersionFilters.data.canFind(m[1]))
						debugVersionFilters.put(m[1].idup);
			}
		}
		logDebug("Using inferred versionFilters for %s: %s %s", ti.pack.name,
			versionFilters.data, debugVersionFilters.data);
		bs.addVersionFilters(versionFilters.data);
		bs.addDebugVersionFilters(debugVersionFilters.data);

		auto cachedFilters = cache["versionFilters"];
		if (cachedFilters.type == Json.Type.undefined)
			cachedFilters = cache["versionFilters"] = [ti.config: Json.emptyObject];
		cachedFilters[ti.config] = [
			"mtime": Json(Clock.currTime(UTC()).toISOExtString),
			"versions": Json(versionFilters.data.map!Json.array),
			"debugVersions": Json(debugVersionFilters.data.map!Json.array),
		];
		ti.pack.metadataCache = cache;
	}

	private static void mergeFromDependent(const scope ref BuildSettings parent, ref BuildSettings child)
	{
		child.addVersions(parent.versions);
		child.addDebugVersions(parent.debugVersions);
		child.addOptions(BuildOptions(parent.options & inheritedBuildOptions));
	}

	private static void mergeFromDependency(const scope ref BuildSettings child, ref BuildSettings parent, const scope ref BuildPlatform platform)
	{
		import dub.compilers.utils : isLinkerFile;

		parent.addDFlags(child.dflags);
		parent.addVersions(child.versions);
		parent.addDebugVersions(child.debugVersions);
		parent.addVersionFilters(child.versionFilters);
		parent.addDebugVersionFilters(child.debugVersionFilters);
		parent.addImportPaths(child.importPaths);
		parent.addStringImportPaths(child.stringImportPaths);
		// linking of static libraries is done by parent
		if (child.targetType == TargetType.staticLibrary) {
			parent.addSourceFiles(child.sourceFiles.filter!(f => isLinkerFile(platform, f)).array);
			parent.addLibs(child.libs);
			parent.addLFlags(child.lflags);
		}
	}

	// configure targets for build types such as release, or unittest-cov
	private void addBuildTypeSettings(TargetInfo[string] targets, in GeneratorSettings settings)
	{
		foreach (ref ti; targets.byValue) {
			ti.buildSettings.add(settings.buildSettings);

			// add build type settings and convert plain DFLAGS to build options
			m_project.addBuildTypeSettings(ti.buildSettings, settings, ti.pack is m_project.rootPackage);
			settings.compiler.extractBuildOptions(ti.buildSettings);

			auto tt = ti.buildSettings.targetType;
			enforce (tt != TargetType.sourceLibrary || ti.pack !is m_project.rootPackage || (ti.buildSettings.options & BuildOption.syntaxOnly),
				format("Main package must not have target type \"%s\". Cannot build.", tt));
		}
	}
}


struct GeneratorSettings {
	BuildPlatform platform;
	Compiler compiler;
	string config;
	string buildType;
	BuildSettings buildSettings;
	BuildMode buildMode = BuildMode.separate;
	int targetExitStatus;

	bool combined; // compile all in one go instead of each dependency separately
	bool filterVersions;

	// only used for generator "build"
	bool run, force, direct, rdmd, tempBuild, parallelBuild;

	/// single file dub package
	bool single;

	string[] runArgs;
	void delegate(int status, string output) compileCallback;
	void delegate(int status, string output) linkCallback;
	void delegate(int status, string output) runCallback;
}


/**
	Determines the mode in which the compiler and linker are invoked.
*/
enum BuildMode {
	separate,                 /// Compile and link separately
	allAtOnce,                /// Perform compile and link with a single compiler invocation
	singleFile,               /// Compile each file separately
	//multipleObjects,          /// Generate an object file per module
	//multipleObjectsPerModule, /// Use the -multiobj switch to generate multiple object files per module
	//compileOnly               /// Do not invoke the linker (can be done using a post build command)
}


/**
	Creates a project generator of the given type for the specified project.
*/
ProjectGenerator createProjectGenerator(string generator_type, Project project)
{
	assert(project !is null, "Project instance needed to create a generator.");

	generator_type = generator_type.toLower();
	switch(generator_type) {
		default:
			throw new Exception("Unknown project generator: "~generator_type);
		case "build":
			logDebug("Creating build generator.");
			return new BuildGenerator(project);
		case "mono-d":
			throw new Exception("The Mono-D generator has been removed. Use Mono-D's built in DUB support instead.");
		case "visuald":
			logDebug("Creating VisualD generator.");
			return new VisualDGenerator(project);
		case "sublimetext":
			logDebug("Creating SublimeText generator.");
			return new SublimeTextGenerator(project);
		case "cmake":
			logDebug("Creating CMake generator.");
			return new CMakeGenerator(project);
	}
}


/**
	Calls delegates on files and directories in the given path that match any globs.
*/
void findFilesMatchingGlobs(in NativePath path, in string[] globList, void delegate(string file) addFile, void delegate(string dir) addDir)
{
	import std.path : globMatch;

	string[] globs;
	foreach (f; globList)
	{
		if (f.canFind("*", "?") ||
			(f.canFind("{") && f.balancedParens('{', '}')) ||
			(f.canFind("[") && f.balancedParens('[', ']')))
		{
			globs ~= f;
		}
		else
		{
			if (f.isDir)
				addDir(f);
			else
				addFile(f);
		}
	}
	if (globs.length) // Search all files for glob matches
		foreach (f; dirEntries(path.toNativeString(), SpanMode.breadth))
			foreach (glob; globs)
				if (f.name().globMatch(glob))
				{
					if (f.isDir)
						addDir(f);
					else
						addFile(f);
					break;
				}
}


/**
	Calls delegates on files in the given path that match any globs.

	If a directory matches a glob, the delegate is called on all existing files inside it recursively
	in depth-first pre-order.
*/
void findFilesMatchingGlobs(in NativePath path, in string[] globList, void delegate(string file) addFile)
{
	void addDir(string dir)
	{
		foreach (f; dirEntries(dir, SpanMode.breadth))
			addFile(f);
	}

	findFilesMatchingGlobs(path, globList, addFile, &addDir);
}


/**
	Runs pre-build commands and performs other required setup before project files are generated.
*/
private void prepareGeneration(in Package pack, in Project proj, in GeneratorSettings settings,
	in BuildSettings buildsettings)
{
	if (buildsettings.preGenerateCommands.length && !isRecursiveInvocation(pack.name)) {
		logInfo("Running pre-generate commands for %s...", pack.name);
		runBuildCommands(buildsettings.preGenerateCommands, pack, proj, settings, buildsettings,
			[buildsettings.environments, buildsettings.buildEnvironments, buildsettings.preGenerateEnvironments]);
	}
}

/**
	Runs post-build commands and copies required files to the binary directory.
*/
private void finalizeGeneration(in Package pack, in Project proj, in GeneratorSettings settings,
	in BuildSettings buildsettings, NativePath target_path, bool generate_binary)
{
	if (buildsettings.postGenerateCommands.length && !isRecursiveInvocation(pack.name)) {
		logInfo("Running post-generate commands for %s...", pack.name);
		runBuildCommands(buildsettings.postGenerateCommands, pack, proj, settings, buildsettings,
			[buildsettings.environments, buildsettings.buildEnvironments, buildsettings.postGenerateEnvironments]);
	}

	if (generate_binary) {
		if (!exists(buildsettings.targetPath))
			mkdirRecurse(buildsettings.targetPath);

		if (buildsettings.copyFiles.length) {
			void copyFolderRec(NativePath folder, NativePath dstfolder)
			{
				mkdirRecurse(dstfolder.toNativeString());
				foreach (de; iterateDirectory(folder.toNativeString())) {
					if (de.isDirectory) {
						copyFolderRec(folder ~ de.name, dstfolder ~ de.name);
					} else {
						try hardLinkFile(folder ~ de.name, dstfolder ~ de.name, true);
						catch (Exception e) {
							logWarn("Failed to copy file %s: %s", (folder ~ de.name).toNativeString(), e.msg);
						}
					}
				}
			}

			void tryCopyDir(string file)
			{
				auto src = NativePath(file);
				if (!src.absolute) src = pack.path ~ src;
				auto dst = target_path ~ NativePath(file).head;
				if (src == dst) {
					logDiagnostic("Skipping copy of %s (same source and destination)", file);
					return;
				}
				logDiagnostic("  %s to %s", src.toNativeString(), dst.toNativeString());
				try {
					copyFolderRec(src, dst);
				} catch(Exception e) logWarn("Failed to copy %s to %s: %s", src.toNativeString(), dst.toNativeString(), e.msg);
			}

			void tryCopyFile(string file)
			{
				auto src = NativePath(file);
				if (!src.absolute) src = pack.path ~ src;
				auto dst = target_path ~ NativePath(file).head;
				if (src == dst) {
					logDiagnostic("Skipping copy of %s (same source and destination)", file);
					return;
				}
				logDiagnostic("  %s to %s", src.toNativeString(), dst.toNativeString());
				try {
					hardLinkFile(src, dst, true);
				} catch(Exception e) logWarn("Failed to copy %s to %s: %s", src.toNativeString(), dst.toNativeString(), e.msg);
			}
			logInfo("Copying files for %s...", pack.name);
			findFilesMatchingGlobs(pack.path, buildsettings.copyFiles, &tryCopyFile, &tryCopyDir);
		}

	}
}


/** Runs a list of build commands for a particular package.

	This function sets all DUB speficic environment variables and makes sure
	that recursive dub invocations are detected and don't result in infinite
	command execution loops. The latter could otherwise happen when a command
	runs "dub describe" or similar functionality.
*/
void runBuildCommands(in string[] commands, in Package pack, in Project proj,
	in GeneratorSettings settings, in BuildSettings build_settings, in string[string][] extraVars = null)
{
	import dub.internal.utils : getDUBExePath, runCommands;
	import std.conv : to, text;
	import std.process : environment, escapeShellFileName;

	string[string] env = environment.toAA();
	// TODO: do more elaborate things here
	// TODO: escape/quote individual items appropriately
	env["VERSIONS"]              = join(cast(string[])build_settings.versions," ");
	env["LIBS"]                  = join(cast(string[])build_settings.libs," ");
	env["SOURCE_FILES"]          = join(cast(string[])build_settings.sourceFiles," ");
	env["IMPORT_PATHS"]          = join(cast(string[])build_settings.importPaths," ");
	env["STRING_IMPORT_PATHS"]   = join(cast(string[])build_settings.stringImportPaths," ");

	env["DC"]                    = settings.platform.compilerBinary;
	env["DC_BASE"]               = settings.platform.compiler;
	env["D_FRONTEND_VER"]        = to!string(settings.platform.frontendVersion);

	env["DUB_EXE"]               = getDUBExePath(settings.platform.compilerBinary);
	env["DUB_PLATFORM"]          = join(cast(string[])settings.platform.platform," ");
	env["DUB_ARCH"]              = join(cast(string[])settings.platform.architecture," ");

	env["DUB_TARGET_TYPE"]       = to!string(build_settings.targetType);
	env["DUB_TARGET_PATH"]       = build_settings.targetPath;
	env["DUB_TARGET_NAME"]       = build_settings.targetName;
	env["DUB_TARGET_EXIT_STATUS"] = settings.targetExitStatus.text;
	env["DUB_WORKING_DIRECTORY"] = build_settings.workingDirectory;
	env["DUB_MAIN_SOURCE_FILE"]  = build_settings.mainSourceFile;

	env["DUB_CONFIG"]            = settings.config;
	env["DUB_BUILD_TYPE"]        = settings.buildType;
	env["DUB_BUILD_MODE"]        = to!string(settings.buildMode);
	env["DUB_PACKAGE"]           = pack.name;
	env["DUB_PACKAGE_DIR"]       = pack.path.toNativeString();
	env["DUB_ROOT_PACKAGE"]      = proj.rootPackage.name;
	env["DUB_ROOT_PACKAGE_DIR"]  = proj.rootPackage.path.toNativeString();
	env["DUB_PACKAGE_VERSION"]   = pack.version_.toString();

	env["DUB_COMBINED"]          = settings.combined?      "TRUE" : "";
	env["DUB_RUN"]               = settings.run?           "TRUE" : "";
	env["DUB_FORCE"]             = settings.force?         "TRUE" : "";
	env["DUB_DIRECT"]            = settings.direct?        "TRUE" : "";
	env["DUB_RDMD"]              = settings.rdmd?          "TRUE" : "";
	env["DUB_TEMP_BUILD"]        = settings.tempBuild?     "TRUE" : "";
	env["DUB_PARALLEL_BUILD"]    = settings.parallelBuild? "TRUE" : "";

	env["DUB_RUN_ARGS"] = (cast(string[])settings.runArgs).map!(escapeShellFileName).join(" ");

	auto cfgs = proj.getPackageConfigs(settings.platform, settings.config, true);
	auto rootPackageBuildSettings = proj.rootPackage.getBuildSettings(settings.platform, cfgs[proj.rootPackage.name]);
	env["DUB_ROOT_PACKAGE_TARGET_TYPE"] = to!string(rootPackageBuildSettings.targetType);
	env["DUB_ROOT_PACKAGE_TARGET_PATH"] = rootPackageBuildSettings.targetPath;
	env["DUB_ROOT_PACKAGE_TARGET_NAME"] = rootPackageBuildSettings.targetName;

	foreach (aa; extraVars) {
		foreach (k, v; aa)
			env[k] = v;
	}

	auto depNames = proj.dependencies.map!((a) => a.name).array();
	storeRecursiveInvokations(env, proj.rootPackage.name ~ depNames);
	runCommands(commands, env, pack.path().toString());
}

private bool isRecursiveInvocation(string pack)
{
	import std.algorithm : canFind, splitter;
	import std.process : environment;

	return environment
        .get("DUB_PACKAGES_USED", "")
        .splitter(",")
        .canFind(pack);
}

private void storeRecursiveInvokations(string[string] env, string[] packs)
{
	import std.algorithm : canFind, splitter;
	import std.range : chain;
	import std.process : environment;

    env["DUB_PACKAGES_USED"] = environment
        .get("DUB_PACKAGES_USED", "")
        .splitter(",")
        .chain(packs)
        .join(",");
}
