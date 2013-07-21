/**
	Generator for direct RDMD builds.
	
	Copyright: © 2013 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.generators.rdmd;

import dub.compilers.compiler;
import dub.generators.generator;
import dub.internal.std.process;
import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.inet.path;
import dub.package_;
import dub.packagemanager;
import dub.project;
import dub.utils;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.file;
import std.string;


class RdmdGenerator : ProjectGenerator {
	private {
		Project m_project;
		PackageManager m_pkgMgr;
	}
	
	this(Project app, PackageManager mgr)
	{
		m_project = app;
		m_pkgMgr = mgr;
	}
	
	void generateProject(GeneratorSettings settings)
	{
		//Added check for existance of [AppNameInPackagejson].d
		//If exists, use that as the starting file.
		auto mainsrc = getMainSourceFile(m_project);

		auto buildsettings = settings.buildSettings;
		m_project.addBuildSettings(buildsettings, settings.platform, settings.config);
		m_project.addBuildTypeSettings(buildsettings, settings.platform, settings.buildType);
		// do not pass all source files to RDMD, only the main source file
		buildsettings.sourceFiles = buildsettings.sourceFiles.filter!(s => !s.endsWith(".d"))().array();
		settings.compiler.prepareBuildSettings(buildsettings, BuildSetting.commandLine);

		auto generate_binary = !buildsettings.dflags.canFind("-o-");

		// Create start script, which will be used by the calling bash/cmd script.
		// build "rdmd --force %DFLAGS% -I%~dp0..\source -Jviews -Isource @deps.txt %LIBS% source\app.d" ~ application arguments
		// or with "/" instead of "\"
		Path run_exe_file;
		if( generate_binary ){
			if( settings.run ){
				import std.random;
				auto rnd = to!string(uniform(uint.min, uint.max)) ~ "-";
				auto tmp = environment.get("TEMP");
				if( !tmp.length ) tmp = environment.get("TMP");
				if( !tmp.length ){
					version(Posix) tmp = "/tmp";
					else tmp = ".";
				}
				buildsettings.targetPath = (Path(tmp)~".rdmd/source/").toNativeString();
				buildsettings.targetName = rnd ~ buildsettings.targetName;
				run_exe_file = Path(buildsettings.targetPath) ~ getTargetFileName(buildsettings, settings.platform);
			}
			settings.compiler.setTarget(buildsettings, settings.platform);
		}

		logDiagnostic("Application output name is '%s'", getTargetFileName(buildsettings, settings.platform));

		string[] flags = ["--build-only", "--compiler="~settings.compilerBinary];
		flags ~= buildsettings.dflags;
		flags ~= (mainsrc).toNativeString();

		prepareGeneration(buildsettings);
		finalizeGeneration(buildsettings, generate_binary);

		if( buildsettings.preBuildCommands.length ){
			logInfo("Running pre-build commands...");
			runCommands(buildsettings.preBuildCommands);
		}

		if( settings.config.length ) logInfo("Building configuration "~settings.config~", build type "~settings.buildType);
		else logInfo("Building default configuration, build type "~settings.buildType);

		logInfo("Running rdmd...");
		logDiagnostic("rdmd %s", join(flags, " "));
		auto rdmd_pid = spawnProcess("rdmd" ~ flags);
		auto result = rdmd_pid.wait();
		enforce(result == 0, "Build command failed with exit code "~to!string(result));

		if( buildsettings.postBuildCommands.length ){
			logInfo("Running post-build commands...");
			runCommands(buildsettings.postBuildCommands);
		}

		if (generate_binary && settings.run) {
			if (buildsettings.targetType == TargetType.executable) {
				auto cwd = Path(getcwd());
				if (buildsettings.workingDirectory.length) {
					logDiagnostic("Switching to %s", (cwd ~ buildsettings.workingDirectory).toNativeString());
					chdir((cwd ~ buildsettings.workingDirectory).toNativeString());
				}
				scope(exit) chdir(cwd.toNativeString());
				logInfo("Running %s...", run_exe_file.toNativeString());
				auto prg_pid = spawnProcess(run_exe_file.toNativeString() ~ settings.runArgs);
				result = prg_pid.wait();
				remove(run_exe_file.toNativeString());
				foreach( f; buildsettings.copyFiles )
					remove((run_exe_file.parentPath ~ Path(f).head).toNativeString());
				enforce(result == 0, "Program exited with code "~to!string(result));
			} else logInfo("Target is a library. Skipping execution.");
		}
	}
}

private Path getMainSourceFile(in Project prj)
{
	foreach( f; ["source/app.d", "src/app.d", "source/"~prj.name~".d", "src/"~prj.name~".d"])
		if( exists(f) )
			return Path(f);
	return Path("source/app.d");
}
