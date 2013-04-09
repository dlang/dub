/**
	Generator for VisualD project files
	
	Copyright: © 2012 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff
*/
module dub.generators.visuald;

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

version = VISUALD_SEPERATE_PROJECT_FILES;
//version = VISUALD_SINGLE_PROJECT_FILE;

// Dubbing is developing dub...
//version = DUBBING;

// TODO: handle pre/post build commands


class VisualDGenerator : ProjectGenerator {
	private {
		Project m_app;
		PackageManager m_pkgMgr;
		string[string] m_projectUuids;
	}
	
	this(Project app, PackageManager mgr) {
		m_app = app;
		m_pkgMgr = mgr;
	}
	
	void generateProject(GeneratorSettings settings) {
		auto buildsettings = settings.buildSettings;
		m_app.addBuildSettings(buildsettings, settings.platform, settings.config);
		
		prepareGeneration(buildsettings);

		logTrace("About to generate projects for %s, with %s direct dependencies.", m_app.mainPackage().name, m_app.mainPackage().dependencies().length);
		generateProjects(m_app.mainPackage(), settings);
		generateSolution();
		logInfo("VisualD project generated.");

		finalizeGeneration(buildsettings, true);
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

			generateSolutionEntry(ret, m_app.mainPackage);
			version(VISUALD_SEPERATE_PROJECT_FILES)
			{
				performOnDependencies(m_app.mainPackage, (pack){
					generateSolutionEntry(ret, pack);
				});
			}
			
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
			auto sln = openFile(solutionFileName(), FileMode.CreateTrunc);
			scope(exit) sln.close();
			sln.put(ret.data());
			sln.flush();
		}

		void generateSolutionEntry(Appender!(char[]) ret, const Package pack) {
			auto projUuid = generateUUID();
			auto projName = pack.name;
			auto projPath = projFileName(pack);
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
		
		void generateProjects(const Package main, GeneratorSettings settings) {
		
			// TODO: cyclic check
			
			generateProj(main, settings);
			
			version(VISUALD_SEPERATE_PROJECT_FILES) 
			{
				bool[string] generatedProjects;
				generatedProjects[main.name] = true;
				performOnDependencies(main, (const Package dependency) {
					if(dependency.name in generatedProjects)
						return;
					generateProj(dependency, settings);
				} );
			}
		}
		
		void generateProj(const Package pack, GeneratorSettings settings)
		{
			int i = 0;
			auto ret = appender!(char[])();
			
			auto projName = pack.name;
			ret.formattedWrite(
"<DProject>
  <ProjectGuid>%s</ProjectGuid>", guid(projName));
	
			// Several configurations (debug, release, unittest)
			generateProjectConfiguration(ret, pack, Config.Debug, settings);
			generateProjectConfiguration(ret, pack, Config.Release, settings);
			generateProjectConfiguration(ret, pack, Config.Unittest, settings);

			// Add all files
			version(VISUALD_SINGLE_PROJECT_FILE){
				auto files = settings.buildSettings;

				// add all package.json files to the project
				foreach(prj; m_app.getTopologicalPackageList())
					files.sourceFiles ~= prj.packageInfoFile.toNativeString();

				bool[SourceFile] sourceFiles;
				foreach(s; files.sourceFiles){
					auto sp = Path(s);
					if( !sp.absolute ) sp = m_app.mainPackage.path ~ sp;
					SourceFile sf;
					sf.pkg = pack.name;
					sf.filePath = sp.relativeTo(m_app.mainPackage.path);
					sf.structurePath = Path(pack.name) ~ sp.relativeTo(pack.path);
					sourceFiles[sf] = true;
				}
			}

			version(VISUALD_SEPERATE_PROJECT_FILES){
				auto configs = m_app.getPackageConfigs(settings.platform, settings.config);
				auto files = pack.getBuildSettings(settings.platform, configs[pack.name]);

				files.sourceFiles ~= pack.packageInfoFile.toNativeString();

				bool[SourceFile] sourceFiles;
				foreach(s; files.sourceFiles){
					auto sp = Path(s);
					if( !sp.absolute ) sp = pack.path ~ sp;
					SourceFile sf;
					sf.pkg = pack.name;
					sf.filePath = sp.relativeTo(m_app.mainPackage.path);
					sf.structurePath = sp.relativeTo(pack.path);
					sourceFiles[sf] = true;
				}
			}

			// Create folders and files
			ret.formattedWrite("\n  <Folder name=\"%s\">", pack.name);
			Path lastFolder;
			foreach(source; sortedSources(sourceFiles.keys)) {
				logTrace("source looking at %s", source.structurePath);
				auto cur = source.structurePath[0 .. source.structurePath.length-1];
				if(lastFolder != cur) {
					size_t same = 0;
					foreach(idx; 0..min(lastFolder.length, cur.length))
						if(lastFolder[idx] != cur[idx]) break;
						else same = idx+1;

					const decrease = lastFolder.length - min(lastFolder.length, same);
					const increase = cur.length - min(cur.length, same);

					foreach(unused; 0..decrease)
						ret.put("\n    </Folder>");
					foreach(idx; 0..increase)
						ret.formattedWrite("\n    <Folder name=\"%s\">", cur[same + idx].toString());
					lastFolder = cur;
				}
				ret.formattedWrite("\n      <File path=\"%s\" />",  source.filePath.toNativeString());
			}
			// Finalize all open folders
			foreach(unused; 0..lastFolder.length)
				ret.put("\n    </Folder>");
			ret.put("\n  </Folder>\n</DProject>");

			logTrace("About to write to '%s.visualdproj' file %s bytes", pack.name, ret.data().length);
			auto proj = openFile(projFileName(pack), FileMode.CreateTrunc);
			scope(exit) proj.close();
			proj.put(ret.data());
			proj.flush();
		}
		
		void generateProjectConfiguration(Appender!(char[]) ret, const Package pack, Config type, GeneratorSettings settings)
		{
			auto configs = m_app.getPackageConfigs(settings.platform, settings.config);
			auto buildsettings = settings.buildSettings;
			auto pbuildsettings = pack.getBuildSettings(settings.platform, configs[pack.name]);
			m_app.addBuildSettings(buildsettings, settings.platform, m_app.getDefaultConfiguration(settings.platform));
			string[] getSettings(string setting)(){ return __traits(getMember, buildsettings, setting); }
			
			foreach(architecture; settings.platform.architecture) {
				string arch;
				switch(architecture) {
					default: logWarn("Unsupported platform('%s'), defaulting to x86", architecture); goto case;
					case "x86": arch = "Win32"; break;
					case "x86_64": arch = "x64"; break;
				}
				ret.formattedWrite("
  <Config name=\"%s\" platform=\"%s\">", to!string(type), arch);
			
				// debug and optimize setting
				ret.formattedWrite("
    <symdebug>%s</symdebug>", type != Config.Release? "1":"0");
				ret.formattedWrite("
    <optimize>%s</optimize>", type == Config.Release? "1":"0");

				// Lib or exe?
				bool is_lib = pbuildsettings.targetType != TargetType.executable;
				string debugSuffix = type == Config.Debug? "_d" : "";
				auto bin_path = Path(pbuildsettings.targetPath);
				bin_path.endsWithSlash = true;
				ret.formattedWrite("
    <lib>%s</lib>
    <exefile>%s%s%s.%s</exefile>", is_lib ? "1" : "0", bin_path.toNativeString(), pbuildsettings.targetName, debugSuffix, is_lib ? "lib" : "exe");

				// include paths and string imports
				string imports = join(getSettings!"importPaths"(), " ");
				string stringImports = join(getSettings!"stringImportPaths"(), " ");
				ret.formattedWrite("
    <imppath>%s</imppath>
    <fileImppath>%s</fileImppath>", imports, stringImports);

				// Compiler?
				string compiler = "$(DMDInstallDir)windows\\bin\\dmd.exe";
				string dflags = join(getSettings!"dflags"(), " ");
				ret.formattedWrite("
    <program>%s</program>
    <additionalOptions>%s</additionalOptions>", compiler, dflags);

				// Add version identifiers
				string versions = join(getSettings!"versions"(), " ");
				if(type == Config.Unittest) versions ~= " " ~ "Unittest";
				ret.formattedWrite("
    <versionids>%s</versionids>", versions);

				// Add libraries, system libs need to be suffixed by ".lib".
				string linkLibs = join(map!(a => a~".lib")(getSettings!"libs"()), " ");
				string addLinkFiles = join(getSettings!"sourceFiles"().filter!(s => s.endsWith(".lib"))(), " ");
				ret.formattedWrite("
    <libfiles>%s</libfiles>", linkLibs ~ " " ~ addLinkFiles);

				// Unittests
				ret.formattedWrite("
				<useUnitTests>%s</useUnitTests>", type == Config.Unittest? "1" : "0");
		
				// Not yet dynamic stuff
				ret.formattedWrite("
    <obj>0</obj>
    <link>0</link>
    <subsystem>0</subsystem>
    <multiobj>0</multiobj>
    <singleFileCompilation>0</singleFileCompilation>
    <oneobj>0</oneobj>
    <trace>0</trace>
    <quiet>0</quiet>
    <verbose>0</verbose>
    <vtls>0</vtls>
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
    <otherDMD>0</otherDMD>
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
    <debugids />
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
    <libpaths />
    <deffile />
    <resfile />
    <preBuildCommand />
    <postBuildCommand />
    <filesToClean>*.obj;*.cmd;*.build;*.json;*.dep</filesToClean>
  </Config>");
			} // foreach(architecture)
		}
		
		void performOnDependencies(const Package main, void delegate(const Package pack) op) {
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
		
		string generateUUID() const {
			return "{" ~ randomUUID().toString() ~ "}";
		}
		
		string guid(string projectName) {
			if(projectName !in m_projectUuids)
				m_projectUuids[projectName] = generateUUID();
			return m_projectUuids[projectName];
		}

		auto solutionFileName() const {
			version(DUBBING) return m_app.mainPackage().name ~ ".dubbed.sln";
			else return m_app.mainPackage().name ~ ".sln";
		}

		auto projFileName(ref const Package pack) const {
			version(DUBBING) return pack.name ~ ".dubbed.visualdproj";
			else return pack.name ~ ".visualdproj";
		}
	}

	// TODO: nice folders
	struct SourceFile {
		string pkg;
		Path structurePath;
		Path filePath;

		int opCmp(ref const SourceFile rhs) const { return sortOrder(this, rhs); }
		// "a < b" for folder structures (deepest folder first, else lexical)
		private final static int sortOrder(ref const SourceFile a, ref const SourceFile b) {
			enforce(!a.structurePath.empty());
			enforce(!b.structurePath.empty());
			auto as = a.structurePath;
			auto bs = b.structurePath;

			// Check for different folders, compare folders only (omit last one).
			for(uint idx=0; idx<min(as.length-1, bs.length-1); ++idx)
				if(as[idx] != bs[idx])
					return as[idx].opCmp(bs[idx]);

			if(as.length != bs.length) {
				// If length differ, the longer one is "smaller", that is more 
				// specialized and will be put out first.
				return as.length > bs.length? -1 : 1;
			}
			else {
				// Both paths indicate files in the same directory, use lexical
				// ordering for those.
				return as.head.opCmp(bs.head);
			}
		}
	}

	auto sortedSources(SourceFile[] sources) {
		return sort(sources);
	}

	unittest {
		SourceFile[] sfs = [
			{ "", Path("b/file.d"), Path("") },
			{ "", Path("b/b/fileA.d"), Path("") },
			{ "", Path("a/file.d"), Path("") },
			{ "", Path("b/b/fileB.d"), Path("") },
			{ "", Path("b/b/b/fileA.d"), Path("") },
			{ "", Path("b/c/fileA.d"), Path("") },
		];
		auto sorted = sort(sfs);
		SourceFile[] sortedSfs;
		foreach(sr; sorted) {
			logInfo("%s", sr.structurePath.toNativeString());
			sortedSfs ~= sr;
		}
		assert(sortedSfs[0].structurePath == Path("a/file.d"), "1");
		assert(sortedSfs[1].structurePath == Path("b/b/b/fileA.d"), "2");
		assert(sortedSfs[2].structurePath == Path("b/b/fileA.d"), "3");
		assert(sortedSfs[3].structurePath == Path("b/b/fileB.d"), "4");
		assert(sortedSfs[4].structurePath == Path("b/c/fileA.d"), "5");
		assert(sortedSfs[5].structurePath == Path("b/file.d"), "6");
	}
}
