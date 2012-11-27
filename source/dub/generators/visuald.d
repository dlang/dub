/**
	Generator for VisualD project files
	
	Copyright: © 2012 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff
*/
module dub.generators.visuald;

import std.array;
import std.conv;
import std.format;
import std.uuid;

import vibe.core.file;
import vibe.core.log;

import dub.dub;
import dub.package_;
import dub.packagestore;
import dub.generators.generator;

class VisualDGenerator : ProjectGenerator {
	private {
		Application m_app;
		PackageStore m_store;
		string[string] m_projectUuids;
		bool[string] m_generatedProjects;
	}
	
	this(Application app, PackageStore store) {
		m_app = app;
		m_store = store;
	}
	
	override void generateProject() {
		logDebug("About to generate projects for %s, with %s direct dependencies.", m_app.mainPackage().name, to!string(m_app.mainPackage().dependencies().length));
		generateProjects(m_app.mainPackage());
		generateSolution();
	}
	
	private {
		enum Config {
			Release,
			Debug,
			Unittest
		}
		
		void generateSolution() {
			auto ret = appender!(char[])();
			
			// Solution header
			ret.formattedWrite("Microsoft Visual Studio Solution File, Format Version 11.00
# Visual Studio 2010");

			generateSolutionEntries(ret, m_app.mainPackage());
			
			// Global section contains configurations
			ret.formattedWrite("Global
	GlobalSection(SolutionConfigurationPlatforms) = preSolution
		Debug|Win32 = Debug|Win32
		Release|Win32 = Release|Win32
		Unittest|Win32 = Unittest|Win32
	EndGlobalSection
	GlobalSection(ProjectConfigurationPlatforms) = postSolution");
			
			generateSolutionConfig(ret, m_app.mainPackage());
			
			// TODO: for all dependencies
			
			ret.formattedWrite("
	GlobalSection(SolutionProperties) = preSolution
		HideSolutionNode = FALSE
	EndGlobalSection
EndGlobal");

			// Writing solution file
			logTrace("About to write to .sln file with %s bytes", to!string(ret.data().length));
			auto sln = openFile(m_app.mainPackage().name ~ ".sln", FileMode.CreateTrunc);
			scope(exit) sln.close();
			sln.write(ret.data());
			sln.flush();
		}
		
		void generateSolutionEntries(Appender!(char[]) ret, const Package main) {
			generateSolutionEntry(ret, main);
			performOnDependencies(main, (const Package pack) { generateSolutionEntries(ret, pack); } );
		}
		
		void generateSolutionEntry(Appender!(char[]) ret, const Package pack) {
			auto projUuid = generateUUID();
			auto projName = pack.name;
			auto projPath = pack.name ~ ".visualdproj";
			auto projectUuid = guid(projName);
			
			// Write project header, like so
			// Project("{002A2DE9-8BB6-484D-9802-7E4AD4084715}") = "derelict", "..\inbase\source\derelict.visualdproj", "{905EF5DA-649E-45F9-9C15-6630AA815ACB}"
			ret.formattedWrite("\nProject(\"%s\") = \"%s\", \"%s\", \"%s\"",
				projUuid, projName, projPath, projectUuid);

			// TODO: add dependency references
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
			
			ret.formattedWrite("\nEndProject");
		}

		void generateSolutionConfig(Appender!(char[]) ret, const Package pack) {
			const string[] sub = [ "ActiveCfg", "Build.0" ];
			const string[] conf = [ "Debug|Win32", "Release|Win32", "Unittest|Win32" ];
			auto projectUuid = guid(pack.name());
			foreach(c; conf)
				foreach(s; sub)
					formattedWrite(ret, "\n\t\t%s.%s.%s = %s", to!string(projectUuid), c, s, c);
		}
		
		void generateProjects(const Package main) {
		
			// TODO: cyclic check
			
			generateProj(main);
			m_generatedProjects[main.name] = true;
			performOnDependencies(main, (const Package dependency) {
				if(dependency.name in m_generatedProjects)
					return;
				generateProjects(dependency);
			} );
		}
		
		void generateProj(const Package pack) {
			int i = 0;
			auto ret = appender!(char[])();
			
			auto projName = pack.name;
			ret.formattedWrite(
"<DProject>
	<ProjectGuid>%s</ProjectGuid>", guid(projName));
	
			// Several configurations (debug, release, unittest)
			generateProjectConfiguration(ret, pack, Config.Release);
			generateProjectConfiguration(ret, pack, Config.Debug);
			generateProjectConfiguration(ret, pack, Config.Unittest);

			// Add all files
			// TODO: nice folders
			formattedWrite(ret, "
	<Folder name=\"%s\">", projName);			
			foreach(source; pack.sources) {
				ret.formattedWrite("\n  <File path=\"%s\" />", source.toString());
			}
			ret.formattedWrite("
	</Folder>
</DProject>");

			logTrace("About to write to '%s.visualdproj' file %s bytes", pack.name, to!string(ret.data().length));
			auto sln = openFile(pack.name ~ ".visualdproj", FileMode.CreateTrunc);
			scope(exit) sln.close();
			sln.write(ret.data());
			sln.flush();
		}
		
		void generateProjectConfiguration(Appender!(char[]) ret, const Package pack, Config type) {
			ret.formattedWrite(
"\n	<Config name=\"%s\" platform=\"Win32\">
		<obj>0</obj>
		<link>0</link>
		<lib>0</lib>
		<subsystem>1</subsystem>
		<multiobj>0</multiobj>
		<singleFileCompilation>0</singleFileCompilation>
		<oneobj>0</oneobj>
		<trace>0</trace>
		<quiet>0</quiet>
		<verbose>0</verbose>
		<vtls>0</vtls>
		<symdebug>1</symdebug>
		<optimize>0</optimize>
		<cpu>0</cpu>
		<isX86_64>0</isX86_64>
		<isLinux>0</isLinux>
		<isOSX>0</isOSX>
		<isWindows>0</isWindows>
		<isFreeBSD>0</isFreeBSD>
		<isSolaris>0</isSolaris>
		<scheduler>0</scheduler>
		<useDeprecated>0</useDeprecated>
		<useAssert>0</useAssert>
		<useInvariants>0</useInvariants>
		<useIn>0</useIn>
		<useOut>0</useOut>
		<useArrayBounds>0</useArrayBounds>
		<noboundscheck>0</noboundscheck>
		<useSwitchError>0</useSwitchError>
		<useUnitTests>0</useUnitTests>
		<useInline>0</useInline>
		<release>0</release>
		<preservePaths>0</preservePaths>
		<warnings>1</warnings>
		<infowarnings>0</infowarnings>
		<checkProperty>1</checkProperty>
		<genStackFrame>0</genStackFrame>
		<pic>0</pic>
		<cov>0</cov>
		<nofloat>0</nofloat>
		<Dversion>2</Dversion>
		<ignoreUnsupportedPragmas>0</ignoreUnsupportedPragmas>
		<compiler>0</compiler>
		<otherDMD>0</otherDMD>
		<program>$(DMDInstallDir)windows\\bin\\dmd.exe</program>
		<imppath>source; ..\\vibe.d\\source</imppath>
		<fileImppath />
		<outdir>$(ConfigurationName)</outdir>
		<objdir>obj\\$(ConfigurationName)</objdir>
		<objname />
		<libname />
		<doDocComments>0</doDocComments>
		<docdir />
		<docname />
		<modules_ddoc />
		<ddocfiles />
		<doHdrGeneration>0</doHdrGeneration>
		<hdrdir />
		<hdrname />
		<doXGeneration>1</doXGeneration>
		<xfilename>$(IntDir)\\$(TargetName).json</xfilename>
		<debuglevel>0</debuglevel>
		<debugids />
		<versionlevel>0</versionlevel>
		<versionids>DerelictGL_ALL HostWin32</versionids>
		<dump_source>0</dump_source>
		<mapverbosity>0</mapverbosity>
		<createImplib>0</createImplib>
		<defaultlibname />
		<debuglibname />
		<moduleDepsFile />
		<run>0</run>
		<runargs />
		<runCv2pdb>1</runCv2pdb>
		<pathCv2pdb>$(VisualDInstallDir)cv2pdb\\cv2pdb.exe</pathCv2pdb>
		<cv2pdbPre2043>0</cv2pdbPre2043>
		<cv2pdbNoDemangle>0</cv2pdbNoDemangle>
		<cv2pdbEnumType>0</cv2pdbEnumType>
		<cv2pdbOptions />
		<objfiles />
		<linkswitches />
		<libfiles>ws2_32.lib gdi32.lib winmm.lib ..\\vibe.d\\lib\\win-i386\\event2.lib ..\\vibe.d\\lib\\win-i386\\eay.lib ..\\vibe.d\\lib\\win-i386\\ssl.lib</libfiles>
		<libpaths />
		<deffile />
		<resfile />
		<exefile>bin\\$(ProjectName)_d.exe</exefile>
		<additionalOptions>-L/PAGESIZE:1024</additionalOptions>
		<preBuildCommand />
		<postBuildCommand />
		<filesToClean>*.obj;*.cmd;*.build;*.json;*.dep</filesToClean>
	</Config>", to!string(type));
		}
		
		void performOnDependencies(const Package main, void delegate(const Package pack) op) {
			// TODO: cyclic check

			foreach(id, dependency; main.dependencies) {
				logWarn("Retrieving package %s from store.", id);
				logWarn("dudb");
				auto pack = m_store.package_(id, dependency);
				if(pack is null) {
				 	logWarn("Package %s (%s) could not be retrieved continuing...", id, to!string(dependency));
					continue;
				}
				op(pack);
			}
		}
		
		string generateUUID() const {
			return "{" ~ randomUUID().toString() ~ "}";
		}
		
		string guid(string projectName) {
			if(projectName !in m_projectUuids)
				m_projectUuids[projectName] = generateUUID();
			return m_projectUuids[projectName];
		}
	}
}