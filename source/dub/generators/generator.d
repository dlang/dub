/**
	Generator for project files

	Copyright: © 2012-2013 Matthias Dondorff
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
		if (!settings.config.length) settings.config = m_project.getDefaultConfiguration(settings.platform);

		TargetInfo[string] targets;
		string[string] configs = m_project.getPackageConfigs(settings.platform, settings.config);

		foreach (pack; m_project.getTopologicalPackageList(true, null, configs)) {
			BuildSettings buildsettings;
			buildsettings.processVars(m_project, pack, pack.getBuildSettings(settings.platform, configs[pack.name]), true);
			prepareGeneration(pack.name, buildsettings);
		}

		string[] mainfiles;
		collect(settings, m_project.rootPackage, targets, configs, mainfiles, null);
		downwardsInheritSettings(m_project.rootPackage.name, targets, targets[m_project.rootPackage.name].buildSettings);
		foreach (ref t; targets.byValue) enforceBuildRequirements(t.buildSettings);
		auto bs = &targets[m_project.rootPackage.name].buildSettings;
		if (bs.targetType == TargetType.executable) bs.addSourceFiles(mainfiles);

		generateTargets(settings, targets);

		foreach (pack; m_project.getTopologicalPackageList(true, null, configs)) {
			BuildSettings buildsettings;
			buildsettings.processVars(m_project, pack, pack.getBuildSettings(settings.platform, configs[pack.name]), true);
			bool generate_binary = !(buildsettings.options & BuildOption.syntaxOnly);
			finalizeGeneration(pack.name, buildsettings, pack.path, Path(bs.targetPath), generate_binary);
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

	private BuildSettings collect(GeneratorSettings settings, Package pack, ref TargetInfo[string] targets, in string[string] configs, ref string[] main_files, string bin_pack)
	{
		if (auto pt = pack.name in targets) return pt.buildSettings;

		// determine the actual target type
		auto shallowbs = pack.getBuildSettings(settings.platform, configs[pack.name]);
		TargetType tt = shallowbs.targetType;
		if (pack is m_project.rootPackage) {
			if (tt == TargetType.autodetect || tt == TargetType.library) tt = TargetType.staticLibrary;
		} else {
			if (tt == TargetType.autodetect || tt == TargetType.library) tt = settings.combined ? TargetType.sourceLibrary : TargetType.staticLibrary;
			else if (tt == TargetType.dynamicLibrary) {
				logWarn("Dynamic libraries are not yet supported as dependencies - building as static library.");
				tt = TargetType.staticLibrary;
			}
		}
		if (tt != TargetType.none && tt != TargetType.sourceLibrary && shallowbs.sourceFiles.empty) {
			logWarn(`Configuration '%s' of package %s contains no source files. Please add {"targetType": "none"} to it's package description to avoid building it.`,
				configs[pack.name], pack.name);
			tt = TargetType.none;
		}

		shallowbs.targetType = tt;
		bool generates_binary = tt != TargetType.sourceLibrary && tt != TargetType.none;
		bool is_target = generates_binary || pack is m_project.rootPackage;

		if (tt == TargetType.none) {
			// ignore any build settings for targetType none (only dependencies will be processed)
			shallowbs = BuildSettings.init;
		}

		// start to build up the build settings
		BuildSettings buildsettings;
		if (is_target) buildsettings = settings.buildSettings.dup;
		processVars(buildsettings, m_project, pack, shallowbs, true);

		// remove any mainSourceFile from library builds
		if (buildsettings.targetType != TargetType.executable && buildsettings.mainSourceFile.length) {
			buildsettings.sourceFiles = buildsettings.sourceFiles.filter!(f => f != buildsettings.mainSourceFile)().array;
			main_files ~= buildsettings.mainSourceFile;
		}

		logDiagnostic("Generate target %s (%s %s %s)", pack.name, buildsettings.targetType, buildsettings.targetPath, buildsettings.targetName);
		if (is_target)
			targets[pack.name] = TargetInfo(pack, [pack], configs[pack.name], buildsettings, null);

		foreach (depname, depspec; pack.dependencies) {
			if (!pack.hasDependency(depname, configs[pack.name])) continue;
			auto dep = m_project.getDependency(depname, depspec.optional);
			if (!dep) continue;

			auto depbs = collect(settings, dep, targets, configs, main_files, is_target ? pack.name : bin_pack);

			if (depbs.targetType != TargetType.sourceLibrary && depbs.targetType != TargetType.none) {
				// add a reference to the target binary and remove all source files in the dependency build settings
				depbs.sourceFiles = depbs.sourceFiles.filter!(f => f.isLinkerFile()).array;
				depbs.importFiles = null;
			}

			buildsettings.add(depbs);

			if (depbs.targetType == TargetType.executable)
				continue;

			auto pt = (is_target ? pack.name : bin_pack) in targets;
			assert(pt !is null);
			if (auto pdt = depname in targets) {
				pt.dependencies ~= depname;
				pt.linkDependencies ~= depname;
				if (depbs.targetType == TargetType.staticLibrary)
					pt.linkDependencies = pt.linkDependencies.filter!(d => !pdt.linkDependencies.canFind(d)).array ~ pdt.linkDependencies;
			} else pt.packages ~= dep;
		}

		if (is_target) {
			// add build type settings and convert plain DFLAGS to build options
			m_project.addBuildTypeSettings(buildsettings, settings.platform, settings.buildType);
			settings.compiler.extractBuildOptions(buildsettings);

			enforce (generates_binary || pack !is m_project.rootPackage || (buildsettings.options & BuildOption.syntaxOnly),
				format("Main package must have a binary target type, not %s. Cannot build.", tt));

			targets[pack.name].buildSettings = buildsettings.dup;
		}

		return buildsettings;
	}

	private string[] downwardsInheritSettings(string target, TargetInfo[string] targets, in BuildSettings root_settings)
	{
		auto ti = &targets[target];
		ti.buildSettings.addVersions(root_settings.versions);
		ti.buildSettings.addDebugVersions(root_settings.debugVersions);
		ti.buildSettings.addOptions(root_settings.options);

		// special support for overriding string imports in parent packages
		// this is a candidate for deprecation, once an alternative approach
		// has been found
		if (ti.buildSettings.stringImportPaths.length) {
			// override string import files (used for up to date checking)
			foreach (ref f; ti.buildSettings.stringImportFiles)
				foreach (fi; root_settings.stringImportFiles)
					if (f != fi && Path(f).head == Path(fi).head) {
						f = fi;
					}

			// add the string import paths (used by the compiler to find the overridden files)
			ti.buildSettings.prependStringImportPaths(root_settings.stringImportPaths);
		}

		string[] packs = ti.packages.map!(p => p.name).array;
		foreach (d; ti.dependencies)
			packs ~= downwardsInheritSettings(d, targets, root_settings);

		logDebug("%s: %s", target, packs);

		// Add Have_* versions *after* downwards inheritance, so that dependencies
		// are build independently of the parent packages w.r.t the other parent
		// dependencies. This enables sharing of the same package build for
		// multiple dependees.
		ti.buildSettings.addVersions(packs.map!(pn => "Have_" ~ stripDlangSpecialChars(pn)).array);

		return packs;
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
	bool run, force, direct, clean, rdmd, tempBuild, parallelBuild;
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
private void prepareGeneration(string pack, in BuildSettings buildsettings)
{
	if( buildsettings.preGenerateCommands.length ){
		logInfo("Running pre-generate commands for %s...", pack);
		runBuildCommands(buildsettings.preGenerateCommands, buildsettings);
	}
}

/**
	Runs post-build commands and copies required files to the binary directory.
*/
private void finalizeGeneration(string pack, in BuildSettings buildsettings, Path pack_path, Path target_path, bool generate_binary)
{
	if (buildsettings.postGenerateCommands.length) {
		logInfo("Running post-generate commands for %s...", pack);
		runBuildCommands(buildsettings.postGenerateCommands, buildsettings);
	}

	if (generate_binary) {
		if (!exists(buildsettings.targetPath))
			mkdirRecurse(buildsettings.targetPath);

		if (buildsettings.copyFiles.length) {
			void copyFolderRec(Path folder, Path dstfolder)
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
				auto src = Path(file);
				if (!src.absolute) src = pack_path ~ src;
				auto dst = target_path ~ Path(file).head;
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
				auto src = Path(file);
				if (!src.absolute) src = pack_path ~ src;
				auto dst = target_path ~ Path(file).head;
				if (src == dst) {
					logDiagnostic("Skipping copy of %s (same source and destination)", file);
					return;
				}
				logDiagnostic("  %s to %s", src.toNativeString(), dst.toNativeString());
				try {
					hardLinkFile(src, dst, true);
				} catch(Exception e) logWarn("Failed to copy %s to %s: %s", src.toNativeString(), dst.toNativeString(), e.msg);
			}
			logInfo("Copying files for %s...", pack);
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
				foreach (f; dirEntries(pack_path.toNativeString(), SpanMode.breadth))
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

void runBuildCommands(in string[] commands, in BuildSettings build_settings)
{
	import std.process;
	import dub.internal.utils;

	string[string] env = environment.toAA();
	// TODO: do more elaborate things here
	// TODO: escape/quote individual items appropriately
	env["DFLAGS"] = join(cast(string[])build_settings.dflags, " ");
	env["LFLAGS"] = join(cast(string[])build_settings.lflags," ");
	env["VERSIONS"] = join(cast(string[])build_settings.versions," ");
	env["LIBS"] = join(cast(string[])build_settings.libs," ");
	env["IMPORT_PATHS"] = join(cast(string[])build_settings.importPaths," ");
	env["STRING_IMPORT_PATHS"] = join(cast(string[])build_settings.stringImportPaths," ");
	runCommands(commands, env);
}
