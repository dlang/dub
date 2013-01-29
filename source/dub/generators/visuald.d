/**
	Generator for VisualD project files
	
	Copyright: © 2012 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff
*/
module dub.generators.visuald;

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

// version = VISUALD_SEPERATE_PROJECT_FILES;
version = VISUALD_SINGLE_PROJECT_FILE;

class VisualDGenerator : ProjectGenerator {
	private {
		Project m_app;
		PackageManager m_pkgMgr;
		string[string] m_projectUuids;
		bool[string] m_generatedProjects;
	}
	
	this(Project app, PackageManager mgr) {
		m_app = app;
		m_pkgMgr = mgr;
	}
	
	void generateProject() {
		logTrace("About to generate projects for %s, with %s direct dependencies.", m_app.mainPackage().name, to!string(m_app.mainPackage().dependencies().length));
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
			ret.formattedWrite("
Microsoft Visual Studio Solution File, Format Version 11.00
# Visual Studio 2010");

			generateSolutionEntries(ret, m_app.mainPackage());
			
			// Global section contains configurations
			ret.formattedWrite("
Global
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
			version(VISUALD_SEPERATE_PROJECT_FILES) {
				performOnDependencies(main, (const Package pack) { generateSolutionEntries(ret, pack); } );
			}
			version(VISUALD_SINGLE_PROJECT_FILE) {
				enforce(main == m_app.mainPackage());
			}
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

			version(VISUALD_SEPERATE_PROJECT_FILES) {
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

		void generateSolutionConfig(Appender!(char[]) ret, const Package pack) {
			const string[] sub = [ "ActiveCfg", "Build.0" ];
			const string[] conf = [ "Debug|Win32", "Release|Win32" /*, "Unittest|Win32" */];
			auto projectUuid = guid(pack.name());
			foreach(c; conf)
				foreach(s; sub)
					formattedWrite(ret, "\n\t\t%s.%s.%s = %s", to!string(projectUuid), c, s, c);
		}
		
		void generateProjects(const Package main) {
		
			// TODO: cyclic check
			
			generateProj(main);
			
			version(VISUALD_SEPERATE_PROJECT_FILES) 
			{
				m_generatedProjects[main.name] = true;
				performOnDependencies(main, (const Package dependency) {
					if(dependency.name in m_generatedProjects)
						return;
					generateProjects(dependency);
				} );
			}
		}
		
		void generateProj(const Package pack) {
			int i = 0;
			auto ret = appender!(char[])();
			
			auto projName = pack.name;
			ret.formattedWrite(
"<DProject>
  <ProjectGuid>%s</ProjectGuid>", guid(projName));
	
			// Several configurations (debug, release, unittest)
			generateProjectConfiguration(ret, pack, Config.Debug);
			generateProjectConfiguration(ret, pack, Config.Release);
	//		generateProjectConfiguration(ret, pack, Config.Unittest);

			// Add all files
			// TODO: nice folders
			struct SourceFile {
				string pkg;
				Path structurePath;
				Path filePath;
				int opCmp(ref const SourceFile rhs) const { return filePath.opCmp(rhs.filePath); }
			}
			bool[SourceFile] sourceFiles;
			void gatherSources(const(Package) package_, string prefix) {
				logDebug("Gather sources for %s", package_.name);
				if(prefix != "") prefix = "|" ~ prefix ~ "|";
				foreach(source; package_.sources) {
					SourceFile f = { package_.name, source, source };
					sourceFiles[f] = true;
					logDebug("pkg file: %s", source);
				}
			}
			
			version(VISUALD_SINGLE_PROJECT_FILE) {
				// gather all sources
				enforce(pack == m_app.mainPackage(), "Some setup has gone wrong in VisualD.generateProj()");
				bool[string] gathered;
				void gatherAll(const Package package_) {
					logDebug("Looking at %s", package_.name);
					if(package_.name in gathered)
						return;
					gathered[package_.name] = true;
					gatherSources(package_, ""/*package_.name*/);
					performOnDependencies(package_, (const Package dependency) { gatherAll(dependency); });
				}
				gatherAll(pack);
			}
			version(VISUALD_SEPERATE_PROJECT_FILES) {
				// gather sources for this package only
				gatherSources(pack, "");
			}
			
			// Create folders and files
			// TODO: nice foldering
			ret.formattedWrite("\n  <Folder name=\"%s\">", pack.name);
			version(VISUALD_SINGLE_PROJECT_FILE) {
				SourceFile[] files = sourceFiles.keys;
				sort!("a.pkg > b.pkg")(files);
				string last = "";
				foreach(source; files) {
					if(last != source.pkg) {
						if(!last.empty)
							ret.put("\n    </Folder>");
						ret.formattedWrite("\n    <Folder name=\"%s\">", source.pkg);
						last = source.pkg;
					}
					ret.formattedWrite("\n      <File path=\"%s\" />",  source.filePath.toString());
				}
				ret.put("\n    </Folder>");
			}
			version(VISUALD_SEPERATE_PROJECT_FILES) {
				foreach(source, dummy; sourceFiles)
					ret.formattedWrite("\n  <File path=\"%s\" />",  source.filePath.toString());
			}
			ret.put("\n  </Folder>\n</DProject>");

			logTrace("About to write to '%s.visualdproj' file %s bytes", pack.name, to!string(ret.data().length));
			auto sln = openFile(pack.name ~ ".visualdproj", FileMode.CreateTrunc);
			scope(exit) sln.close();
			sln.write(ret.data());
			sln.flush();
		}
		
		void generateProjectConfiguration(Appender!(char[]) ret, const Package pack, Config type) {
			BuildPlatform platform;
			platform.platform ~= "windows";
			platform.architecture ~= "x86";
			platform.compiler = "dmd";
		
			auto settings = m_app.getBuildSettings(platform, m_app.getDefaultConfiguration(platform));

			string[] getSettings(string setting)(){ return __traits(getMember, settings, setting); }
			
			// Specify build configuration name
			ret.formattedWrite("
  <Config name=\"%s\" platform=\"Win32\">", to!string(type));
			
			ret.formattedWrite("
    <obj>0</obj>
    <link>0</link>
    <lib>0</lib>
    <subsystem>0</subsystem>
    <multiobj>0</multiobj>
    <singleFileCompilation>0</singleFileCompilation>
    <oneobj>0</oneobj>
    <trace>0</trace>
    <quiet>0</quiet>
    <verbose>0</verbose>
    <vtls>0</vtls>");
	
			// debug and optimize setting
			ret.formattedWrite("			
    <symdebug>%s</symdebug>
    <optimize>%s</optimize>", type != Config.Release? "1":"0", type != Config.Debug? "1":"0");
			
			ret.formattedWrite("
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
    <warnings>0</warnings>
    <infowarnings>0</infowarnings>
    <checkProperty>0</checkProperty>
    <genStackFrame>0</genStackFrame>
    <pic>0</pic>
    <cov>0</cov>
    <nofloat>0</nofloat>
    <Dversion>2</Dversion>
    <ignoreUnsupportedPragmas>0</ignoreUnsupportedPragmas>
    <compiler>0</compiler>
    <otherDMD>0</otherDMD>");
	
			// include paths and string imports
			string imports;
			string stringImports;
			ret.formattedWrite("
    <imppath>%s</imppath>
    <fileImppath>%s</fileImppath>", imports, stringImports);
	
			// Compiler?
			ret.formattedWrite("
    <program>$(DMDInstallDir)windows\\bin\\dmd.exe</program>
    <outdir>$(ConfigurationName)</outdir>
    <objdir>$(OutDir)</objdir>
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
    <versionlevel>0</versionlevel>
    <debugids />"); // version ids ?
	
			// Add version identifiers
			string versions = join(getSettings!"versions"(), " ");
			ret.formattedWrite("
    <versionids>%s</versionids>", versions);
	
			ret.formattedWrite("
    <dump_source>0</dump_source>
    <mapverbosity>0</mapverbosity>
    <createImplib>0</createImplib>
    <defaultlibname />
    <debuglibname />
    <moduleDepsFile />
    <run>0</run>
    <runargs />");
			
			// TODO: Mago? Debugger settings!
			ret.formattedWrite("
    <runCv2pdb>1</runCv2pdb>
    <pathCv2pdb>$(VisualDInstallDir)cv2pdb\\cv2pdb.exe</pathCv2pdb>
    <cv2pdbPre2043>0</cv2pdbPre2043>
    <cv2pdbNoDemangle>0</cv2pdbNoDemangle>
    <cv2pdbEnumType>0</cv2pdbEnumType>
    <cv2pdbOptions />
    <objfiles />
    <linkswitches />");
			
			// Add libraries.
			string linkLibs = join(getSettings!"libs"(), " ");
			string addLinkFiles = join(getSettings!"files"(), " ");
			ret.formattedWrite("
    <libfiles>%s</libfiles>", linkLibs ~ " " ~ addLinkFiles);
			
			// Add library paths ( not necessary, libraries have absolute path )
			ret.formattedWrite("
    <libpaths />
    <deffile />
    <resfile />
    <exefile>bin\\$(ProjectName)_d.exe</exefile>
    <additionalOptions />
    <preBuildCommand />");
			
			// Add a post build command to copy files
			ret.formattedWrite("
    <postBuildCommand />");
			
			ret.formattedWrite("
    <filesToClean>*.obj;*.cmd;*.build;*.json;*.dep</filesToClean>
  </Config>");
		}
		
		void performOnDependencies(const Package main, void delegate(const Package pack) op) {
			// TODO: cyclic check

			foreach(id, dependency; main.dependencies) {
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
		
		string generateUUID() const {
			return "{" ~ randomUUID().toString() ~ "}";
		}
		
		string guid(string projectName) {
			if(projectName !in m_projectUuids)
				m_projectUuids[projectName] = generateUUID();
			return m_projectUuids[projectName];
		}
		
		string libfiles(const Package pack) {
			return "";
		}
	}
}