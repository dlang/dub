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

import std.algorithm;
import std.array;
import std.conv;
import std.format;
import std.uuid;
import std.exception;

import vibe.core.file;
import vibe.core.log;


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
	
	void generateProject(BuildPlatform build_platform)
	{
		logTrace("About to generate projects for %s, with %s direct dependencies.", m_app.mainPackage().name, to!string(m_app.mainPackage().dependencies().length));
		generateProjects(m_app.mainPackage(), build_platform);
		generateSolution();
	}
	
	private void generateSolution()
	{
		auto sln = openFile(m_app.mainPackage().name ~ ".sln", FileMode.CreateTrunc);
		scope(exit) sln.close();

		// Writing solution file
		logTrace("About to write to .sln file.");

		// Solution header
		sln.put('\n');
		sln.put("Microsoft Visual Studio Solution File, Format Version 11.00\n");
		sln.put("# Visual Studio 2010\n");

		generateSolutionEntry(sln, m_app.mainPackage);
		if( !m_singleProject )
			performOnDependencies(m_app.mainPackage, pack => generateSolutionEntry(sln, pack));
		
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
	
	private void generateSolutionEntry(OutputStream ret, const Package pack)
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

	private void generateProjects(in Package pack, BuildPlatform build_platform)
	{
		bool[const(Package)] visited;

		void generateRec(in Package p){
			if( p in visited ) return;
			visited[p] = true;

			generateProject(p, build_platform);

			if( !m_singleProject )
				performOnDependencies(p, &generateRec);
		}
		generateRec(pack);
	}
		
	private void generateProject(in Package pack, BuildPlatform build_platform)
	{
		logTrace("About to write to '%s.dproj' file", pack.name);
		auto sln = openFile(pack.name ~ ".dproj", FileMode.CreateTrunc);
		scope(exit) sln.close();

		sln.put("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n");
		sln.put("<Project DefaultTargets=\"Build\" ToolsVersion=\"4.0\" xmlns=\"http://schemas.microsoft.com/developer/msbuild/2003\">\n");
		// TODO: property groups

		auto projName = pack.name;

		auto buildsettings = m_app.getBuildSettings(build_platform, m_app.getDefaultConfiguration(build_platform));

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
			sln.formattedWrite("        <String>%s</String>\n", buildsettings.versions.join(", "));
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
	    		sln.formattedWrite("        <Lib>%s</Lib>\n", build_platform.platform.canFind("windows") ? dir ~ ".lib" : dir);
	    	sln.put("      </Libs>\n");
	    	sln.put("    </Libs>\n");
	    }
    	buildsettings.dflags ~= buildsettings.stringImportPaths.map!(p => "-J"~p)().array();
		sln.formattedWrite("    <ExtraCompilerArguments>%s</ExtraCompilerArguments>\n", buildsettings.dflags.join(" "));
		sln.formattedWrite("    <ExtraLinkerArguments>%s</ExtraLinkerArguments>\n", buildsettings.lflags.join(" "));
		sln.put("  </PropertyGroup>\n");

		void generateProperties(Config config)
		{
			sln.formattedWrite("  <PropertyGroup Condition=\" '$(Configuration)|$(Platform)' == '%s|%s' \">\n",
				config.configName, config.platformName);
			
    		sln.put("    <DebugSymbols>True</DebugSymbols>\n");
			sln.formattedWrite("    <OutputPath>bin\\%s</OutputPath>\n", config.configName);
			sln.put("    <Externalconsole>True</Externalconsole>\n");
 			sln.put("    <Target>Executable</Target>\n");
    		sln.formattedWrite("    <OutputName>%s</OutputName>\n", pack.name);
			sln.put("    <UnittestMode>False</UnittestMode>\n");
			sln.formattedWrite("    <ObjectsDirectory>obj\\%s</ObjectsDirectory>\n", config.configName);
			sln.put("    <DebugLevel>0</DebugLevel>\n");
			sln.put("  </PropertyGroup>\n");
		}

		foreach(config; m_allConfigs)
			generateProperties(config);


		bool[const(Package)] visited;
		void generateSources(in Package p)
		{
			if( p in visited ) return;
			visited[p] = true;

			foreach( s; p.sources )
				sln.formattedWrite("    <Compile Include=\"%s\" />\n", (p.path.relativeTo(pack.path) ~ s).toNativeString());
			foreach( s; buildsettings.files )
				sln.formattedWrite("    <Compile Include=\"%s\" />\n", s);
		}


		sln.put("  <ItemGroup>\n");
		generateSources(pack);
		if( m_singleProject )
			foreach(dep; m_app.installedPackages)
				generateSources(dep);
		sln.put("  </ItemGroup>\n");
		sln.put("</Project>");
	}
		
	void performOnDependencies(const Package main, void delegate(const Package pack) op)
	{
		foreach(id, dependency; main.dependencies){
			logDebug("Retrieving package %s from package manager.", id);
			auto pack = m_pkgMgr.getBestPackage(id, dependency);
			if(pack is null) {
			 	logWarn("Package %s (%s) could not be retrieved continuing...", id, to!string(dependency));
				continue;
			}
			logDebug("Performing on retrieved package %s", pack.name);
			op(pack);
		}
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