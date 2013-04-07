/**
	Generator for MonoD project files
	
	Copyright: © 2013 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.generators.monod;

import dub.compilers.compiler;
import dub.generators.generator;
import dub.package_;
import dub.packagemanager;
import dub.project;
import dub.utils;

import std.algorithm;
import std.array;
import std.conv;
import std.format;
import std.uuid;
import std.exception;

import vibecompat.core.file;
import vibecompat.core.log;


// TODO: handle pre/post build commands

class MonoDGenerator : ProjectGenerator {
	private {
		Project m_app;
		PackageManager m_pkgMgr;
		string[string] m_projectUuids;
		bool m_singleProject = true;
		Config[] m_allConfigs;
	}
	
	this(Project app, PackageManager mgr)
	{
		m_app = app;
		m_pkgMgr = mgr;
		m_allConfigs ~= Config("Debug", "AnyCPU", "Any CPU");
	}
	
	void generateProject(GeneratorSettings settings)
	{
		auto buildsettings = settings.buildSettings;

		if( buildsettings.preGenerateCommands.length ){
			logInfo("Running pre-generate commands...");
			// TODO: pass full build settings for current configuration instead?
			runBuildCommands(buildsettings.preGenerateCommands, buildsettings);
		}

		logTrace("About to generate projects for %s, with %s direct dependencies.", m_app.mainPackage().name, m_app.mainPackage().dependencies().length);
		generateProjects(m_app.mainPackage(), settings);
		generateSolution(settings);

		if( buildsettings.postGenerateCommands.length ){
			logInfo("Running post-generate commands...");
			// TODO: pass full build settings for current configuration instead?
			runBuildCommands(buildsettings.postGenerateCommands, buildsettings);
		}
	}
	
	private void generateSolution(GeneratorSettings settings)
	{
		auto sln = openFile(m_app.mainPackage().name ~ ".sln", FileMode.CreateTrunc);
		scope(exit) sln.close();

		// Writing solution file
		logTrace("About to write to .sln file.");

		// Solution header
		sln.put('\n');
		sln.put("Microsoft Visual Studio Solution File, Format Version 11.00\n");
		sln.put("# Visual Studio 2010\n");

		generateSolutionEntry(sln, settings, m_app.mainPackage);
		if( !m_singleProject )
			performOnDependencies(m_app.mainPackage, pack => generateSolutionEntry(sln, settings, pack));
		
		sln.put("Global\n");

		// configuration platforms
		sln.put("\tGlobalSection(SolutionConfigurationPlatforms) = preSolution\n");
		foreach(config; m_allConfigs)
			sln.formattedWrite("\t\t%s|%s = %s|%s\n", config.configName, config.platformName2,
				config.configName, config.platformName2);
		sln.put("\tEndGlobalSection\n");

		// configuration platforms per project
		sln.put("\tGlobalSection(ProjectConfigurationPlatforms) = postSolution\n");
		auto projectUuid = guid(m_app.mainPackage.name);
		foreach(config; m_allConfigs)
			foreach(s; ["ActiveCfg", "Build.0"])
				sln.formattedWrite("\t\t%s.%s|%s.%s = %s|%s\n",
					projectUuid, config.configName, config.platformName2, s,
					config.configName, config.platformName2);
		// TODO: for all dependencies
		sln.put("\tEndGlobalSection\n");
		
		// solution properties
		sln.put("\tGlobalSection(SolutionProperties) = preSolution\n");
		sln.put("\t\tHideSolutionNode = FALSE\n");
		sln.put("\tEndGlobalSection\n");

		// monodevelop properties
		sln.put("\tGlobalSection(MonoDevelopProperties) = preSolution\n");
		sln.formattedWrite("\t\tStartupItem = %s\n", "monodtest/monodtest.dproj");
		sln.put("\tEndGlobalSection\n");

		sln.put("EndGlobal\n");
	}
	
	private void generateSolutionEntry(RangeFile ret, GeneratorSettings settings, const Package pack)
	{
		auto projUuid = generateUUID();
		auto projName = pack.name;
		auto projPath = pack.name ~ ".dproj";
		auto projectUuid = guid(projName);
		
		// Write project header, like so
		// Project("{002A2DE9-8BB6-484D-9802-7E4AD4084715}") = "derelict", "..\inbase\source\derelict.visualdproj", "{905EF5DA-649E-45F9-9C15-6630AA815ACB}"
		ret.formattedWrite("Project(\"%s\") = \"%s\", \"%s\", \"%s\"\n",
			projUuid, projName, projPath, projectUuid);

		if( !m_singleProject ){
			if(pack.dependencies.length > 0) {
				ret.put("	ProjectSection(ProjectDependencies) = postProject\n");
				foreach(id, dependency; pack.dependencies) {
					// TODO: clarify what "uuid = uuid" should mean
					auto uuid = guid(id);
					ret.formattedWrite("		%s = %s\n", uuid, uuid);
				}
				ret.put("	EndProjectSection\n");
			}
		}

		ret.put("EndProject\n");
	}

	private void generateProjects(in Package pack, GeneratorSettings settings)
	{
		bool[const(Package)] visited;

		void generateRec(in Package p){
			if( p in visited ) return;
			visited[p] = true;

			generateProject(p, settings);

			if( !m_singleProject )
				performOnDependencies(p, &generateRec);
		}
		generateRec(pack);
	}
		
	private void generateProject(in Package pack, GeneratorSettings settings)
	{
		logTrace("About to write to '%s.dproj' file", pack.name);
		auto sln = openFile(pack.name ~ ".dproj", FileMode.CreateTrunc);
		scope(exit) sln.close();

		sln.put("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n");
		sln.put("<Project DefaultTargets=\"Build\" ToolsVersion=\"4.0\" xmlns=\"http://schemas.microsoft.com/developer/msbuild/2003\">\n");
		// TODO: property groups

		auto projName = pack.name;

		auto buildsettings = settings.buildSettings;
		m_app.addBuildSettings(buildsettings, settings.platform, m_app.getDefaultConfiguration(settings.platform));

		// Mono-D does not have a setting for string import paths
	    settings.compiler.prepareBuildSettings(buildsettings, BuildSetting.all & ~BuildSetting.stringImportPaths);

		sln.put("  <PropertyGroup>\n");
	    sln.put("    <Configuration Condition=\" '$(Configuration)' == '' \">Debug</Configuration>\n");
    	sln.put("    <Platform Condition=\" '$(Platform)' == '' \">AnyCPU</Platform>\n");
    	sln.put("    <ProductVersion>10.0.0</ProductVersion>\n");
    	sln.put("    <SchemaVersion>2.0</SchemaVersion>\n");
    	sln.formattedWrite("    <ProjectGuid>%s</ProjectGuid>\n", guid(pack.name));
    	sln.put("    <PreferOneStepBuild>True</PreferOneStepBuild>\n");
    	sln.put("    <UseDefaultCompiler>True</UseDefaultCompiler>\n");
    	sln.put("    <IncrementalLinking>True</IncrementalLinking>\n");
    	sln.put("    <Compiler>DMD2</Compiler>\n");
    	if( !buildsettings.versions.empty ){
			sln.put("    <VersionIds>\n");
			sln.put("      <VersionIds>\n");
			foreach(ver; buildsettings.versions)
				sln.formattedWrite("        <String>%s</String>\n", ver);
			sln.put("      </VersionIds>\n");
			sln.put("    </VersionIds>\n");
		}
		if( !buildsettings.importPaths.empty ){
	    	sln.put("    <Includes>\n");
	    	sln.put("      <Includes>\n");
	    	foreach(dir; buildsettings.importPaths)
	    		sln.formattedWrite("        <Path>%s</Path>\n", dir);
	    	sln.put("      </Includes>\n");
	    	sln.put("    </Includes>\n");
	    }
	    if( !buildsettings.libs.empty ){
	    	sln.put("    <Libs>\n");
	    	sln.put("      <Libs>\n");
	    	foreach(dir; buildsettings.libs)
	    		sln.formattedWrite("        <Lib>%s</Lib>\n", settings.platform.platform.canFind("windows") ? dir ~ ".lib" : dir);
	    	sln.put("      </Libs>\n");
	    	sln.put("    </Libs>\n");
	    }
		sln.formattedWrite("    <ExtraCompilerArguments>%s</ExtraCompilerArguments>\n", buildsettings.dflags.join(" "));
		sln.formattedWrite("    <ExtraLinkerArguments>%s</ExtraLinkerArguments>\n", buildsettings.lflags.join(" "));
		sln.put("  </PropertyGroup>\n");

		void generateProperties(Config config)
		{
			sln.formattedWrite("  <PropertyGroup Condition=\" '$(Configuration)|$(Platform)' == '%s|%s' \">\n",
				config.configName, config.platformName);
			
    		sln.put("    <DebugSymbols>True</DebugSymbols>\n");
    		auto outpath = Path(buildsettings.targetPath).toNativeString();
			sln.formattedWrite("    <OutputPath>%s</OutputPath>\n", outpath.length ? outpath : ".");
			sln.put("    <Externalconsole>True</Externalconsole>\n");
 			sln.put("    <Target>Executable</Target>\n");
    		sln.formattedWrite("    <OutputName>%s</OutputName>\n", buildsettings.targetName);
			sln.put("    <UnittestMode>False</UnittestMode>\n");
			sln.formattedWrite("    <ObjectsDirectory>%s</ObjectsDirectory>\n", (Path("obj/")~config.configName).toNativeString());
			sln.put("    <DebugLevel>0</DebugLevel>\n");
			sln.put("  </PropertyGroup>\n");
		}

		foreach(config; m_allConfigs)
			generateProperties(config);


		bool[const(Package)] visited;
		void generateSourceEntry(Path path, Path base_path, bool compile = true)
		{
			auto rel_path = path.relativeTo(pack.path);
			rel_path.normalize();

			Path pretty_path;
			foreach (i; 0 .. rel_path.length)
				if (rel_path[i] != "..") {
					pretty_path = rel_path[i .. $];
					break;
				}
			string kind = compile ? "Compile" : "None";

			if (base_path == pretty_path) {
				sln.formattedWrite("    <%s Include=\"%s\" />\n", kind, rel_path.toNativeString());
			} else {
				sln.formattedWrite("    <%s Include=\"%s\">\n", kind, rel_path.toNativeString());
				sln.formattedWrite("      <Link>%s</Link>\n", pretty_path.toNativeString());
				sln.formattedWrite("    </%s>\n", kind);
			}
		}

		sln.put("  <ItemGroup>\n");
		// add source files
		foreach (s; buildsettings.sourceFiles) {
			auto sp = Path(s);
			if (!sp.absolute) sp = pack.path ~ sp;
			generateSourceEntry(sp, pack.path);
		}
		// add package.json files
		foreach (p; m_app.getTopologicalPackageList())
			generateSourceEntry(p.packageInfoFile, pack.path, false);
		sln.put("  </ItemGroup>\n");
		sln.put("</Project>");
	}
		
	void performOnDependencies(const Package main, void delegate(const Package pack) op)
	{
		bool[const(Package)] visited;
		void perform_rec(const Package parent_pack){
			foreach(id, dependency; parent_pack.dependencies){
				logDebug("Retrieving package %s from package manager.", id);
				auto pack = m_pkgMgr.getBestPackage(id, dependency);
				if( pack in visited ) continue;
				visited[pack] = true;
				if(pack is null) {
				 	logWarn("Package %s (%s) could not be retrieved continuing...", id, to!string(dependency));
					continue;
				}
				logDebug("Performing on retrieved package %s", pack.name);
				op(pack);
				perform_rec(pack);
			}
		}

		perform_rec(main);
	}
	
	string generateUUID()
	const {
		return "{" ~ randomUUID().toString() ~ "}";
	}
	
	string guid(string projectName)
	{
		if(projectName !in m_projectUuids)
			m_projectUuids[projectName] = generateUUID();
		return m_projectUuids[projectName];
	}
}

struct Config {
	string configName;
	string platformName;
	string platformName2;
}