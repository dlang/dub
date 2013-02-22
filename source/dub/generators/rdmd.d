/**
	Generator for direct RDMD builds.
	
	Copyright: © 2013 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.generators.rdmd;

import dub.compilers.compiler;
import dub.generators.generator;
import dub.package_;
import dub.packagemanager;
import dub.project;

import std.array;
import std.conv;
import std.exception;
import std.file;
import std.string;
import stdx.process;

import vibecompat.core.file;
import vibecompat.core.log;
import vibecompat.inet.path;


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
		auto outfile = getBinName(m_project);
		auto mainsrc = getMainSourceFile(m_project);

		logDebug("Application output name is '%s'", outfile);

		// Create start script, which will be used by the calling bash/cmd script.
		// build "rdmd --force %DFLAGS% -I%~dp0..\source -Jviews -Isource @deps.txt %LIBS% source\app.d" ~ application arguments
		// or with "/" instead of "\"
		string[] flags = ["--force", "--build-only", "--compiler="~settings.compilerBinary];
		Path run_exe_file;
		if( !settings.run ){
			flags ~= "-of"~(m_project.binaryPath~outfile).toNativeString();
		} else {
			import std.random;
			auto rnd = to!string(uniform(uint.min, uint.max)) ~ "-";
			auto tmp = environment.get("TEMP");
			if( !tmp.length ) tmp = environment.get("TMP");
			if( !tmp.length ){
				version(Posix) tmp = "/tmp";
				else tmp = ".";
			}
			run_exe_file = Path(tmp~"/.rdmd/source/"~rnd~outfile);
			flags ~= "-of"~run_exe_file.toNativeString();
		}

		auto buildsettings = settings.buildSettings;
		m_project.addBuildSettings(buildsettings, settings.platform, settings.config);
		buildsettings.addDFlags(["-w"/*, "-property"*/]);
		string dflags = environment.get("DFLAGS");
		if( dflags ){
			settings.buildType = "$DFLAGS";
			buildsettings.addDFlags(dflags.split());
		} else {
			addBuildTypeFlags(buildsettings, settings.buildType);
		}

		settings.compiler.prepareBuildSettings(buildsettings, BuildSetting.commandLine);
		flags ~= buildsettings.dflags;
		flags ~= (mainsrc).toNativeString();

		if( settings.config.length ) logInfo("Building configuration "~settings.config~", build type "~settings.buildType);
		else logInfo("Building default configuration, build type "~settings.buildType);

		logInfo("Running %s", "rdmd " ~ join(flags, " "));
		auto rdmd_pid = spawnProcess("rdmd", flags);
		auto result = rdmd_pid.wait();
		enforce(result == 0, "Build command failed with exit code "~to!string(result));

		// TODO: move to a common place - this is not generator specific
		if( buildsettings.copyFiles.length ){
			logInfo("Copying files...");
			foreach( f; buildsettings.copyFiles ){
				auto src = Path(f);
				auto dst = (run_exe_file.empty ? m_project.binaryPath : run_exe_file.parentPath) ~ Path(f).head;
				logDebug("  %s to %s", src.toNativeString(), dst.toNativeString());
				try copyFile(src, dst, true);
				catch logWarn("Failed to copy to %s", dst.toNativeString());
			}
		}

		if( settings.run ){
			auto prg_pid = spawnProcess(run_exe_file.toNativeString(), settings.runArgs);
			result = prg_pid.wait();
			remove(run_exe_file.toNativeString());
			foreach( f; buildsettings.copyFiles )
				remove((run_exe_file.parentPath ~ Path(f).head).toNativeString());
			enforce(result == 0, "Program exited with code "~to!string(result));
		}
	}
}

private string getBinName(in Project prj)
{
	// take the project name as the base or fall back to "app"
	string ret = prj.name;
	if( ret.length == 0 ) ret ="app";
	version(Windows) { ret ~= ".exe"; }
	return ret;
} 

private Path getMainSourceFile(in Project prj)
{
	auto p = Path("source") ~ (prj.name ~ ".d");
	return existsFile(p) ? p : Path("source/app.d");
}

