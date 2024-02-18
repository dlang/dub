/**
	Generator for direct compiler builds.

	Copyright: © 2013-2013 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.generators.build;

import dub.compilers.compiler;
import dub.compilers.utils;
import dub.generators.generator;
import dub.internal.utils;
import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.inet.path;
import dub.internal.logging;
import dub.package_;
import dub.packagemanager;
import dub.project;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.file;
import std.process;
import std.string;
import std.encoding : sanitize;

string getObjSuffix(const scope ref BuildPlatform platform)
{
    return platform.isWindows() ? ".obj" : ".o";
}

string computeBuildName(string config, in GeneratorSettings settings, const string[][] hashing...)
{
	import std.digest.sha : SHA256;
	import std.base64 : Base64URL;

	SHA256 hash;
	hash.start();
	void addHash(in string[] strings...) { foreach (s; strings) { hash.put(cast(ubyte[])s); hash.put(0); } hash.put(0); }
	foreach(strings; hashing)
		addHash(strings);
	addHash(settings.platform.platform);
	addHash(settings.platform.architecture);
	addHash(settings.platform.compiler);
	addHash(settings.platform.compilerVersion);
	if(settings.recipeName != "")
		addHash(settings.recipeName);
	const hashstr = Base64URL.encode(hash.finish()[0 .. $ / 2]).stripRight("=");

	if(settings.recipeName != "")
	{
		import std.path:stripExtension, baseName;
		string recipeName = settings.recipeName.baseName.stripExtension;
		return format("%s-%s-%s-%s", config, settings.buildType, recipeName, hashstr);
	}
	return format("%s-%s-%s", config, settings.buildType, hashstr);
}

class BuildGenerator : ProjectGenerator {
	private {
		NativePath[] m_temporaryFiles;
	}

	this(Project project)
	{
		super(project);
	}

	override void generateTargets(GeneratorSettings settings, in TargetInfo[string] targets)
	{
		import std.path : setExtension;
		scope (exit) cleanupTemporaries();

		void checkPkgRequirements(const(Package) pkg)
		{
			const tr = pkg.recipe.toolchainRequirements;
			tr.checkPlatform(settings.platform, pkg.name);
		}

		checkPkgRequirements(m_project.rootPackage);
		foreach (pkg; m_project.dependencies)
			checkPkgRequirements(pkg);

		auto root_ti = targets[m_project.rootPackage.name];
		const rootTT = root_ti.buildSettings.targetType;

		enforce(!(settings.rdmd && rootTT == TargetType.none),
				"Building package with target type \"none\" with rdmd is not supported yet.");

		logInfo("Starting", Color.light_green,
		    "Performing \"%s\" build using %s for %-(%s, %).",
			settings.buildType.color(Color.magenta), settings.platform.compilerBinary,
			settings.platform.architecture);

		if (settings.rdmd || (rootTT == TargetType.staticLibrary && !settings.buildDeep)) {
			// Only build the main target.
			// RDMD always builds everything at once and static libraries don't need their
			// dependencies to be built, unless --deep flag is specified
			NativePath tpath;
			buildTarget(settings, root_ti.buildSettings.dup, m_project.rootPackage, root_ti.config, root_ti.packages, null, tpath);
			return;
		}

		// Recursive build starts here

		bool any_cached = false;

		NativePath[string] target_paths;

		NativePath[] dynamicLibDepsFilesToCopy; // to the root package output dir
		const copyDynamicLibDepsLinkerFiles = rootTT == TargetType.dynamicLibrary || rootTT == TargetType.none;
		const copyDynamicLibDepsRuntimeFiles = copyDynamicLibDepsLinkerFiles || rootTT == TargetType.executable;

		bool[string] visited;
		void buildTargetRec(string target)
		{
			if (target in visited) return;
			visited[target] = true;

			auto ti = targets[target];

			foreach (dep; ti.dependencies)
				buildTargetRec(dep);

			NativePath[] additional_dep_files;
			auto bs = ti.buildSettings.dup;
			const tt = bs.targetType;
			foreach (ldep; ti.linkDependencies) {
				const ldepPath = target_paths[ldep].toNativeString();
				const doLink = tt != TargetType.staticLibrary && !(bs.options & BuildOption.syntaxOnly);

				if (doLink && isLinkerFile(settings.platform, ldepPath))
					bs.addSourceFiles(ldepPath);
				else
					additional_dep_files ~= target_paths[ldep];

				if (targets[ldep].buildSettings.targetType == TargetType.dynamicLibrary) {
					// copy the .{dll,so,dylib}
					if (copyDynamicLibDepsRuntimeFiles)
						dynamicLibDepsFilesToCopy ~= NativePath(ldepPath);

					if (settings.platform.isWindows()) {
						// copy the accompanying .pdb if found
						if (copyDynamicLibDepsRuntimeFiles) {
							const pdb = ldepPath.setExtension(".pdb");
							if (existsFile(pdb))
								dynamicLibDepsFilesToCopy ~= NativePath(pdb);
						}

						const importLib = ldepPath.setExtension(".lib");
						if (existsFile(importLib)) {
							// link dependee against the import lib
							if (doLink)
								bs.addSourceFiles(importLib);
							// and copy
							if (copyDynamicLibDepsLinkerFiles)
								dynamicLibDepsFilesToCopy ~= NativePath(importLib);
						}

						// copy the .exp file if found
						const exp = ldepPath.setExtension(".exp");
						if (copyDynamicLibDepsLinkerFiles && existsFile(exp))
							dynamicLibDepsFilesToCopy ~= NativePath(exp);
					}
				}
			}
			NativePath tpath;
			if (tt != TargetType.none) {
				if (buildTarget(settings, bs, ti.pack, ti.config, ti.packages, additional_dep_files, tpath))
					any_cached = true;
			}
			target_paths[target] = tpath;
		}

		buildTargetRec(m_project.rootPackage.name);

		if (dynamicLibDepsFilesToCopy.length) {
			const rootTargetPath = NativePath(root_ti.buildSettings.targetPath);

			ensureDirectory(rootTargetPath);
			foreach (src; dynamicLibDepsFilesToCopy) {
				logDiagnostic("Copying target from %s to %s",
					src.toNativeString(), rootTargetPath.toNativeString());
				hardLinkFile(src, rootTargetPath ~ src.head, true);
			}
		}

		if (any_cached) {
			logInfo("Finished", Color.green,
				"To force a rebuild of up-to-date targets, run again with --force"
			);
		}
	}

	override void performPostGenerateActions(GeneratorSettings settings, in TargetInfo[string] targets)
	{
		// run the generated executable
		auto buildsettings = targets[m_project.rootPackage.name].buildSettings.dup;
		if (settings.run && !(buildsettings.options & BuildOption.syntaxOnly)) {
			NativePath exe_file_path;
			if (m_tempTargetExecutablePath.empty)
				exe_file_path = getTargetPath(buildsettings, settings);
			else
				exe_file_path = m_tempTargetExecutablePath ~ settings.compiler.getTargetFileName(buildsettings, settings.platform);
			runTarget(exe_file_path, buildsettings, settings.runArgs, settings);
		}
	}

	private bool buildTarget(GeneratorSettings settings, BuildSettings buildsettings, in Package pack, string config, in Package[] packages, in NativePath[] additional_dep_files, out NativePath target_path)
	{
		import std.path : absolutePath;

		auto cwd = settings.toolWorkingDirectory;
		bool generate_binary = !(buildsettings.options & BuildOption.syntaxOnly);

		auto build_id = buildsettings.computeBuildID(pack.path, config, settings);

		// make all paths relative to shrink the command line
		string makeRelative(string path) { return shrinkPath(NativePath(path), cwd); }
		foreach (ref f; buildsettings.sourceFiles) f = makeRelative(f);
		foreach (ref p; buildsettings.importPaths) p = makeRelative(p);
		foreach (ref p; buildsettings.cImportPaths) p = makeRelative(p);
		foreach (ref p; buildsettings.stringImportPaths) p = makeRelative(p);

		// perform the actual build
		bool cached = false;
		if (settings.rdmd) performRDMDBuild(settings, buildsettings, pack, config, target_path);
		else if (!generate_binary) performDirectBuild(settings, buildsettings, pack, config, target_path);
		else cached = performCachedBuild(settings, buildsettings, pack, config, build_id, packages, additional_dep_files, target_path);

		// HACK: cleanup dummy doc files, we shouldn't specialize on buildType
		// here and the compiler shouldn't need dummy doc output.
		if (settings.buildType == "ddox") {
			if ("__dummy.html".exists)
				removeFile("__dummy.html");
			if ("__dummy_docs".exists)
				rmdirRecurse("__dummy_docs");
		}

		// run post-build commands
		if (!cached && buildsettings.postBuildCommands.length) {
			logInfo("Post-build", Color.light_green, "Running commands");
			runBuildCommands(CommandType.postBuild, buildsettings.postBuildCommands, pack, m_project, settings, buildsettings,
							[["DUB_BUILD_PATH" : target_path is NativePath.init
								? ""
								: target_path.parentPath.toNativeString.absolutePath(settings.toolWorkingDirectory.toNativeString)]]);
		}

		return cached;
	}

	private bool performCachedBuild(GeneratorSettings settings, BuildSettings buildsettings, in Package pack, string config,
		string build_id, in Package[] packages, in NativePath[] additional_dep_files, out NativePath target_binary_path)
	{
		NativePath target_path;
		if (settings.tempBuild) {
			string packageName = pack.basePackage is null ? pack.name : pack.basePackage.name;
			m_tempTargetExecutablePath = target_path = getTempDir() ~ format(".dub/build/%s-%s/%s/", packageName, pack.version_, build_id);
		}
		else
			target_path = targetCacheDir(settings.cache, pack, build_id);

		if (!settings.force && isUpToDate(target_path, buildsettings, settings, pack, packages, additional_dep_files)) {
			logInfo("Up-to-date", Color.green, "%s %s: target for configuration [%s] is up to date.",
				pack.name.color(Mode.bold), pack.version_, config.color(Color.blue));
			logDiagnostic("Using existing build in %s.", target_path.toNativeString());
			target_binary_path = target_path ~ settings.compiler.getTargetFileName(buildsettings, settings.platform);
			if (!settings.tempBuild)
				copyTargetFile(target_path, buildsettings, settings);
			return true;
		}

		if (!isWritableDir(target_path, true)) {
			if (!settings.tempBuild)
				logInfo("Build directory %s is not writable. Falling back to direct build in the system's temp folder.", target_path);
			performDirectBuild(settings, buildsettings, pack, config, target_path);
			return false;
		}

		logInfo("Building", Color.light_green, "%s %s: building configuration [%s]", pack.name.color(Mode.bold), pack.version_, config.color(Color.blue));

		if( buildsettings.preBuildCommands.length ){
			logInfo("Pre-build", Color.light_green, "Running commands");
			runBuildCommands(CommandType.preBuild, buildsettings.preBuildCommands, pack, m_project, settings, buildsettings);
		}

		// override target path
		auto cbuildsettings = buildsettings;
		cbuildsettings.targetPath = target_path.toNativeString();
		buildWithCompiler(settings, cbuildsettings);
		target_binary_path = getTargetPath(cbuildsettings, settings);

		if (!settings.tempBuild) {
			copyTargetFile(target_path, buildsettings, settings);
			updateCacheDatabase(settings, cbuildsettings, pack, config, build_id, target_binary_path.toNativeString());
		}

		return false;
	}

	private void updateCacheDatabase(GeneratorSettings settings, BuildSettings buildsettings, in Package pack, string config,
		string build_id, string target_binary_path)
	{
		import dub.internal.vibecompat.data.json;
		import core.time : seconds;

		// Generate a `db.json` in the package version cache directory.
		// This is read by 3rd party software (e.g. Meson) in order to find
		// relevant build artifacts in Dub's cache.

		enum jsonFileName = "db.json";
		enum lockFileName = "db.lock";

		const pkgCacheDir = packageCache(settings.cache, pack);
		auto lock = lockFile((pkgCacheDir ~ lockFileName).toNativeString(), 3.seconds);

		const dbPath = pkgCacheDir ~ jsonFileName;
		const dbPathStr = dbPath.toNativeString();
		Json db;
		if (exists(dbPathStr)) {
			const text = readText(dbPath);
			db = parseJsonString(text, dbPathStr);
			enforce(db.type == Json.Type.array, "Expected a JSON array in " ~ dbPathStr);
		}
		else {
			db = Json.emptyArray;
		}

		foreach_reverse (entry; db) {
			if (entry["buildId"].get!string == build_id) {
				// duplicate
				return;
			}
		}

		Json entry = Json.emptyObject;

		entry["architecture"] = serializeToJson(settings.platform.architecture);
		entry["buildId"] = build_id;
		entry["buildType"] = settings.buildType;
		entry["compiler"] = settings.platform.compiler;
		entry["compilerBinary"] = settings.platform.compilerBinary;
		entry["compilerVersion"] = settings.platform.compilerVersion;
		entry["configuration"] = config;
		entry["package"] = pack.name;
		entry["platform"] = serializeToJson(settings.platform.platform);
		entry["targetBinaryPath"] = target_binary_path;
		entry["version"] = pack.version_.toString();

		db ~= entry;

		writeFile(dbPath, representation(db.toPrettyString()));
	}

	private void performRDMDBuild(GeneratorSettings settings, ref BuildSettings buildsettings, in Package pack, string config, out NativePath target_path)
	{
		auto cwd = settings.toolWorkingDirectory;
		//Added check for existence of [AppNameInPackagejson].d
		//If exists, use that as the starting file.
		NativePath mainsrc;
		if (buildsettings.mainSourceFile.length) {
			mainsrc = NativePath(buildsettings.mainSourceFile);
			if (!mainsrc.absolute) mainsrc = pack.path ~ mainsrc;
		} else {
			mainsrc = getMainSourceFile(pack);
			logWarn(`Package has no "mainSourceFile" defined. Using best guess: %s`, mainsrc.relativeTo(pack.path).toNativeString());
		}

		// do not pass all source files to RDMD, only the main source file
		buildsettings.sourceFiles = buildsettings.sourceFiles.filter!(s => !s.endsWith(".d"))().array();
		settings.compiler.prepareBuildSettings(buildsettings, settings.platform, BuildSetting.commandLine);

		auto generate_binary = !buildsettings.dflags.canFind("-o-");

		// Create start script, which will be used by the calling bash/cmd script.
		// build "rdmd --force %DFLAGS% -I%~dp0..\source -Jviews -Isource @deps.txt %LIBS% source\app.d" ~ application arguments
		// or with "/" instead of "\"
		bool tmp_target = false;
		if (generate_binary) {
			if (settings.tempBuild || (settings.run && !isWritableDir(NativePath(buildsettings.targetPath), true))) {
				import std.random;
				auto rnd = to!string(uniform(uint.min, uint.max)) ~ "-";
				auto tmpdir = getTempDir()~".rdmd/source/";
				buildsettings.targetPath = tmpdir.toNativeString();
				buildsettings.targetName = rnd ~ buildsettings.targetName;
				m_temporaryFiles ~= tmpdir;
				tmp_target = true;
			}
			target_path = getTargetPath(buildsettings, settings);
			settings.compiler.setTarget(buildsettings, settings.platform);
		}

		logDiagnostic("Application output name is '%s'", settings.compiler.getTargetFileName(buildsettings, settings.platform));

		string[] flags = ["--build-only", "--compiler="~settings.platform.compilerBinary];
		if (settings.force) flags ~= "--force";
		flags ~= buildsettings.dflags;
		flags ~= mainsrc.relativeTo(cwd).toNativeString();

		if (buildsettings.preBuildCommands.length){
			logInfo("Pre-build", Color.light_green, "Running commands");
			runCommands(buildsettings.preBuildCommands, null, cwd.toNativeString());
		}

		logInfo("Building", Color.light_green, "%s %s [%s]", pack.name.color(Mode.bold), pack.version_, config.color(Color.blue));

		logInfo("Running rdmd...");
		logDiagnostic("rdmd %s", join(flags, " "));
		auto rdmd_pid = spawnProcess("rdmd" ~ flags, null, Config.none, cwd.toNativeString());
		auto result = rdmd_pid.wait();
		enforce(result == 0, "Build command failed with exit code "~to!string(result));

		if (tmp_target) {
			m_temporaryFiles ~= target_path;
			foreach (f; buildsettings.copyFiles)
				m_temporaryFiles ~= NativePath(buildsettings.targetPath).parentPath ~ NativePath(f).head;
		}
	}

	private void performDirectBuild(GeneratorSettings settings, ref BuildSettings buildsettings, in Package pack, string config, out NativePath target_path)
	{
		auto cwd = settings.toolWorkingDirectory;
		auto generate_binary = !(buildsettings.options & BuildOption.syntaxOnly);

		// make file paths relative to shrink the command line
		foreach (ref f; buildsettings.sourceFiles) {
			auto fp = NativePath(f);
			if( fp.absolute ) fp = fp.relativeTo(cwd);
			f = fp.toNativeString();
		}

		logInfo("Building", Color.light_green, "%s %s [%s]", pack.name.color(Mode.bold), pack.version_, config.color(Color.blue));

		// make all target/import paths relative
		string makeRelative(string path) {
			auto p = NativePath(path);
			// storing in a separate temprary to work around #601
			auto prel = p.absolute ? p.relativeTo(cwd) : p;
			return prel.toNativeString();
		}
		buildsettings.targetPath = makeRelative(buildsettings.targetPath);
		foreach (ref p; buildsettings.importPaths) p = makeRelative(p);
		foreach (ref p; buildsettings.cImportPaths) p = makeRelative(p);
		foreach (ref p; buildsettings.stringImportPaths) p = makeRelative(p);

		bool is_temp_target = false;
		if (generate_binary) {
			if (settings.tempBuild || (settings.run && !isWritableDir(NativePath(buildsettings.targetPath), true))) {
				import std.random;
				auto rnd = to!string(uniform(uint.min, uint.max));
				auto tmppath = getTempDir()~("dub/"~rnd~"/");
				buildsettings.targetPath = tmppath.toNativeString();
				m_temporaryFiles ~= tmppath;
				is_temp_target = true;
			}
			target_path = getTargetPath(buildsettings, settings);
		}

		if( buildsettings.preBuildCommands.length ){
			logInfo("Pre-build", Color.light_green, "Running commands");
			runBuildCommands(CommandType.preBuild, buildsettings.preBuildCommands, pack, m_project, settings, buildsettings);
		}

		buildWithCompiler(settings, buildsettings);

		if (is_temp_target) {
			m_temporaryFiles ~= target_path;
			foreach (f; buildsettings.copyFiles)
				m_temporaryFiles ~= NativePath(buildsettings.targetPath).parentPath ~ NativePath(f).head;
		}
	}

	private void copyTargetFile(in NativePath build_path, in BuildSettings buildsettings, in GeneratorSettings settings)
	{
		ensureDirectory(NativePath(buildsettings.targetPath));

		string[] filenames = [
			settings.compiler.getTargetFileName(buildsettings, settings.platform)
		];

		// Windows: add .pdb (for executables and DLLs) and/or import .lib & .exp (for DLLs) if found
		if (settings.platform.isWindows()) {
			void addIfFound(string extension) {
				import std.path : setExtension;
				const candidate = filenames[0].setExtension(extension);
				if (existsFile(build_path ~ candidate))
					filenames ~= candidate;
			}

			const tt = buildsettings.targetType;
			if (tt == TargetType.executable || tt == TargetType.dynamicLibrary)
				addIfFound(".pdb");

			if (tt == TargetType.dynamicLibrary) {
				addIfFound(".lib");
				addIfFound(".exp");
			}
		}

		foreach (filename; filenames)
		{
			auto src = build_path ~ filename;
			logDiagnostic("Copying target from %s to %s", src.toNativeString(), buildsettings.targetPath);
			hardLinkFile(src, NativePath(buildsettings.targetPath) ~ filename, true);
		}
	}

	private bool isUpToDate(NativePath target_path, BuildSettings buildsettings, GeneratorSettings settings, in Package main_pack, in Package[] packages, in NativePath[] additional_dep_files)
	{
		import std.datetime;

		auto targetfile = target_path ~ settings.compiler.getTargetFileName(buildsettings, settings.platform);
		if (!existsFile(targetfile)) {
			logDiagnostic("Target '%s' doesn't exist, need rebuild.", targetfile.toNativeString());
			return false;
		}
		auto targettime = getFileInfo(targetfile).timeModified;

		auto allfiles = appender!(string[]);
		allfiles ~= buildsettings.sourceFiles;
		allfiles ~= buildsettings.importFiles;
		allfiles ~= buildsettings.stringImportFiles;
		allfiles ~= buildsettings.extraDependencyFiles;
		// TODO: add library files
		foreach (p; packages)
			allfiles ~= (p.recipePath != NativePath.init ? p : p.basePackage).recipePath.toNativeString();
		foreach (f; additional_dep_files) allfiles ~= f.toNativeString();
		bool checkSelectedVersions = !settings.single;
		if (checkSelectedVersions && main_pack is m_project.rootPackage && m_project.rootPackage.getAllDependencies().length > 0)
			allfiles ~= (main_pack.path ~ SelectedVersions.defaultFile).toNativeString();

		foreach (file; allfiles.data) {
			if (!existsFile(file)) {
				logDiagnostic("File %s doesn't exist, triggering rebuild.", file);
				return false;
			}
			auto ftime = getFileInfo(file).timeModified;
			if (ftime > Clock.currTime)
				logWarn("File '%s' was modified in the future. Please re-save.", file);
			if (ftime > targettime) {
				logDiagnostic("File '%s' modified, need rebuild.", file);
				return false;
			}
		}
		return true;
	}

	/// Output an unique name to represent the source file.
	/// Calls with path that resolve to the same file on the filesystem will return the same,
	/// unless they include different symbolic links (which are not resolved).
	deprecated("Use the overload taking in the current working directory")
	static string pathToObjName(const scope ref BuildPlatform platform, string path)
	{
		return pathToObjName(platform, path, getWorkingDirectory);
	}

	/// ditto
	static string pathToObjName(const scope ref BuildPlatform platform, string path, NativePath cwd)
	{
		import std.digest.crc : crc32Of;
		import std.path : buildNormalizedPath, dirSeparator, relativePath, stripDrive;
		if (path.endsWith(".d")) path = path[0 .. $-2];
		auto ret = buildNormalizedPath(cwd.toNativeString(), path).replace(dirSeparator, ".");
		auto idx = ret.lastIndexOf('.');
		const objSuffix = getObjSuffix(platform);
		return idx < 0 ? ret ~ objSuffix : format("%s_%(%02x%)%s", ret[idx+1 .. $], crc32Of(ret[0 .. idx]), objSuffix);
	}

	/// Compile a single source file (srcFile), and write the object to objName.
	static string compileUnit(string srcFile, string objName, BuildSettings bs, GeneratorSettings gs) {
		NativePath tempobj = NativePath(bs.targetPath)~objName;
		string objPath = tempobj.toNativeString();
		bs.libs = null;
		bs.lflags = null;
		bs.sourceFiles = [ srcFile ];
		bs.targetType = TargetType.object;
		gs.compiler.prepareBuildSettings(bs, gs.platform, BuildSetting.commandLine);
		gs.compiler.setTarget(bs, gs.platform, objPath);
		gs.compiler.invoke(bs, gs.platform, gs.compileCallback, gs.toolWorkingDirectory);
		return objPath;
	}

	private void buildWithCompiler(GeneratorSettings settings, BuildSettings buildsettings)
	{
		auto generate_binary = !(buildsettings.options & BuildOption.syntaxOnly);
		auto is_static_library = buildsettings.targetType == TargetType.staticLibrary || buildsettings.targetType == TargetType.library;

		scope (failure) {
			logDiagnostic("FAIL %s %s %s" , buildsettings.targetPath, buildsettings.targetName, buildsettings.targetType);
			auto tpath = getTargetPath(buildsettings, settings);
			if (generate_binary && existsFile(tpath))
				removeFile(tpath);
		}
		if (settings.buildMode == BuildMode.singleFile && generate_binary) {
			import std.parallelism, std.range : walkLength;

			auto lbuildsettings = buildsettings;
			auto srcs = buildsettings.sourceFiles.filter!(f => !isLinkerFile(settings.platform, f));
			auto objs = new string[](srcs.walkLength);

			void compileSource(size_t i, string src) {
				logInfo("Compiling", Color.light_green, "%s", src);
				const objPath = pathToObjName(settings.platform, src, settings.toolWorkingDirectory);
				objs[i] = compileUnit(src, objPath, buildsettings, settings);
			}

			if (settings.parallelBuild) {
				foreach (i, src; srcs.parallel(1)) compileSource(i, src);
			} else {
				foreach (i, src; srcs.array) compileSource(i, src);
			}

			logInfo("Linking", Color.light_green, "%s", buildsettings.targetName.color(Mode.bold));
			lbuildsettings.sourceFiles = is_static_library ? [] : lbuildsettings.sourceFiles.filter!(f => isLinkerFile(settings.platform, f)).array;
			settings.compiler.setTarget(lbuildsettings, settings.platform);
			settings.compiler.prepareBuildSettings(lbuildsettings, settings.platform, BuildSetting.commandLineSeparate|BuildSetting.sourceFiles);
			settings.compiler.invokeLinker(lbuildsettings, settings.platform, objs, settings.linkCallback, settings.toolWorkingDirectory);

		// NOTE: separate compile/link is not yet enabled for GDC.
		} else if (generate_binary && (settings.buildMode == BuildMode.allAtOnce || settings.compiler.name == "gdc" || is_static_library)) {
			// don't include symbols of dependencies (will be included by the top level target)
			if (is_static_library) buildsettings.sourceFiles = buildsettings.sourceFiles.filter!(f => !isLinkerFile(settings.platform, f)).array;

			// setup for command line
			settings.compiler.setTarget(buildsettings, settings.platform);
			settings.compiler.prepareBuildSettings(buildsettings, settings.platform, BuildSetting.commandLine);

			// invoke the compiler
			settings.compiler.invoke(buildsettings, settings.platform, settings.compileCallback, settings.toolWorkingDirectory);
		} else {
			// determine path for the temporary object file
			string tempobjname = buildsettings.targetName ~ getObjSuffix(settings.platform);
			NativePath tempobj = NativePath(buildsettings.targetPath) ~ tempobjname;

			// setup linker command line
			auto lbuildsettings = buildsettings;
			lbuildsettings.sourceFiles = lbuildsettings.sourceFiles.filter!(f => isLinkerFile(settings.platform, f)).array;
			if (generate_binary) settings.compiler.setTarget(lbuildsettings, settings.platform);
			settings.compiler.prepareBuildSettings(lbuildsettings, settings.platform, BuildSetting.commandLineSeparate|BuildSetting.sourceFiles);

			// setup compiler command line
			buildsettings.libs = null;
			buildsettings.lflags = null;
			if (generate_binary) buildsettings.addDFlags("-c", "-of"~tempobj.toNativeString());
			buildsettings.sourceFiles = buildsettings.sourceFiles.filter!(f => !isLinkerFile(settings.platform, f)).array;

			settings.compiler.prepareBuildSettings(buildsettings, settings.platform, BuildSetting.commandLine);

			settings.compiler.invoke(buildsettings, settings.platform, settings.compileCallback, settings.toolWorkingDirectory);

			if (generate_binary) {
				if (settings.tempBuild) {
					logInfo("Linking", Color.light_green, "%s => %s", buildsettings.targetName.color(Mode.bold), buildsettings.getTargetPath(settings));
				} else {
					logInfo("Linking", Color.light_green, "%s", buildsettings.targetName.color(Mode.bold));
				}
				settings.compiler.invokeLinker(lbuildsettings, settings.platform, [tempobj.toNativeString()], settings.linkCallback, settings.toolWorkingDirectory);
			}
		}
	}

	private void runTarget(NativePath exe_file_path, in BuildSettings buildsettings, string[] run_args, GeneratorSettings settings)
	{
		if (buildsettings.targetType == TargetType.executable) {
			auto cwd = settings.toolWorkingDirectory;
			auto runcwd = cwd;
			if (buildsettings.workingDirectory.length) {
				runcwd = NativePath(buildsettings.workingDirectory);
				if (!runcwd.absolute) runcwd = cwd ~ runcwd;
			}
			if (!exe_file_path.absolute) exe_file_path = cwd ~ exe_file_path;
			runPreRunCommands(m_project.rootPackage, m_project, settings, buildsettings);
			logInfo("Running", Color.green, "%s %s", exe_file_path.relativeTo(runcwd), run_args.join(" "));
			string[string] env;
			foreach (aa; [buildsettings.environments, buildsettings.runEnvironments])
				foreach (k, v; aa)
					env[k] = v;
			if (settings.runCallback) {
				auto res = execute([ exe_file_path.toNativeString() ] ~ run_args,
						   env, Config.none, size_t.max, runcwd.toNativeString());
				settings.runCallback(res.status, res.output);
				settings.targetExitStatus = res.status;
				runPostRunCommands(m_project.rootPackage, m_project, settings, buildsettings);
			} else {
				auto prg_pid = spawnProcess([ exe_file_path.toNativeString() ] ~ run_args,
								env, Config.none, runcwd.toNativeString());
				auto result = prg_pid.wait();
				settings.targetExitStatus = result;
				runPostRunCommands(m_project.rootPackage, m_project, settings, buildsettings);
				enforce(result == 0, "Program exited with code "~to!string(result));
			}
		} else
			enforce(false, "Target is a library. Skipping execution.");
	}

	private void runPreRunCommands(in Package pack, in Project proj, in GeneratorSettings settings,
		in BuildSettings buildsettings)
	{
		if (buildsettings.preRunCommands.length) {
			logInfo("Pre-run", Color.light_green, "Running commands...");
			runBuildCommands(CommandType.preRun, buildsettings.preRunCommands, pack, proj, settings, buildsettings);
		}
	}

	private void runPostRunCommands(in Package pack, in Project proj, in GeneratorSettings settings,
		in BuildSettings buildsettings)
	{
		if (buildsettings.postRunCommands.length) {
			logInfo("Post-run", Color.light_green, "Running commands...");
			runBuildCommands(CommandType.postRun, buildsettings.postRunCommands, pack, proj, settings, buildsettings);
		}
	}

	private void cleanupTemporaries()
	{
		foreach_reverse (f; m_temporaryFiles) {
			try {
				if (f.endsWithSlash) rmdir(f.toNativeString());
				else remove(f.toNativeString());
			} catch (Exception e) {
				logWarn("Failed to remove temporary file '%s': %s", f.toNativeString(), e.msg);
				logDiagnostic("Full error: %s", e.toString().sanitize);
			}
		}
		m_temporaryFiles = null;
	}
}

private NativePath getMainSourceFile(in Package prj)
{
	foreach (f; ["source/app.d", "src/app.d", "source/"~prj.name~".d", "src/"~prj.name~".d"])
		if (existsFile(prj.path ~ f))
			return prj.path ~ f;
	return prj.path ~ "source/app.d";
}

private NativePath getTargetPath(const scope ref BuildSettings bs, const scope ref GeneratorSettings settings)
{
	return NativePath(bs.targetPath) ~ settings.compiler.getTargetFileName(bs, settings.platform);
}

private string shrinkPath(NativePath path, NativePath base)
{
	auto orig = path.toNativeString();
	if (!path.absolute) return orig;
	version (Windows)
	{
		// avoid relative paths starting with `..\`: https://github.com/dlang/dub/issues/2143
		if (!path.startsWith(base)) return orig;
	}
	auto rel = path.relativeTo(base).toNativeString();
	return rel.length < orig.length ? rel : orig;
}

unittest {
	assert(shrinkPath(NativePath("/foo/bar/baz"), NativePath("/foo")) == NativePath("bar/baz").toNativeString());
	version (Windows)
		assert(shrinkPath(NativePath("/foo/bar/baz"), NativePath("/foo/baz")) == NativePath("/foo/bar/baz").toNativeString());
	else
		assert(shrinkPath(NativePath("/foo/bar/baz"), NativePath("/foo/baz")) == NativePath("../bar/baz").toNativeString());
	assert(shrinkPath(NativePath("/foo/bar/baz"), NativePath("/bar/")) == NativePath("/foo/bar/baz").toNativeString());
	assert(shrinkPath(NativePath("/foo/bar/baz"), NativePath("/bar/baz")) == NativePath("/foo/bar/baz").toNativeString());
}

unittest { // issue #1235 - pass no library files to compiler command line when building a static lib
	import dub.internal.vibecompat.data.json : parseJsonString;
	import dub.compilers.gdc : GDCCompiler;
	import dub.platform : determinePlatform;

	version (Windows) auto libfile = "bar.lib";
	else auto libfile = "bar.a";

	auto desc = parseJsonString(`{"name": "test", "targetType": "library", "sourceFiles": ["foo.d", "`~libfile~`"]}`);
	auto pack = new Package(desc, NativePath("/tmp/fooproject"));
	auto pman = new PackageManager(pack.path, NativePath("/tmp/foo/"), NativePath("/tmp/foo/"), false);
	auto prj = new Project(pman, pack);

	final static class TestCompiler : GDCCompiler {
		override void invoke(in BuildSettings settings, in BuildPlatform platform, void delegate(int, string) output_callback, NativePath cwd) {
			assert(!settings.dflags[].any!(f => f.canFind("bar")));
		}
		override void invokeLinker(in BuildSettings settings, in BuildPlatform platform, string[] objects, void delegate(int, string) output_callback, NativePath cwd) {
			assert(false);
		}
	}

	GeneratorSettings settings;
	settings.platform = BuildPlatform(determinePlatform(), ["x86"], "gdc", "test", 2075);
	settings.compiler = new TestCompiler;
	settings.config = "library";
	settings.buildType = "debug";
	settings.tempBuild = true;

	auto gen = new BuildGenerator(prj);
	gen.generate(settings);
}
