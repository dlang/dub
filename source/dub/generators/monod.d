/**
	Generator for MonoD project files
	
	Copyright: © 2013 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.generators.monod;

import std.algorithm;
import std.array;
import std.conv;
import std.format;
import std.uuid;
import std.exception;

import vibe.core.file;
import vibe.core.log;

import dub.project;
import dub.package_;
import dub.packagemanager;
import dub.generators.generator;

class MonoDGenerator : ProjectGenerator {
	private {
		Project m_app;
		PackageManager m_pkgMgr;
		string[string] m_projectUuids;
		bool m_singleProject = true;
	}
	
	this(Project app, PackageManager mgr)
	{
		m_app = app;
		m_pkgMgr = mgr;
	}
	
	void generateProject()
	{
		logTrace("About to generate projects for %s, with %s direct dependencies.", m_app.mainPackage().name, to!string(m_app.mainPackage().dependencies().length));
		/+generateProjects(m_app.mainPackage());
		generateSolution();+/
	}
	
	/+private void generateSolution()
	{
		auto sln = openFile(m_app.mainPackage().name ~ ".sln", FileMode.CreateTrunc);
		scope(exit) sln.close();

		// Writing solution file
		logTrace("About to write to .sln file.");

		// Solution header
		sln.put('\n');
		sln.put("Microsoft Visual Studio Solution File, Format Version 11.00\n");
		sln.put("# Visual Studio 2010\n");

		generateSolutionEntry(sln, main);
		if( m_singleProject ) enforce(main == m_app.mainPackage());
		else performOnDependencies(main, (const Package pack) { generateSolutionEntries(sln, pack); } );
		
		sln.put("Global\n");

		// configuration platforms
		sln.put("\tGlobalSection(SolutionConfigurationPlatforms) = preSolution\n");
		foreach(config; allconfigs)
			sln.formattedWrite("\t\t%s|%s = %s|%s\n", config.configName, config.plaformName);
		sln.put("\tEndGlobalSection\n");

		// configuration platforms per project
		sln.put("\tGlobalSection(ProjectConfigurationPlatforms) = postSolution\n");
		generateSolutionConfig(sln, m_app.mainPackage());
		auto projectUuid = guid(pack.name());
		foreach(config; allconfigs)
			foreach(s; ["ActiveCfg", "Build.0"])
				sln.formattedWrite("\n\t\t%s.%s|%s.%s = %s|%s",
					projectUuid, config.configName, config.platformName, s,
					config.configName, config.platformName);
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
		auto projPath = pack.name ~ ".visualdproj";
		auto projectUuid = guid(projName);
		
		// Write project header, like so
		// Project("{002A2DE9-8BB6-484D-9802-7E4AD4084715}") = "derelict", "..\inbase\source\derelict.visualdproj", "{905EF5DA-649E-45F9-9C15-6630AA815ACB}"
		ret.formattedWrite("\nProject(\"%s\") = \"%s\", \"%s\", \"%s\"",
			projUuid, projName, projPath, projectUuid);

		if( !m_singleProject ){
			if(pack.dependencies.length > 0) {
				ret.formattedWrite("
	ProjectSection(ProjectDependencies) = postProject");
				foreach(id, dependency; pack.dependencies) {
					// TODO: clarify what "uuid = uuid" should mean
					auto uuid = guid(id);
					ret.formattedWrite("
		%s = %s", uuid, uuid);
				}
				ret.formattedWrite("
	EndProjectSection");
			}
		}
		
		ret.formattedWrite("\nEndProject");
	}

	private void generateProjects(in Package pack)
	{
		bool[const(Package)] visited;

		void generateRec(in Package p){
			if( p in visited ) return;
			visited[p] = true;

			generateProject(p);

			if( !m_singleProject )
				performOnDependencies(p, &generateRec);
		}
	}
		
	private void generateProject(in Package pack) {
		logTrace("About to write to '%s.dproj' file", pack.name);
		auto sln = openFile(pack.name ~ ".dproj", FileMode.CreateTrunc);
		scope(exit) sln.close();

		sln.put("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n");
		sln.put("<Project DefaultTargets=\"Build\" ToolsVersion=\"4.0\" xmlns=\"http://schemas.microsoft.com/developer/msbuild/2003\">\n");
		// TODO: property groups

		auto projName = pack.name;

		void generateProperties(Configuration config)
		{
			sln.formattedWrite("\t<PropertyGroup> Condition=\" '$(Configuration)|$(Platform)' == '%s|%s' \"\n",
				config.configName, config.platformName);
			
			// TODO!
			sln.put("\n</PropertyGroup>\n");
		}

		foreach(config; allconfigs)
			generateProperties(config);


		bool[const(Package)] visited;
		void generateSources(in Package p)
		{
			if( p in visited ) return;
			visited[p] = true;

			foreach( s; p.sources )
				sln.formattedWrite("\t\t<Compile Include=\"%s\" />\n", s);

			if( m_singleProject ){
				foreach( dep; p.dependencies )
					generateSources(dep);
			}
		}


		sln.put("\t<ItemGroup>\n");
		generateSources(pack);
		sln.put("\t</ItemGroup>\n");
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
	}+/
}