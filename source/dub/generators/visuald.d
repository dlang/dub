/**
	Generator for VisualD project files
	
	Copyright: © 2012-2013 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff
*/
module dub.generators.visuald;

import dub.compilers.compiler;
import dub.generators.generator;
import dub.internal.utils;
import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.core.log;
import dub.package_;
import dub.packagemanager;
import dub.project;

import std.algorithm;
import std.array;
import std.conv;
import std.format;
import std.uuid;
import std.exception;


// Dubbing is developing dub...
//version = DUBBING;

// TODO: handle pre/post build commands


class VisualDGenerator : ProjectGenerator {
	private {
		Project m_app;
		PackageManager m_pkgMgr;
		string[string] m_projectUuids;
		bool m_combinedProject;
	}
	
	this(Project app, PackageManager mgr, bool combined_project)
	{
		m_combinedProject = combined_project;
		m_app = app;
		m_pkgMgr = mgr;
	}
	
	void generateProject(GeneratorSettings settings)
	{
		auto buildsettings = settings.buildSettings;
		m_app.addBuildSettings(buildsettings, settings.platform, settings.config);
		
		prepareGeneration(buildsettings);

		logDebug("About to generate projects for %s, with %s direct dependencies.", m_app.mainPackage().name, m_app.mainPackage().dependencies().length);
		generateProjects(m_app.mainPackage(), settings);
		generateSolution(settings);
		logInfo("VisualD project generated.");

		finalizeGeneration(buildsettings, true);
	}
	
	private {
		void generateSolution(GeneratorSettings settings)
		{
			auto ret = appender!(char[])();
			auto configs = m_app.getPackageConfigs(settings.platform, settings.config);
			
			// Solution header
			ret.formattedWrite("
Microsoft Visual Studio Solution File, Format Version 11.00
# Visual Studio 2010");

			generateSolutionEntry(ret, m_app.mainPackage, settings);
			if (!m_combinedProject) {
				performOnDependencies(m_app.mainPackage, configs, (pack){
					generateSolutionEntry(ret, pack, settings);
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
			logDebug("About to write to .sln file with %s bytes", to!string(ret.data().length));
			auto sln = openFile(solutionFileName(), FileMode.CreateTrunc);
			scope(exit) sln.close();
			sln.put(ret.data());
			sln.flush();
		}

		void generateSolutionEntry(Appender!(char[]) ret, const Package pack, GeneratorSettings settings)
		{
			auto projUuid = generateUUID();
			auto projName = pack.name;
			auto projPath = projFileName(pack);
			auto projectUuid = guid(projName);
			
			// Write project header, like so
			// Project("{002A2DE9-8BB6-484D-9802-7E4AD4084715}") = "derelict", "..\inbase\source\derelict.visualdproj", "{905EF5DA-649E-45F9-9C15-6630AA815ACB}"
			ret.formattedWrite("\nProject(\"%s\") = \"%s\", \"%s\", \"%s\"",
				projUuid, projName, projPath, projectUuid);

			if (!m_combinedProject) {
				void addDepsRec(in Package p)
				{
					foreach(id, dependency; p.dependencies) {
						auto deppack = m_app.getDependency(id, true);
						if (!deppack) continue;
						if (isHeaderOnlyPackage(deppack, settings)) {
							addDepsRec(deppack);
						} else if (!m_app.isRedundantDependency(p, deppack)) {
							// TODO: clarify what "uuid = uuid" should mean
							auto uuid = guid(id);
							ret.formattedWrite("\n			%s = %s", uuid, uuid);
						}
					}
				}

				if(pack.dependencies.length > 0) {
					ret.formattedWrite("
		ProjectSection(ProjectDependencies) = postProject");
					addDepsRec(pack);
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
			auto configs = m_app.getPackageConfigs(settings.platform, settings.config);
			
			generateProj(main, settings);
			
			if (!m_combinedProject) {
				bool[string] generatedProjects;
				generatedProjects[main.name] = true;
				performOnDependencies(main, configs, (const Package dependency) {
					if(dependency.name in generatedProjects)
						return;
					generateProj(dependency, settings);
				} );
			}
		}

		bool isHeaderOnlyPackage(in Package pack, in GeneratorSettings settings)
		const {
			auto configs = m_app.getPackageConfigs(settings.platform, settings.config);
			auto pbuildsettings = pack.getBuildSettings(settings.platform, configs[pack.name]);
			if (!pbuildsettings.sourceFiles.any!(f => f.endsWith(".d"))())
				return true;
			return false;
		}
		
		void generateProj(const Package pack, GeneratorSettings settings)
		{
			int i = 0;
			auto ret = appender!(char[])();
			
			auto projName = pack.name;
			auto project_file_dir = m_app.mainPackage.path ~ projFileName(pack).parentPath;
			ret.put("<DProject>\n");
			ret.formattedWrite("  <ProjectGuid>%s</ProjectGuid>\n", guid(projName));
	
			// Several configurations (debug, release, unittest)
			generateProjectConfiguration(ret, pack, "debug", settings);
			generateProjectConfiguration(ret, pack, "release", settings);
			generateProjectConfiguration(ret, pack, "unittest", settings);

			// Add all files
			auto configs = m_app.getPackageConfigs(settings.platform, settings.config);
			auto files = pack.getBuildSettings(settings.platform, configs[pack.name]);
			bool[SourceFile] sourceFiles;
			void addSourceFile(Path file_path, Path structure_path, bool build)
			{
				SourceFile sf;
				sf.filePath = file_path;
				sf.structurePath = structure_path;
				if (build) {
					sf.build = false;
					if (sf in sourceFiles) sourceFiles.remove(sf);
				} else {
					sf.build = true;
					if (sf in sourceFiles) return;
				}
				sf.build = build;
				sourceFiles[sf] = true;
			}
			if (m_combinedProject) {
				bool[const(Package)] basePackagesAdded;

				// add all package.json files to the project
				// and all source files
				performOnDependencies(pack, configs, (prj) {
					void addFile(string s, bool build) {
						auto sp = Path(s);
						if( !sp.absolute ) sp = prj.path ~ sp;
						// regroup in Folder by base package
						addSourceFile(sp.relativeTo(project_file_dir), Path(prj.basePackage().name) ~ sp.relativeTo(prj.path), build);
					}

					string[] prjFiles;

					// Avoid multiples package.json when using sub-packages.
					// Only add the package info file if no other package/sub-package from the same base package
					// has been seen yet.
					{
						const(Package) base = prj.basePackage();

						if (base !in basePackagesAdded) {
							prjFiles ~= prj.packageInfoFile.toNativeString();
							basePackagesAdded[base] = true;
						}
					}

					auto settings = prj.getBuildSettings(settings.platform, configs[prj.name]);
					foreach (f; prjFiles) addFile(f, false);
					foreach (f; settings.sourceFiles) addFile(f, true);
					foreach (f; settings.importFiles) addFile(f, false);
					foreach (f; settings.stringImportFiles) addFile(f, false);
				});
			}

			void addFile(string s, bool build) {
				auto sp = Path(s);
				if( !sp.absolute ) sp = pack.path ~ sp;
				addSourceFile(sp.relativeTo(project_file_dir), sp.relativeTo(pack.path), build);
			}
			addFile(pack.packageInfoFile.toNativeString(), false);
			foreach(s; files.sourceFiles) addFile(s, true);
			foreach(s; files.importFiles) addFile(s, false);
			foreach(s; files.stringImportFiles) addFile(s, false);

			// Create folders and files
			ret.formattedWrite("  <Folder name=\"%s\">", getPackageFileName(pack));
			Path lastFolder;
			foreach(source; sortedSources(sourceFiles.keys)) {
				logDebug("source looking at %s", source.structurePath);
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
				ret.formattedWrite("\n      <File %spath=\"%s\" />", source.build ? "" : "tool=\"None\" ", source.filePath.toNativeString());
			}
			// Finalize all open folders
			foreach(unused; 0..lastFolder.length)
				ret.put("\n    </Folder>");
			ret.put("\n  </Folder>\n</DProject>");

			logDebug("About to write to '%s.visualdproj' file %s bytes", getPackageFileName(pack), ret.data().length);
			auto proj = openFile(projFileName(pack), FileMode.CreateTrunc);
			scope(exit) proj.close();
			proj.put(ret.data());
			proj.flush();
		}
		
		void generateProjectConfiguration(Appender!(char[]) ret, const Package pack, string type, GeneratorSettings settings)
		{
			auto project_file_dir = m_app.mainPackage.path ~ projFileName(pack).parentPath;
			auto configs = m_app.getPackageConfigs(settings.platform, settings.config);
			auto buildsettings = settings.buildSettings;
			auto pbuildsettings = pack.getBuildSettings(settings.platform, configs[pack.name]);
			m_app.addBuildSettings(buildsettings, settings.platform, settings.config, pack);
			m_app.addBuildTypeSettings(buildsettings, settings.platform, type);
			settings.compiler.extractBuildOptions(buildsettings);
			enforceBuildRequirements(buildsettings);
			
			string[] getSettings(string setting)(){ return __traits(getMember, buildsettings, setting); }
			string[] getPathSettings(string setting)()
			{
				auto settings = getSettings!setting();
				auto ret = new string[settings.length];
				foreach (i; 0 .. settings.length) {
					// \" is interpreted as an escaped " by cmd.exe, so we need to avoid that
					auto p = Path(settings[i]).relativeTo(project_file_dir);
					p.endsWithSlash = false;
					ret[i] = '"' ~ p.toNativeString() ~ '"';
				}
				return ret;
			}
			
			foreach(architecture; settings.platform.architecture) {
				string arch;
				switch(architecture) {
					default: logWarn("Unsupported platform('%s'), defaulting to x86", architecture); goto case;
					case "x86": arch = "Win32"; break;
					case "x86_64": arch = "x64"; break;
				}
				ret.formattedWrite("  <Config name=\"%s\" platform=\"%s\">\n", to!string(type), arch);

				// FIXME: handle compiler options in an abstract way instead of searching for DMD specific flags
			
				// debug and optimize setting
				ret.formattedWrite("    <symdebug>%s</symdebug>\n", buildsettings.options & BuildOptions.debugInfo ? "1" : "0");
				ret.formattedWrite("    <optimize>%s</optimize>\n", buildsettings.options & BuildOptions.optimize ? "1" : "0");
				ret.formattedWrite("    <useInline>%s</useInline>\n", buildsettings.options & BuildOptions.inline ? "1" : "0");
				ret.formattedWrite("    <release>%s</release>\n", buildsettings.options & BuildOptions.releaseMode ? "1" : "0");

				// Lib or exe?
				enum 
				{
					Executable = 0,
					StaticLib = 1,
					DynamicLib = 2
				}

				int output_type = StaticLib; // library
				string output_ext = "lib";
				if (pbuildsettings.targetType == TargetType.executable)
				{
					output_type = Executable;
					output_ext = "exe";
				}
				else if (pbuildsettings.targetType == TargetType.dynamicLibrary)
				{
					output_type = DynamicLib;
					output_ext = "dll";
				}
				string debugSuffix = type == "debug" ? "_d" : "";
				auto bin_path = pack is m_app.mainPackage ? Path(pbuildsettings.targetPath) : Path(".dub/lib/");
				bin_path.endsWithSlash = true;
				ret.formattedWrite("    <lib>%s</lib>\n", output_type);
				ret.formattedWrite("    <exefile>%s%s%s.%s</exefile>\n", bin_path.toNativeString(), pbuildsettings.targetName, debugSuffix, output_ext);

				// include paths and string imports
				string imports = join(getPathSettings!"importPaths"(), " ");
				string stringImports = join(getPathSettings!"stringImportPaths"(), " ");
				ret.formattedWrite("    <imppath>%s</imppath>\n", imports);
				ret.formattedWrite("    <fileImppath>%s</fileImppath>\n", stringImports);

				ret.formattedWrite("    <program>%s</program>\n", "$(DMDInstallDir)windows\\bin\\dmd.exe"); // FIXME: use the actually selected compiler!
				ret.formattedWrite("    <additionalOptions>%s</additionalOptions>\n", getSettings!"dflags"().join(" "));

				// Add version identifiers
				string versions = join(getSettings!"versions"(), " ");
				ret.formattedWrite("    <versionids>%s</versionids>\n", versions);

				// Add libraries, system libs need to be suffixed by ".lib".
				string linkLibs = join(map!(a => a~".lib")(getSettings!"libs"()), " ");
				string addLinkFiles = join(getSettings!"sourceFiles"().filter!(s => s.endsWith(".lib"))(), " ");
				if (output_type != StaticLib) ret.formattedWrite("    <libfiles>%s %s phobos.lib</libfiles>\n", linkLibs, addLinkFiles);

				// Unittests
				ret.formattedWrite("    <useUnitTests>%s</useUnitTests>\n", buildsettings.options & BuildOptions.unittests ? "1" : "0");

				// compute directory for intermediate files (need dummy/ because of how -op determines the resulting path)
				auto relpackpath = pack.path.relativeTo(project_file_dir);
				uint ndummy = 0;
				foreach (i; 0 .. relpackpath.length)
					if (relpackpath[i] == "..") ndummy++;
				string intersubdir = (ndummy*2 > relpackpath.length ? replicate("dummy/", ndummy*2-relpackpath.length) : "") ~ getPackageFileName(pack);
		
				ret.put("    <obj>0</obj>\n");
				ret.put("    <link>0</link>\n");
				ret.put("    <subsystem>0</subsystem>\n");
				ret.put("    <multiobj>0</multiobj>\n");
				ret.put("    <singleFileCompilation>2</singleFileCompilation>\n");
				ret.put("    <oneobj>0</oneobj>\n");
				ret.put("    <trace>0</trace>\n");
				ret.put("    <quiet>0</quiet>\n");
				ret.formattedWrite("    <verbose>%s</verbose>\n", buildsettings.options & BuildOptions.verbose ? "1" : "0");
				ret.put("    <vtls>0</vtls>\n");
				ret.put("    <cpu>0</cpu>\n");
				ret.formattedWrite("    <isX86_64>%s</isX86_64>\n", arch == "x64" ? 1 : 0);
				ret.put("    <isLinux>0</isLinux>\n");
				ret.put("    <isOSX>0</isOSX>\n");
				ret.put("    <isWindows>0</isWindows>\n");
				ret.put("    <isFreeBSD>0</isFreeBSD>\n");
				ret.put("    <isSolaris>0</isSolaris>\n");
				ret.put("    <scheduler>0</scheduler>\n");
				ret.put("    <useDeprecated>0</useDeprecated>\n");
				ret.put("    <useAssert>0</useAssert>\n");
				ret.put("    <useInvariants>0</useInvariants>\n");
				ret.put("    <useIn>0</useIn>\n");
				ret.put("    <useOut>0</useOut>\n");
				ret.put("    <useArrayBounds>0</useArrayBounds>\n");
				ret.formattedWrite("    <noboundscheck>%s</noboundscheck>\n", buildsettings.options & BuildOptions.noBoundsCheck ? "1" : "0");
				ret.put("    <useSwitchError>0</useSwitchError>\n");
				ret.put("    <preservePaths>1</preservePaths>\n");
				ret.formattedWrite("    <warnings>%s</warnings>\n", buildsettings.options & BuildOptions.warningsAsErrors ? "1" : "0");
				ret.formattedWrite("    <infowarnings>%s</infowarnings>\n", buildsettings.options & BuildOptions.warnings ? "1" : "0");
				ret.formattedWrite("    <checkProperty>%s</checkProperty>\n", buildsettings.options & BuildOptions.property ? "1" : "0");
				ret.formattedWrite("    <genStackFrame>%s</genStackFrame>\n", buildsettings.options & BuildOptions.alwaysStackFrame ? "1" : "0");
				ret.put("    <pic>0</pic>\n");
				ret.formattedWrite("    <cov>%s</cov>\n", buildsettings.options & BuildOptions.coverage ? "1" : "0");
				ret.put("    <nofloat>0</nofloat>\n");
				ret.put("    <Dversion>2</Dversion>\n");
				ret.formattedWrite("    <ignoreUnsupportedPragmas>%s</ignoreUnsupportedPragmas>\n", buildsettings.options & BuildOptions.ignoreUnknownPragmas ? "1" : "0");
				ret.formattedWrite("    <compiler>%s</compiler>\n", settings.compiler.name == "ldc" ? 2 : settings.compiler.name == "gdc" ? 1 : 0);
				ret.formattedWrite("    <otherDMD>0</otherDMD>\n");
				ret.formattedWrite("    <outdir>%s</outdir>\n", bin_path.toNativeString());
				ret.formattedWrite("    <objdir>.dub/obj/%s/%s</objdir>\n", to!string(type), intersubdir);
				ret.put("    <objname />\n");
				ret.put("    <libname />\n");
				ret.put("    <doDocComments>0</doDocComments>\n");
				ret.put("    <docdir />\n");
				ret.put("    <docname />\n");
				ret.put("    <modules_ddoc />\n");
				ret.put("    <ddocfiles />\n");
				ret.put("    <doHdrGeneration>0</doHdrGeneration>\n");
				ret.put("    <hdrdir />\n");
				ret.put("    <hdrname />\n");
				ret.put("    <doXGeneration>1</doXGeneration>\n");
				ret.put("    <xfilename>$(IntDir)\\$(TargetName).json</xfilename>\n");
				ret.put("    <debuglevel>0</debuglevel>\n");
				ret.put("    <versionlevel>0</versionlevel>\n");
				ret.put("    <debugids />\n");
				ret.put("    <dump_source>0</dump_source>\n");
				ret.put("    <mapverbosity>0</mapverbosity>\n");
				ret.put("    <createImplib>0</createImplib>\n");
				ret.put("    <defaultlibname />\n");
				ret.put("    <debuglibname />\n");
				ret.put("    <moduleDepsFile />\n");
				ret.put("    <run>0</run>\n");
				ret.put("    <runargs />\n");
				ret.put("    <runCv2pdb>1</runCv2pdb>\n");
				ret.put("    <pathCv2pdb>$(VisualDInstallDir)cv2pdb\\cv2pdb.exe</pathCv2pdb>\n");
				ret.put("    <cv2pdbPre2043>0</cv2pdbPre2043>\n");
				ret.put("    <cv2pdbNoDemangle>0</cv2pdbNoDemangle>\n");
				ret.put("    <cv2pdbEnumType>0</cv2pdbEnumType>\n");
				ret.put("    <cv2pdbOptions />\n");
				ret.put("    <objfiles />\n");
				ret.put("    <linkswitches />\n");
				ret.put("    <libpaths />\n");
				ret.put("    <deffile />\n");
				ret.put("    <resfile />\n");
				ret.put("    <preBuildCommand />\n");
				ret.put("    <postBuildCommand />\n");
				ret.put("    <filesToClean>*.obj;*.cmd;*.build;*.dep</filesToClean>\n");
				ret.put("  </Config>\n");
			} // foreach(architecture)
		}
		
		void performOnDependencies(const Package main, string[string] configs, void delegate(const Package pack) op)
		{
			foreach (p; m_app.getTopologicalPackageList(false, main, configs)) {
				if (p is main) continue;
				op(p);
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

		auto solutionFileName() const {
			version(DUBBING) return getPackageFileName(m_app.mainPackage()) ~ ".dubbed.sln";
			else return getPackageFileName(m_app.mainPackage()) ~ ".sln";
		}

		Path projFileName(ref const Package pack) const {
			auto basepath = Path(".");//Path(".dub/");
			version(DUBBING) return basepath ~ (getPackageFileName(pack) ~ ".dubbed.visualdproj");
			else return basepath ~ (getPackageFileName(pack) ~ ".visualdproj");
		}
	}

	// TODO: nice folders
	struct SourceFile {
		Path structurePath;
		Path filePath;
		bool build = true;

		hash_t toHash() const nothrow @trusted { return structurePath.toHash() ^ filePath.toHash() ^ (build * 0x1f3e7b2c); }
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
			{ Path("b/file.d"), Path("") },
			{ Path("b/b/fileA.d"), Path("") },
			{ Path("a/file.d"), Path("") },
			{ Path("b/b/fileB.d"), Path("") },
			{ Path("b/b/b/fileA.d"), Path("") },
			{ Path("b/c/fileA.d"), Path("") },
		];
		auto sorted = sort(sfs);
		SourceFile[] sortedSfs;
		foreach(sr; sorted)
			sortedSfs ~= sr;
		assert(sortedSfs[0].structurePath == Path("a/file.d"), "1");
		assert(sortedSfs[1].structurePath == Path("b/b/b/fileA.d"), "2");
		assert(sortedSfs[2].structurePath == Path("b/b/fileA.d"), "3");
		assert(sortedSfs[3].structurePath == Path("b/b/fileB.d"), "4");
		assert(sortedSfs[4].structurePath == Path("b/c/fileA.d"), "5");
		assert(sortedSfs[5].structurePath == Path("b/file.d"), "6");
	}
}

private string getPackageFileName(in Package pack)
{
	return pack.name.replace(":", "_");
}
