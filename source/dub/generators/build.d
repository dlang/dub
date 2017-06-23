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
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.inet.path;
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

version(Windows) enum objSuffix = ".obj";
else enum objSuffix = ".o";

class BuildGenerator : ProjectGenerator {
	private {
		PackageManager m_packageMan;
		Path[] m_temporaryFiles;
		Path m_targetExecutablePath;
	}

	this(Project project)
	{
		super(project);
		m_packageMan = project.packageManager;
	}

	override void generateTargets(GeneratorSettings settings, in TargetInfo[string] targets)
	{
		scope (exit) cleanupTemporaries();

		logInfo("Performing \"%s\" build using %s for %-(%s, %).",
			settings.buildType, settings.platform.compilerBinary, settings.platform.architecture);

		bool any_cached = false;

		Path[string] target_paths;

		bool[string] visited;
		void buildTargetRec(string target)
		{
			if (target in visited) return;
			visited[target] = true;

			auto ti = targets[target];

			foreach (dep; ti.dependencies)
				buildTargetRec(dep);

			Path[] additional_dep_files;
			auto bs = ti.buildSettings.dup;
			foreach (ldep; ti.linkDependencies) {
				auto dbs = targets[ldep].buildSettings;
				if (bs.targetType != TargetType.staticLibrary && !(bs.options & BuildOption.syntaxOnly)) {
					bs.addSourceFiles(target_paths[ldep].toNativeString());
				} else {
					additional_dep_files ~= target_paths[ldep];
				}
			}
			Path tpath;
			if (buildTarget(settings, bs, ti.pack, ti.config, ti.packages, additional_dep_files, tpath))
				any_cached = true;
			target_paths[target] = tpath;
		}

		// build all targets
		auto root_ti = targets[m_project.rootPackage.name];
		if (settings.rdmd || root_ti.buildSettings.targetType == TargetType.staticLibrary) {
			// RDMD always builds everything at once and static libraries don't need their
			// dependencies to be built
			Path tpath;
			buildTarget(settings, root_ti.buildSettings.dup, m_project.rootPackage, root_ti.config, root_ti.packages, null, tpath);
		} else {
			buildTargetRec(m_project.rootPackage.name);

			if (any_cached) {
				logInfo("To force a rebuild of up-to-date targets, run again with --force.");
			}
		}
	}

	override void performPostGenerateActions(GeneratorSettings settings, in TargetInfo[string] targets)
	{
		// run the generated executable
		auto buildsettings = targets[m_project.rootPackage.name].buildSettings.dup;
		if (settings.run && !(buildsettings.options & BuildOption.syntaxOnly)) {
			Path exe_file_path;
			if (m_targetExecutablePath.empty)
				exe_file_path = getTargetPath(buildsettings, settings);
			else
				exe_file_path = m_targetExecutablePath ~ settings.compiler.getTargetFileName(buildsettings, settings.platform);
			runTarget(exe_file_path, buildsettings, settings.runArgs, settings);
		}
	}

	private bool buildTarget(GeneratorSettings settings, BuildSettings buildsettings, in Package pack, string config, in Package[] packages, in Path[] additional_dep_files, out Path target_path)
	{
		auto cwd = Path(getcwd());
		bool generate_binary = !(buildsettings.options & BuildOption.syntaxOnly);

		auto build_id = computeBuildID(config, buildsettings, settings);

		// make all paths relative to shrink the command line
		string makeRelative(string path) { return shrinkPath(Path(path), cwd); }
		foreach (ref f; buildsettings.sourceFiles) f = makeRelative(f);
		foreach (ref p; buildsettings.importPaths) p = makeRelative(p);
		foreach (ref p; buildsettings.stringImportPaths) p = makeRelative(p);

		// perform the actual build
		bool cached = false;
		if (settings.rdmd) performRDMDBuild(settings, buildsettings, pack, config, target_path);
		else if (settings.direct || !generate_binary) performDirectBuild(settings, buildsettings, pack, config, target_path);
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
			logInfo("Running post-build commands...");
			runBuildCommands(buildsettings.postBuildCommands, pack, m_project, settings, buildsettings);
		}

		return cached;
	}

	private bool performCachedBuild(GeneratorSettings settings, BuildSettings buildsettings, in Package pack, string config,
		string build_id, in Package[] packages, in Path[] additional_dep_files, out Path target_binary_path)
	{
		auto cwd = Path(getcwd());

		Path target_path;
		if (settings.tempBuild) {
			string packageName = pack.basePackage is null ? pack.name : pack.basePackage.name;
			m_targetExecutablePath = target_path = getTempDir() ~ format(".dub/build/%s-%s/%s/", packageName, pack.version_, build_id);
		}
		else target_path = pack.path ~ format(".dub/build/%s/", build_id);

		if (!settings.force && isUpToDate(target_path, buildsettings, settings, pack, packages, additional_dep_files)) {
			logInfo("%s %s: target for configuration \"%s\" is up to date.", pack.name, pack.version_, config);
			logDiagnostic("Using existing build in %s.", target_path.toNativeString());
			target_binary_path = target_path ~ settings.compiler.getTargetFileName(buildsettings, settings.platform);
			if (!settings.tempBuild)
				copyTargetFile(target_path, buildsettings, settings);
			return true;
		}

		if (!isWritableDir(target_path, true)) {
			if (!settings.tempBuild)
				logInfo("Build directory %s is not writable. Falling back to direct build in the system's temp folder.", target_path.relativeTo(cwd).toNativeString());
			performDirectBuild(settings, buildsettings, pack, config, target_path);
			return false;
		}

		// determine basic build properties
		auto generate_binary = !(buildsettings.options & BuildOption.syntaxOnly);

		logInfo("%s %s: building configuration \"%s\"...", pack.name, pack.version_, config);

		if( buildsettings.preBuildCommands.length ){
			logInfo("Running pre-build commands...");
			runBuildCommands(buildsettings.preBuildCommands, pack, m_project, settings, buildsettings);
		}

		// override target path
		auto cbuildsettings = buildsettings;
		cbuildsettings.targetPath = shrinkPath(target_path, cwd);
		buildWithCompiler(settings, cbuildsettings);
		target_binary_path = getTargetPath(cbuildsettings, settings);

		if (!settings.tempBuild)
			copyTargetFile(target_path, buildsettings, settings);

		return false;
	}

	private void performRDMDBuild(GeneratorSettings settings, ref BuildSettings buildsettings, in Package pack, string config, out Path target_path)
	{
		auto cwd = Path(getcwd());
		//Added check for existence of [AppNameInPackagejson].d
		//If exists, use that as the starting file.
		Path mainsrc;
		if (buildsettings.mainSourceFile.length) {
			mainsrc = Path(buildsettings.mainSourceFile);
			if (!mainsrc.absolute) mainsrc = pack.path ~ mainsrc;
		} else {
			mainsrc = getMainSourceFile(pack);
			logWarn(`Package has no "mainSourceFile" defined. Using best guess: %s`, mainsrc.relativeTo(pack.path).toNativeString());
		}

		// do not pass all source files to RDMD, only the main source file
		buildsettings.sourceFiles = buildsettings.sourceFiles.filter!(s => !s.endsWith(".d"))().array();
		settings.compiler.prepareBuildSettings(buildsettings, BuildSetting.commandLine);

		auto generate_binary = !buildsettings.dflags.canFind("-o-");

		// Create start script, which will be used by the calling bash/cmd script.
		// build "rdmd --force %DFLAGS% -I%~dp0..\source -Jviews -Isource @deps.txt %LIBS% source\app.d" ~ application arguments
		// or with "/" instead of "\"
		bool tmp_target = false;
		if (generate_binary) {
			if (settings.tempBuild || (settings.run && !isWritableDir(Path(buildsettings.targetPath), true))) {
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
			logInfo("Running pre-build commands...");
			runCommands(buildsettings.preBuildCommands);
		}

		logInfo("%s %s: building configuration \"%s\"...", pack.name, pack.version_, config);

		logInfo("Running rdmd...");
		logDiagnostic("rdmd %s", join(flags, " "));
		auto rdmd_pid = spawnProcess("rdmd" ~ flags);
		auto result = rdmd_pid.wait();
		enforce(result == 0, "Build command failed with exit code "~to!string(result));

		if (tmp_target) {
			m_temporaryFiles ~= target_path;
			foreach (f; buildsettings.copyFiles)
				m_temporaryFiles ~= Path(buildsettings.targetPath).parentPath ~ Path(f).head;
		}
	}

	private void performDirectBuild(GeneratorSettings settings, ref BuildSettings buildsettings, in Package pack, string config, out Path target_path)
	{
		auto cwd = Path(getcwd());

		auto generate_binary = !(buildsettings.options & BuildOption.syntaxOnly);
		auto is_static_library = buildsettings.targetType == TargetType.staticLibrary || buildsettings.targetType == TargetType.library;

		// make file paths relative to shrink the command line
		foreach (ref f; buildsettings.sourceFiles) {
			auto fp = Path(f);
			if( fp.absolute ) fp = fp.relativeTo(cwd);
			f = fp.toNativeString();
		}

		logInfo("%s %s: building configuration \"%s\"...", pack.name, pack.version_, config);

		// make all target/import paths relative
		string makeRelative(string path) {
			auto p = Path(path);
			// storing in a separate temprary to work around #601
			auto prel = p.absolute ? p.relativeTo(cwd) : p;
			return prel.toNativeString();
		}
		buildsettings.targetPath = makeRelative(buildsettings.targetPath);
		foreach (ref p; buildsettings.importPaths) p = makeRelative(p);
		foreach (ref p; buildsettings.stringImportPaths) p = makeRelative(p);

		bool is_temp_target = false;
		if (generate_binary) {
			if (settings.tempBuild || (settings.run && !isWritableDir(Path(buildsettings.targetPath), true))) {
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
			logInfo("Running pre-build commands...");
			runBuildCommands(buildsettings.preBuildCommands, pack, m_project, settings, buildsettings);
		}

		buildWithCompiler(settings, buildsettings);

		if (is_temp_target) {
			m_temporaryFiles ~= target_path;
			foreach (f; buildsettings.copyFiles)
				m_temporaryFiles ~= Path(buildsettings.targetPath).parentPath ~ Path(f).head;
		}
	}

	private string computeBuildID(string config, in BuildSettings buildsettings, GeneratorSettings settings)
	{
		import std.digest.digest;
		import std.digest.md;
		import std.bitmanip;

		MD5 hash;
		hash.start();
		void addHash(in string[] strings...) { foreach (s; strings) { hash.put(cast(ubyte[])s); hash.put(0); } hash.put(0); }
		void addHashI(int value) { hash.put(nativeToLittleEndian(value)); }
		addHash(buildsettings.versions);
		addHash(buildsettings.debugVersions);
		//addHash(buildsettings.versionLevel);
		//addHash(buildsettings.debugLevel);
		addHash(buildsettings.dflags);
		addHash(buildsettings.lflags);
		addHash((cast(uint)buildsettings.options).to!string);
		addHash(buildsettings.stringImportPaths);
		addHash(settings.platform.architecture);
		addHash(settings.platform.compilerBinary);
		addHash(settings.platform.compiler);
		addHashI(settings.platform.frontendVersion);
		auto hashstr = hash.finish().toHexString().idup;

		return format("%s-%s-%s-%s-%s_%s-%s", config, settings.buildType,
			settings.platform.platform.join("."),
			settings.platform.architecture.join("."),
			settings.platform.compiler, settings.platform.frontendVersion, hashstr);
	}

	private void copyTargetFile(Path build_path, BuildSettings buildsettings, GeneratorSettings settings)
	{
		auto filename = settings.compiler.getTargetFileName(buildsettings, settings.platform);
		auto src = build_path ~ filename;
		logDiagnostic("Copying target from %s to %s", src.toNativeString(), buildsettings.targetPath);
		if (!existsFile(Path(buildsettings.targetPath)))
			mkdirRecurse(buildsettings.targetPath);
		hardLinkFile(src, Path(buildsettings.targetPath) ~ filename, true);
	}

	private bool isUpToDate(Path target_path, BuildSettings buildsettings, GeneratorSettings settings, in Package main_pack, in Package[] packages, in Path[] additional_dep_files)
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
		// TODO: add library files
		foreach (p; packages)
			allfiles ~= (p.recipePath != Path.init ? p : p.basePackage).recipePath.toNativeString();
		foreach (f; additional_dep_files) allfiles ~= f.toNativeString();
		if (main_pack is m_project.rootPackage && m_project.rootPackage.getAllDependencies().length > 0)
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

	static string pathToObjName(string path)
	{
		import std.path : buildNormalizedPath, dirSeparator, stripDrive;
		return stripDrive(buildNormalizedPath(getcwd(), path~objSuffix))[1..$].replace(dirSeparator, ".");
	}

	/// Compile a single source file (srcFile), and write the object to objName.
	static string compileUnit(string srcFile, string objName, BuildSettings bs, GeneratorSettings gs) {
		Path tempobj = Path(bs.targetPath)~objName;
		string objPath = tempobj.toNativeString();
		bs.libs = null;
		bs.lflags = null;
		bs.sourceFiles = [ srcFile ];
		bs.targetType = TargetType.object;
		gs.compiler.prepareBuildSettings(bs, BuildSetting.commandLine);
		gs.compiler.setTarget(bs, gs.platform, objPath);
		gs.compiler.invoke(bs, gs.platform, gs.compileCallback);
		return objPath;
	}

	private void buildWithCompiler(GeneratorSettings settings, BuildSettings buildsettings)
	{
		auto generate_binary = !(buildsettings.options & BuildOption.syntaxOnly);
		auto is_static_library = buildsettings.targetType == TargetType.staticLibrary || buildsettings.targetType == TargetType.library;

		Path target_file;
		scope (failure) {
			logDiagnostic("FAIL %s %s %s" , buildsettings.targetPath, buildsettings.targetName, buildsettings.targetType);
			auto tpath = getTargetPath(buildsettings, settings);
			if (generate_binary && existsFile(tpath))
				removeFile(tpath);
		}
		if (settings.buildMode == BuildMode.singleFile && generate_binary) {
			import std.parallelism, std.range : walkLength;

			auto lbuildsettings = buildsettings;
			auto srcs = buildsettings.sourceFiles.filter!(f => !isLinkerFile(f));
			auto objs = new string[](srcs.walkLength);

			void compileSource(size_t i, string src) {
				logInfo("Compiling %s...", src);
				objs[i] = compileUnit(src, pathToObjName(src), buildsettings, settings);
			}

			if (settings.parallelBuild) {
				foreach (i, src; srcs.parallel(1)) compileSource(i, src);
			} else {
				foreach (i, src; srcs.array) compileSource(i, src);
			}

			logInfo("Linking...");
			lbuildsettings.sourceFiles = is_static_library ? [] : lbuildsettings.sourceFiles.filter!(f=> f.isLinkerFile()).array;
			settings.compiler.setTarget(lbuildsettings, settings.platform);
			settings.compiler.prepareBuildSettings(lbuildsettings, BuildSetting.commandLineSeparate|BuildSetting.sourceFiles);
			settings.compiler.invokeLinker(lbuildsettings, settings.platform, objs, settings.linkCallback);

		/*
			NOTE: for DMD experimental separate compile/link is used, but this is not yet implemented
			      on the other compilers. Later this should be integrated somehow in the build process
			      (either in the dub.json, or using a command line flag)
		*/
		} else if (generate_binary && (settings.buildMode == BuildMode.allAtOnce || settings.compiler.name != "dmd" || is_static_library)) {
			// don't include symbols of dependencies (will be included by the top level target)
			if (is_static_library) buildsettings.sourceFiles = buildsettings.sourceFiles.filter!(f => !f.isLinkerFile()).array;

			// setup for command line
			settings.compiler.setTarget(buildsettings, settings.platform);
			settings.compiler.prepareBuildSettings(buildsettings, BuildSetting.commandLine);

			// invoke the compiler
			settings.compiler.invoke(buildsettings, settings.platform, settings.compileCallback);
		} else {
			// determine path for the temporary object file
			string tempobjname = buildsettings.targetName ~ objSuffix;
			Path tempobj = Path(buildsettings.targetPath) ~ tempobjname;

			// setup linker command line
			auto lbuildsettings = buildsettings;
			lbuildsettings.sourceFiles = lbuildsettings.sourceFiles.filter!(f => isLinkerFile(f)).array;
			if (generate_binary) settings.compiler.setTarget(lbuildsettings, settings.platform);
			settings.compiler.prepareBuildSettings(lbuildsettings, BuildSetting.commandLineSeparate|BuildSetting.sourceFiles);

			// setup compiler command line
			buildsettings.libs = null;
			buildsettings.lflags = null;
			if (generate_binary) buildsettings.addDFlags("-c", "-of"~tempobj.toNativeString());
			buildsettings.sourceFiles = buildsettings.sourceFiles.filter!(f => !isLinkerFile(f)).array;

			settings.compiler.prepareBuildSettings(buildsettings, BuildSetting.commandLine);

			settings.compiler.invoke(buildsettings, settings.platform, settings.compileCallback);

			if (generate_binary) {
				logInfo("Linking...");
				settings.compiler.invokeLinker(lbuildsettings, settings.platform, [tempobj.toNativeString()], settings.linkCallback);
			}
		}
	}

	private void runTarget(Path exe_file_path, in BuildSettings buildsettings, string[] run_args, GeneratorSettings settings)
	{
		if (buildsettings.targetType == TargetType.executable) {
			auto cwd = Path(getcwd());
			auto runcwd = cwd;
			if (buildsettings.workingDirectory.length) {
				runcwd = Path(buildsettings.workingDirectory);
				if (!runcwd.absolute) runcwd = cwd ~ runcwd;
				logDiagnostic("Switching to %s", runcwd.toNativeString());
				chdir(runcwd.toNativeString());
			}
			scope(exit) chdir(cwd.toNativeString());
			if (!exe_file_path.absolute) exe_file_path = cwd ~ exe_file_path;
			auto exe_path_string = exe_file_path.relativeTo(runcwd).toNativeString();
			version (Posix) {
				if (!exe_path_string.startsWith(".") && !exe_path_string.startsWith("/"))
					exe_path_string = "./" ~ exe_path_string;
			}
			version (Windows) {
				if (!exe_path_string.startsWith(".") && (exe_path_string.length < 2 || exe_path_string[1] != ':'))
					exe_path_string = ".\\" ~ exe_path_string;
			}
			logInfo("Running %s %s", exe_path_string, run_args.join(" "));
			if (settings.runCallback) {
				auto res = execute(exe_path_string ~ run_args);
				settings.runCallback(res.status, res.output);
			} else {
				auto prg_pid = spawnProcess(exe_path_string ~ run_args);
				auto result = prg_pid.wait();
				enforce(result == 0, "Program exited with code "~to!string(result));
			}
		} else
			enforce(false, "Target is a library. Skipping execution.");
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

private Path getMainSourceFile(in Package prj)
{
	foreach (f; ["source/app.d", "src/app.d", "source/"~prj.name~".d", "src/"~prj.name~".d"])
		if (existsFile(prj.path ~ f))
			return prj.path ~ f;
	return prj.path ~ "source/app.d";
}

private Path getTargetPath(in ref BuildSettings bs, in ref GeneratorSettings settings)
{
	return Path(bs.targetPath) ~ settings.compiler.getTargetFileName(bs, settings.platform);
}

private string shrinkPath(Path path, Path base)
{
	auto orig = path.toNativeString();
	if (!path.absolute) return orig;
	auto ret = path.relativeTo(base).toNativeString();
	return ret.length < orig.length ? ret : orig;
}

unittest {
	assert(shrinkPath(Path("/foo/bar/baz"), Path("/foo")) == Path("bar/baz").toNativeString());
	assert(shrinkPath(Path("/foo/bar/baz"), Path("/foo/baz")) == Path("../bar/baz").toNativeString());
	assert(shrinkPath(Path("/foo/bar/baz"), Path("/bar/")) == Path("/foo/bar/baz").toNativeString());
	assert(shrinkPath(Path("/foo/bar/baz"), Path("/bar/baz")) == Path("/foo/bar/baz").toNativeString());
}

unittest { // issue #1235 - pass no library files to compiler command line when building a static lib
	import dub.internal.vibecompat.data.json : parseJsonString;
	import dub.compilers.gdc : GDCCompiler;
	import dub.platform : determinePlatform;

	version (Windows) auto libfile = "bar.lib";
	else auto libfile = "bar.a";

	auto desc = parseJsonString(`{"name": "test", "targetType": "library", "sourceFiles": ["foo.d", "`~libfile~`"]}`);
	auto pack = new Package(desc, Path("/tmp/fooproject"));
	auto pman = new PackageManager(Path("/tmp/foo/"), Path("/tmp/foo/"), false);
	auto prj = new Project(pman, pack);

	final static class TestCompiler : GDCCompiler {
		override void invoke(in BuildSettings settings, in BuildPlatform platform, void delegate(int, string) output_callback) {
			assert(!settings.dflags[].any!(f => f.canFind("bar")));
		}
		override void invokeLinker(in BuildSettings settings, in BuildPlatform platform, string[] objects, void delegate(int, string) output_callback) {
			assert(false);
		}
	}

	auto comp = new TestCompiler;

	GeneratorSettings settings;
	settings.platform = BuildPlatform(determinePlatform(), ["x86"], "gdc", "test", 2075);
	settings.compiler = new TestCompiler;
	settings.config = "library";
	settings.buildType = "debug";
	settings.tempBuild = true;

	auto gen = new BuildGenerator(prj);
	gen.generate(settings);
}
