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
import std.exception;
import std.format;
import std.string : format;
import std.uuid;


// Dubbing is developing dub...
//version = DUBBING;

// TODO: handle pre/post build commands


class VisualDGenerator : ProjectGenerator {
	private {
		PackageManager m_pkgMgr;
		string[string] m_projectUuids;
	}
	
	this(Project app, PackageManager mgr)
	{
		super(app);
		m_pkgMgr = mgr;
	}
	
	override void generateTargets(GeneratorSettings settings, in TargetInfo[string] targets)
	{
		auto bs = targets[m_project.name].buildSettings;
		logDebug("About to generate projects for %s, with %s direct dependencies.", m_project.rootPackage.name, m_project.rootPackage.dependencies.length);
		generateProjectFiles(settings, targets);
		generateSolutionFile(settings, targets);
		logInfo("VisualD project generated.");
	}

	private {
		void generateSolutionFile(GeneratorSettings settings, in TargetInfo[string] targets)
		{
			auto ret = appender!(char[])();
			auto configs = m_project.getPackageConfigs(settings.platform, settings.config);
			auto some_uuid = generateUUID();
			
			// Solution header
			ret.put("Microsoft Visual Studio Solution File, Format Version 11.00\n");
			ret.put("# Visual Studio 2010\n");

			bool[string] visited;
			void generateSolutionEntry(string pack) {
				if (pack in visited) return;
				visited[pack] = true;

				auto ti = targets[pack];

				auto uuid = guid(pack);
				ret.formattedWrite("Project(\"%s\") = \"%s\", \"%s\", \"%s\"\n",
					some_uuid, pack, projFileName(pack), uuid);

				if (ti.linkDependencies.length && ti.buildSettings.targetType != TargetType.staticLibrary) {
					ret.put("\tProjectSection(ProjectDependencies) = postProject\n");
					foreach (d; ti.linkDependencies)
						if (!isHeaderOnlyPackage(d, targets)) {
							// TODO: clarify what "uuid = uuid" should mean
							ret.formattedWrite("\t\t%s = %s\n", guid(d), guid(d));
						}
					ret.put("\tEndProjectSection\n");
				}

				ret.put("EndProject\n");

				foreach (d; ti.dependencies) generateSolutionEntry(d);
			}

			auto mainpack = m_project.rootPackage.name;

			generateSolutionEntry(mainpack);
			
			// Global section contains configurations
			ret.put("Global\n");
			ret.put("\tGlobalSection(SolutionConfigurationPlatforms) = preSolution\n");
			ret.formattedWrite("\t\t%s|Win32 = %s|Win32\n", settings.buildType, settings.buildType);
			ret.put("\tEndGlobalSection\n");
			ret.put("\tGlobalSection(ProjectConfigurationPlatforms) = postSolution\n");
			
			const string[] sub = ["ActiveCfg", "Build.0"];
			const string[] conf = [settings.buildType~"|Win32"];
			auto projectUuid = guid(mainpack);
			foreach (t; targets.byKey)
				foreach (c; conf)
					foreach (s; sub)
						formattedWrite(ret, "\t\t%s.%s.%s = %s\n", guid(t), c, s, c);
			
			// TODO: for all dependencies
			ret.put("\tEndGlobalSection\n");
			
			ret.put("\tGlobalSection(SolutionProperties) = preSolution\n");
			ret.put("\t\tHideSolutionNode = FALSE\n");
			ret.put("\tEndGlobalSection\n");
			ret.put("EndGlobal\n");

			// Writing solution file
			logDebug("About to write to .sln file with %s bytes", to!string(ret.data().length));
			auto sln = openFile(solutionFileName(), FileMode.CreateTrunc);
			scope(exit) sln.close();
			sln.put(ret.data());
			sln.flush();
		}

		
		void generateProjectFiles(GeneratorSettings settings, in TargetInfo[string] targets)
		{
			bool[string] visited;
			void performRec(string name) {
				if (name in visited) return;
				visited[name] = true;
				generateProjectFile(name, settings, targets);
				foreach (d; targets[name].dependencies)
					performRec(d);
			}

			performRec(m_project.rootPackage.name);
		}

		bool isHeaderOnlyPackage(string pack, in TargetInfo[string] targets)
		const {
			auto buildsettings = targets[pack].buildSettings;
			if (!buildsettings.sourceFiles.any!(f => f.endsWith(".d"))())
				return true;
			return false;
		}
		
		void generateProjectFile(string packname, GeneratorSettings settings, in TargetInfo[string] targets)
		{
			int i = 0;
			auto ret = appender!(char[])();
			
			auto project_file_dir = m_project.rootPackage.path ~ projFileName(packname).parentPath;
			ret.put("<DProject>\n");
			ret.formattedWrite("  <ProjectGuid>%s</ProjectGuid>\n", guid(packname));
	
			// Several configurations (debug, release, unittest)
			generateProjectConfiguration(ret, packname, settings.buildType, settings, targets);
			//generateProjectConfiguration(ret, packname, "release", settings, targets);
			//generateProjectConfiguration(ret, packname, "unittest", settings, targets);

			// Add all files
			auto files = targets[packname].buildSettings;
			SourceFile[string] sourceFiles;
			void addSourceFile(Path file_path, Path structure_path, bool build)
			{
				auto key = file_path.toString();
				auto sf = sourceFiles.get(key, SourceFile.init);
				sf.filePath = file_path;
				if (!sf.build) {
					sf.build = build;
					sf.structurePath = structure_path;
				}
				sourceFiles[key] = sf;
			}

			void addFile(string s, bool build) {
				auto sp = Path(s);
				assert(sp.absolute, format("Source path in %s expected to be absolute: %s", packname, s));
				//if( !sp.absolute ) sp = pack.path ~ sp;
				addSourceFile(sp.relativeTo(project_file_dir), determineStructurePath(sp, targets[packname]), build);
			}

			foreach (p; targets[packname].packages)
				if (!p.packageInfoFile.empty)
					addFile(p.packageInfoFile.toNativeString(), false);

			if (files.targetType == TargetType.staticLibrary)
				foreach(s; files.sourceFiles.filter!(s => !isLinkerFile(s))) addFile(s, true);
			else
				foreach(s; files.sourceFiles.filter!(s => !s.endsWith(".lib"))) addFile(s, true);

			foreach(s; files.importFiles) addFile(s, false);
			foreach(s; files.stringImportFiles) addFile(s, false);

			// Create folders and files
			ret.formattedWrite("  <Folder name=\"%s\">", getPackageFileName(packname));
			Path lastFolder;
			foreach(source; sortedSources(sourceFiles.values)) {
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

			logDebug("About to write to '%s.visualdproj' file %s bytes", getPackageFileName(packname), ret.data().length);
			auto proj = openFile(projFileName(packname), FileMode.CreateTrunc);
			scope(exit) proj.close();
			proj.put(ret.data());
			proj.flush();
		}
		
		void generateProjectConfiguration(Appender!(char[]) ret, string pack, string type, GeneratorSettings settings, in TargetInfo[string] targets)
		{
			auto project_file_dir = m_project.rootPackage.path ~ projFileName(pack).parentPath;
			auto buildsettings = targets[pack].buildSettings.dup;
			
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
				if (buildsettings.targetType == TargetType.executable)
				{
					output_type = Executable;
					output_ext = "exe";
				}
				else if (buildsettings.targetType == TargetType.dynamicLibrary)
				{
					output_type = DynamicLib;
					output_ext = "dll";
				}
				string debugSuffix = type == "debug" ? "_d" : "";
				auto bin_path = pack == m_project.rootPackage.name ? Path(buildsettings.targetPath) : Path(".dub/lib/");
				bin_path.endsWithSlash = true;
				ret.formattedWrite("    <lib>%s</lib>\n", output_type);
				ret.formattedWrite("    <exefile>%s%s%s.%s</exefile>\n", bin_path.toNativeString(), buildsettings.targetName, debugSuffix, output_ext);

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
				if (arch == "x86") addLinkFiles ~= " phobos.lib";
				if (output_type != StaticLib) ret.formattedWrite("    <libfiles>%s %s</libfiles>\n", linkLibs, addLinkFiles);

				// Unittests
				ret.formattedWrite("    <useUnitTests>%s</useUnitTests>\n", buildsettings.options & BuildOptions.unittests ? "1" : "0");

				// compute directory for intermediate files (need dummy/ because of how -op determines the resulting path)
				size_t ndummy = 0;
				foreach (f; buildsettings.sourceFiles) {
					auto rpath = Path(f).relativeTo(project_file_dir);
					size_t nd = 0;
					foreach (i; 0 .. rpath.length)
						if (rpath[i] == "..")
							nd++;
					if (nd > ndummy) ndummy = nd;
				}
				string intersubdir = replicate("dummy/", ndummy) ~ getPackageFileName(pack);
		
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
			foreach (p; m_project.getTopologicalPackageList(false, main, configs)) {
				if (p is main) continue;
				op(p);
			}
		}
		
		string generateUUID() const {
			import std.string;
			return "{" ~ toUpper(randomUUID().toString()) ~ "}";
		}
		
		string guid(string projectName) {
			if(projectName !in m_projectUuids)
				m_projectUuids[projectName] = generateUUID();
			return m_projectUuids[projectName];
		}

		auto solutionFileName() const {
			version(DUBBING) return getPackageFileName(m_project.rootPackage) ~ ".dubbed.sln";
			else return getPackageFileName(m_project.rootPackage.name) ~ ".sln";
		}

		Path projFileName(string pack) const {
			auto basepath = Path(".");//Path(".dub/");
			version(DUBBING) return basepath ~ (getPackageFileName(pack) ~ ".dubbed.visualdproj");
			else return basepath ~ (getPackageFileName(pack) ~ ".visualdproj");
		}
	}

	// TODO: nice folders
	struct SourceFile {
		Path structurePath;
		Path filePath;
		bool build;

		hash_t toHash() const nothrow @trusted { return structurePath.toHash() ^ filePath.toHash() ^ (build * 0x1f3e7b2c); }
		int opCmp(ref const SourceFile rhs) const { return sortOrder(this, rhs); }
		// "a < b" for folder structures (deepest folder first, else lexical)
		private final static int sortOrder(ref const SourceFile a, ref const SourceFile b) {
			assert(!a.structurePath.empty());
			assert(!b.structurePath.empty());
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

private Path determineStructurePath(Path file_path, in ProjectGenerator.TargetInfo target)
{
	foreach (p; target.packages) {
		if (file_path.startsWith(p.path))
			return Path(getPackageFileName(p.name)) ~ file_path[p.path.length .. $];
	}
	return Path("misc/") ~ file_path.head;
}

private string getPackageFileName(string pack)
{
	return pack.replace(":", "_");
}
