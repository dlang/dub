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
import std.array : array;
import std.array;
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

	protected {
		Project m_project;
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

		foreach (pack; m_project.getTopologicalPackageList(true, null, configs)) {
			BuildSettings buildSettings;
			auto config = configs[pack.name];
			buildSettings.processVars(m_project, pack, pack.getBuildSettings(settings.platform, config), true);
			targets[pack.name] = TargetInfo(pack, [pack], config, buildSettings);

			prepareGeneration(pack, m_project, settings, buildSettings);
		}

		string[] mainfiles = configurePackages(m_project.rootPackage, targets, settings);

		addBuildTypeSettings(targets, settings);
		foreach (ref t; targets.byValue) enforceBuildRequirements(t.buildSettings);
		auto bs = &targets[m_project.rootPackage.name].buildSettings;
		if (bs.targetType == TargetType.executable) bs.addSourceFiles(mainfiles);

		generateTargets(settings, targets);

		foreach (pack; m_project.getTopologicalPackageList(true, null, configs)) {
			BuildSettings buildsettings;
			buildsettings.processVars(m_project, pack, pack.getBuildSettings(settings.platform, configs[pack.name]), true);
			bool generate_binary = !(buildsettings.options & BuildOption.syntaxOnly);
			finalizeGeneration(pack, m_project, settings, buildsettings, NativePath(bs.targetPath), generate_binary);
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

	/**
	   Configure package before determining dependencies.

	   Returns:
	       whether the target of `config` for `pack` has any output (e.g. static lib, exe)
	*/
	private bool shallowConfig(in Package pack, string config, bool genCombined, ref BuildSettings bs)
	{
		TargetType tt = bs.targetType;
		if (pack is m_project.rootPackage) {
			if (tt == TargetType.autodetect || tt == TargetType.library) tt = TargetType.staticLibrary;
		} else {
			if (tt == TargetType.autodetect || tt == TargetType.library) tt = genCombined ? TargetType.sourceLibrary : TargetType.staticLibrary;
			else if (tt == TargetType.dynamicLibrary) {
				logWarn("Dynamic libraries are not yet supported as dependencies - building as static library.");
				tt = TargetType.staticLibrary;
			}
		}
		if (tt != TargetType.none && tt != TargetType.sourceLibrary && bs.sourceFiles.empty) {
			logWarn(`Configuration '%s' of package %s contains no source files. Please add {"targetType": "none"} to its package description to avoid building it.`,
					config, pack.name);
			tt = TargetType.none;
		}

		switch (bs.targetType = tt)
		{
		case TargetType.none:
			// ignore any build settings for targetType none (only dependencies will be processed)
			bs = BuildSettings.init;
			bs.targetType = TargetType.none;
			break;

		case TargetType.dynamicLibrary:
			// set -fPIC for dynamic library builds
			bs.addOptions(BuildOption.pic);
			break;

		default:
			break;
		}
		bool generatesBinary = bs.targetType != TargetType.sourceLibrary && bs.targetType != TargetType.none;
		return generatesBinary || pack is m_project.rootPackage;
	}

	/** Recursively Collect dependencies for all targets.
	 */
	void collectDependencies(Package pack, ref TargetInfo ti, TargetInfo[string] targets, in bool[string] hasOutput, void[0][Package] visited = null, size_t level = 0)
	{
		import std.algorithm : sort;
		import std.range : repeat;

		// use `visited` here as pkgs cannot depend on themselves
		if (pack in visited)
			return;
		// transitive dependencies must be visited multiple times, see #1350
		immutable transitive = !hasOutput[pack.name];
		if (!transitive)
			visited[pack] = typeof(visited[pack]).init;

		auto bs = &ti.buildSettings;
		logDebug("%sConfiguring target %s (%s %s %s)", ' '.repeat(2 * level), pack.name, bs.targetType, bs.targetPath, bs.targetName);

		// get specified dependencies, e.g. vibe-d ~0.8.1
		auto deps = pack.getDependencies(targets[pack.name].config);
		logDebug("deps: %s -> %(%s, %)", pack.name, deps.byKey);
		foreach (depname; deps.keys.sort())
		{
			auto depspec = deps[depname];
			// get selected package for that dependency, e.g. vibe-d 0.8.2-beta.2
			auto deppack = m_project.getDependency(depname, depspec.optional);
			if (deppack is null) continue; // optional and not selected

			// if dependency has no target output
			if (!hasOutput[depname]) {
				// add itself
				ti.packages ~= deppack;
				// and it's transitive dependencies to current target
				collectDependencies(deppack, ti, targets, hasOutput, visited, level + 1);
				continue;
			}
			auto depti = depname in targets;
			const depbs = &depti.buildSettings;
			if (depbs.targetType == TargetType.executable)
				continue;
			// add to (link) dependencies
			ti.dependencies ~= depname;
			ti.linkDependencies ~= depname;

			// recurse
			collectDependencies(deppack, *depti, targets, hasOutput, visited, level + 1);

			// also recursively add all link dependencies of static libraries
			// preserve topological sorting of dependencies for correct link order
			if (depbs.targetType == TargetType.staticLibrary)
				ti.linkDependencies = ti.linkDependencies.filter!(d => !depti.linkDependencies.canFind(d)).array ~ depti.linkDependencies;
		}
	}

	/** Configure dependencies.

		1. downwards inherits versions, debugVersions, and inheritable build settings
	*/
	static void configureDependencies(in ref TargetInfo ti, TargetInfo[string] targets, size_t level = 0)
	{
		import std.range : repeat;

		// do not use `visited` here as dependencies must inherit
		// configurations from *all* of their parents
		logDebug("%sConfigure dependencies of %s, deps:%(%s, %)", ' '.repeat(2 * level), ti.pack.name, ti.dependencies);
		foreach (depname; ti.dependencies)
		{
			auto pti = &targets[depname];
			mergeFromDependent(ti.buildSettings, pti.buildSettings);
			configureDependencies(*pti, targets, level + 1);
		}
	}

	/** Define Have_dependency_xyz version identifiers.

		2. add Have_dependency_xyz for all direct dependencies of a target
	    (includes incorporated non-target dependencies and their dependencies)
	*/
	static void defineHaveDependencies(TargetInfo[string] targets)
	{
		foreach (ref ti; targets.byValue)
		{
			import std.range : chain;
			import dub.internal.utils : stripDlangSpecialChars;

			auto bs = &ti.buildSettings;
			auto pkgnames = ti.packages.map!(p => p.name).chain(ti.dependencies);
			bs.addVersions(pkgnames.map!(pn => "Have_" ~ stripDlangSpecialChars(pn)).array);
		}
	}

	/** Configure dependents.

		3. upwards inherit full build configurations (import paths, versions, debugVersions, ...)
	*/
	static void configureDependents(ref TargetInfo ti, TargetInfo[string] targets, void[0][Package] visited = null, size_t level = 0)
	{
		import std.range : repeat;

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
			configureDependents(*pdepti, targets, visited, level + 1);
			mergeFromDependency(pdepti.buildSettings, ti.buildSettings);
		}
	}

	/** Override string imports.

		4. override string import files in dependencies
	*/
	static void overrideStringImports(ref TargetInfo ti, TargetInfo[string] targets, string[] overrides)
	{
		// do not use visited here as string imports can be overridden by *any* parent
		//
		// special support for overriding string imports in parent packages
		// this is a candidate for deprecation, once an alternative approach
		// has been found
		if (ti.buildSettings.stringImportPaths.length) {
			// override string import files (used for up to date checking)
			foreach (ref f; ti.buildSettings.stringImportFiles)
			{
				foreach (o; overrides)
				{
					NativePath op;
					if (f != o && NativePath(f).head == (op = NativePath(o)).head) {
						logDebug("string import %s overridden by %s", f, o);
						f = o;
						ti.buildSettings.prependStringImportPaths(op.parentPath.toNativeString);
					}
				}
			}
		}
		// add to overrides for recursion
		overrides ~= ti.buildSettings.stringImportFiles;
		// override dependencies
		foreach (depname; ti.dependencies)
			overrideStringImports(targets[depname], targets, overrides);
	}

	/** Configure `rootPackage` and all of it's dependencies.

		1. Merge versions, debugVersions, and inheritable build
		settings from dependents to their dependencies.

		2. Define version identifiers Have_dependency_xyz for all
		direct dependencies of all packages.

		3. Merge versions, debugVersions, and inheritable build settings from
		dependencies to their dependents, so that importer and importee are ABI
		compatible. This also transports all Have_dependency_xyz version
		identifiers to `rootPackage`.

		Note: The upwards inheritance is done at last so that siblings do not
		influence each other, also see https://github.com/dlang/dub/pull/1128.

		Note: Targets without output are integrated into their
		dependents and removed from `targets`.
	 */
	private string[] configurePackages(Package rootPackage, TargetInfo[string] targets, GeneratorSettings genSettings)
	{
		import std.algorithm : remove;
		import std.range : repeat;

		bool[string] hasOutput;
		foreach (name, ref ti; targets)
		{
			hasOutput[name] = shallowConfig(ti.pack, ti.config, genSettings.combined, ti.buildSettings);
		}

		collectDependencies(rootPackage, targets[rootPackage.name], targets, hasOutput);
		configureDependencies(targets[rootPackage.name], targets);
		defineHaveDependencies(targets);
		configureDependents(targets[rootPackage.name], targets);
		overrideStringImports(targets[rootPackage.name], targets, null);

		// remove any mainSourceFile from non-executable builds
		string[] mainSourceFiles;
		foreach (ref ti; targets.byValue)
		{
			auto bs = &ti.buildSettings;
			if (bs.targetType != TargetType.executable && bs.mainSourceFile.length) {
				bs.sourceFiles = bs.sourceFiles.remove!(f => f == bs.mainSourceFile);
				mainSourceFiles ~= bs.mainSourceFile;
			}
		}

		// remove targets without output
		foreach (name; targets.keys)
		{
			if (!hasOutput[name])
				targets.remove(name);
		}

		return mainSourceFiles;
	}

	private static void mergeFromDependent(in ref BuildSettings parent, ref BuildSettings child)
	{
		child.addVersions(parent.versions);
		child.addDebugVersions(parent.debugVersions);
		child.addOptions(BuildOptions(cast(BuildOptions)parent.options & inheritedBuildOptions));
	}

	private static void mergeFromDependency(in ref BuildSettings child, ref BuildSettings parent)
	{
		import dub.compilers.utils : isLinkerFile;

		parent.addDFlags(child.dflags);
		parent.addVersions(child.versions);
		parent.addDebugVersions(child.debugVersions);
		parent.addImportPaths(child.importPaths);
		parent.addStringImportPaths(child.stringImportPaths);
		// linking of static libraries is done by parent
		if (child.targetType == TargetType.staticLibrary) {
			parent.addLinkerFiles(child.sourceFiles.filter!isLinkerFile.array);
			parent.addLibs(child.libs);
			parent.addLFlags(child.lflags);
		}
	}

	// configure targets for build types such as release, or unittest-cov
	private void addBuildTypeSettings(TargetInfo[string] targets, GeneratorSettings settings)
	{
		foreach (ref ti; targets.byValue) {
			ti.buildSettings.add(settings.buildSettings);

			// add build type settings and convert plain DFLAGS to build options
			m_project.addBuildTypeSettings(ti.buildSettings, settings.platform, settings.buildType, ti.pack is m_project.rootPackage);
			settings.compiler.extractBuildOptions(ti.buildSettings);

			auto tt = ti.buildSettings.targetType;
			bool generatesBinary = tt != TargetType.sourceLibrary && tt != TargetType.none;
			enforce (generatesBinary || ti.pack !is m_project.rootPackage || (ti.buildSettings.options & BuildOption.syntaxOnly),
				format("Main package must have a binary target type, not %s. Cannot build.", tt));
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

	bool combined; // compile all in one go instead of each dependency separately

	// only used for generator "build"
	bool run, force, direct, rdmd, tempBuild, parallelBuild;
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
	Runs pre-build commands and performs other required setup before project files are generated.
*/
private void prepareGeneration(in Package pack, in Project proj, in GeneratorSettings settings,
	in BuildSettings buildsettings)
{
	if (buildsettings.preGenerateCommands.length && !isRecursiveInvocation(pack.name)) {
		logInfo("Running pre-generate commands for %s...", pack.name);
		runBuildCommands(buildsettings.preGenerateCommands, pack, proj, settings, buildsettings);
	}
}

/**
	Runs post-build commands and copies required files to the binary directory.
*/
private void finalizeGeneration(in Package pack, in Project proj, in GeneratorSettings settings,
	in BuildSettings buildsettings, NativePath target_path, bool generate_binary)
{
	import std.path : globMatch;

	if (buildsettings.postGenerateCommands.length && !isRecursiveInvocation(pack.name)) {
		logInfo("Running post-generate commands for %s...", pack.name);
		runBuildCommands(buildsettings.postGenerateCommands, pack, proj, settings, buildsettings);
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
			string[] globs;
			foreach (f; buildsettings.copyFiles)
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
						tryCopyDir(f);
					else
						tryCopyFile(f);
				}
			}
			if (globs.length) // Search all files for glob matches
			{
				foreach (f; dirEntries(pack.path.toNativeString(), SpanMode.breadth))
				{
					foreach (glob; globs)
					{
						if (f.name().globMatch(glob))
						{
							if (f.isDir)
								tryCopyDir(f);
							else
								tryCopyFile(f);
							break;
						}
					}
				}
			}
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
	in GeneratorSettings settings, in BuildSettings build_settings)
{
	import std.conv;
	import std.process;
	import dub.internal.utils;

	string[string] env = environment.toAA();
	// TODO: do more elaborate things here
	// TODO: escape/quote individual items appropriately
	env["DFLAGS"]                = join(cast(string[])build_settings.dflags, " ");
	env["LFLAGS"]                = join(cast(string[])build_settings.lflags," ");
	env["VERSIONS"]              = join(cast(string[])build_settings.versions," ");
	env["LIBS"]                  = join(cast(string[])build_settings.libs," ");
	env["IMPORT_PATHS"]          = join(cast(string[])build_settings.importPaths," ");
	env["STRING_IMPORT_PATHS"]   = join(cast(string[])build_settings.stringImportPaths," ");

	env["DC"]                    = settings.platform.compilerBinary;
	env["DC_BASE"]               = settings.platform.compiler;
	env["D_FRONTEND_VER"]        = to!string(settings.platform.frontendVersion);

	env["DUB_PLATFORM"]          = join(cast(string[])settings.platform.platform," ");
	env["DUB_ARCH"]              = join(cast(string[])settings.platform.architecture," ");

	env["DUB_TARGET_TYPE"]       = to!string(build_settings.targetType);
	env["DUB_TARGET_PATH"]       = build_settings.targetPath;
	env["DUB_TARGET_NAME"]       = build_settings.targetName;
	env["DUB_WORKING_DIRECTORY"] = build_settings.workingDirectory;
	env["DUB_MAIN_SOURCE_FILE"]  = build_settings.mainSourceFile;

	env["DUB_CONFIG"]            = settings.config;
	env["DUB_BUILD_TYPE"]        = settings.buildType;
	env["DUB_BUILD_MODE"]        = to!string(settings.buildMode);
	env["DUB_PACKAGE"]           = pack.name;
	env["DUB_PACKAGE_DIR"]       = pack.path.toNativeString();
	env["DUB_ROOT_PACKAGE"]      = proj.rootPackage.name;
	env["DUB_ROOT_PACKAGE_DIR"]  = proj.rootPackage.path.toNativeString();

	env["DUB_COMBINED"]          = settings.combined?      "TRUE" : "";
	env["DUB_RUN"]               = settings.run?           "TRUE" : "";
	env["DUB_FORCE"]             = settings.force?         "TRUE" : "";
	env["DUB_DIRECT"]            = settings.direct?        "TRUE" : "";
	env["DUB_RDMD"]              = settings.rdmd?          "TRUE" : "";
	env["DUB_TEMP_BUILD"]        = settings.tempBuild?     "TRUE" : "";
	env["DUB_PARALLEL_BUILD"]    = settings.parallelBuild? "TRUE" : "";

	env["DUB_RUN_ARGS"] = (cast(string[])settings.runArgs).map!(escapeShellFileName).join(" ");

	auto depNames = proj.dependencies.map!((a) => a.name).array();
	storeRecursiveInvokations(env, proj.rootPackage.name ~ depNames);
	runCommands(commands, env);
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
