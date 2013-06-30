/**
    Generator for DDT project files

    Copyright: © 2013 rejectedsoftware e.K.
    License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
    Authors: QAston <qaston@gmail.com>
*/
module dub.generators.ddt;

import dub.compilers.compiler;
import dub.generators.generator;
import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.core.log;
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

class DDTGenerator : ProjectGenerator {
	private {
		Project m_app;
		PackageManager m_pkgMgr;
	}

	this(Project app, PackageManager mgr)
	{
		m_app = app;
		m_pkgMgr = mgr;
	}

	void generateProject(GeneratorSettings settings)
	{
        logWarn("Note that DDT project format does not support subpackages, dependencies, copyFiles  and pre/postBuildCommand settings");

		auto buildsettings = settings.buildSettings;
		m_app.addBuildSettings(buildsettings, settings.platform, settings.config);

		prepareGeneration(buildsettings);

		logDebug("About to generate projects for %s, with %s direct dependencies.", m_app.mainPackage().name, m_app.mainPackage().dependencies().length);
		generateProject(m_app.mainPackage(), settings);

		finalizeGeneration(buildsettings, true);
	}

    /**
        Generates .project file. Based on:
	    http://help.eclipse.org/juno/index.jsp?topic=%2Forg.eclipse.platform.doc.isv%2Freference%2Fmisc%2Fproject_description_file.html
    */
    private void generateProjectFile(in Package pack, BuildSettings buildsettings)
    {
		logDebug("About to write to '.project' file");
		auto proj = openFile(".project", FileMode.CreateTrunc);
		scope(exit) proj.close();

		proj.put("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
		proj.put("<projectDescription>\n");

        // project name
        proj.formattedWrite("    <name>%s</name>\n", pack.name);
        proj.put("    <comment></comment>\n");

        // Specify which workspace projects are referenced by the project
        proj.put("    <projects>\n");
        proj.put("    </projects>\n");

        // Settings required for build with DDT
        proj.put("    <buildSpec>\n");
        proj.put("    <buildCommand>\n");
        proj.put("       <name>org.eclipse.dltk.core.scriptbuilder</name>\n");
        proj.put("       <arguments>\n");
        proj.put("       </arguments>\n");
        proj.put("    </buildCommand>\n");
        proj.put("    <buildCommand>\n");
        proj.put("       <name>org.dsource.ddt.ide.core.deebuilder</name>\n");
        proj.put("       <arguments>\n");
        proj.put("       </arguments>\n");
        proj.put("    </buildCommand>\n");
        proj.put("    </buildSpec>\n");
        proj.put("    <natures>\n");
        proj.put("       <nature>org.dsource.ddt.ide.core.nature</nature>\n");
        proj.put("    </natures>\n");

        /+proj.put("    <linkedResources>\n");
            foreach(dir; buildsettings.importPaths)
            {
                proj.put("        <link>\n");
                proj.put("            <name>source</name>\n");
                // type - directory
                proj.put("            <type>2</type>\n");
                proj.formattedWrite("            <location>%s</location>\n", Path(dir).relativeTo(pack.path));
                proj.put("        </link>\n");
            }+/
        proj.put("    </linkedResources>\n");
        proj.put("</projectDescription>\n");
    }

    /**
        Generates .dprojectoptions file
        The file handles build configuration for the project. Based on:
        https://code.google.com/p/ddt/source/browse/#git/org.dsource.ddt.ide.core/src/mmrnmhrm/core
    */
    private void generateDProjectOptionsFile(in Package pack, BuildSettings buildsettings, BuildPlatform platform, Compiler compiler)
    {
        logDebug("About to write to .dprojectoptions file.");
		auto opt = openFile(".dprojectoptions", FileMode.CreateTrunc);
		scope(exit) opt.close();

        opt.put("[compileoptions]\n");
        opt.formattedWrite("buildtype = %s\n", getBuildType(buildsettings));

        auto outpath = Path(buildsettings.targetPath).toNativeString();
        // relative path to output folder - $DEEBUILDER.OUTPUTPATH
        // must have a dir name
        opt.formattedWrite("out = %s\n", outpath.length ? outpath : "bin");

        // output file name - $DEEBUILDER.OUTPUTEXE
        opt.formattedWrite("outname = %s\n", getTargetFileName(buildsettings, platform));

        // command line of build tool 
        opt.put("buildtool = $DEEBUILDER.COMPILEREXEPATH @build.rf\n");

		// DDT does not have a project setting for string import paths, versions, pre/post build commands and project dependencies
	    compiler.prepareBuildSettings(buildsettings, BuildSetting.all & ~(BuildSetting.stringImportPaths | BuildSetting.versions | BuildSetting.libs | BuildSetting.lflags));
        // workaround - DDT doesn't handle LIB_STATIC type properly
        if (getBuildType(buildsettings) == "LIB_STATIC")
            buildsettings.addDFlags("-lib");

        
        // command line switches for dmd
        // $DEEBUILDER.SRCLIBS - defined, but unused in DDT code
        opt.formattedWrite("extraOptions = %s\\n-od$DEEBUILDER.OUTPUTPATH\\n-of$DEEBUILDER.OUTPUTEXE\\n$DEEBUILDER.SRCLIBS.-I\\n$DEEBUILDER.SRCFOLDERS.-I\\n$DEEBUILDER.SRCMODULES\n", buildsettings.dflags.join("\\n"));
    }

    private string getBuildType(ref BuildSettings settings)
    {
        import std.conv;
        switch(settings.targetType)
        {
            default:
                assert(false, "Invalid build type: " ~ settings.targetType.to!string());
                // the following are defined in DDT but unused
            case TargetType.dynamicLibrary:
                return "LIB_DYNAMIC";
            case TargetType.library:
            case TargetType.staticLibrary:
                return "LIB_STATIC";
            case TargetType.executable:
                return "EXECUTABLE";
        }
    }


    /**
        Generates .buildpath file
        The file handles build dependencies lookup. File format is defined by Dynamic Languages Toolkit (DLTK).
    */
    private void generateBuildPathFile(in Package pack, BuildSettings buildsettings)
    {
		logDebug("About to write to '.buildpath' file");
		auto bld = openFile(".buildpath", FileMode.CreateTrunc);
		scope(exit) bld.close();

		bld.put("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
		bld.put("<buildpath>\n");

        // include dirs - apparently used the same way as source dirs in DDT
        // TODO: paths defined here must be subdirs of the project directory
        foreach(dir; buildsettings.importPaths)
            bld.formattedWrite("    <buildpathentry kind=\"src\" path=\"%s\" />\n", Path(dir).relativeTo(pack.path));

        // TODO: library and project dependencies should be here, DLTK defines those but DDT ignores entries other than kind="src"

        bld.put("    <buildpathentry kind=\"con\" path=\"org.eclipse.dltk.launching.INTERPRETER_CONTAINER\"/>\n");
		bld.put("</buildpath>\n");
    }

    // makes eclipse display utf-8 properly
    private void generateSettings()
    {
        logDebug("About to create '.settings' dir");
        immutable settingsDir = Path("./.settings/");
        if (!std.file.exists(settingsDir.toNativeString()))
			std.file.mkdirRecurse(settingsDir.toNativeString());
		auto settings = openFile(settingsDir ~ "org.eclipse.core.resources.prefs", FileMode.CreateTrunc);
		scope(exit) settings.close();
        settings.put("eclipse.preferences.version=1\n");
        settings.put("encoding/<project>=UTF-8\n");
    }

    
	private void generateProject(in Package pack, GeneratorSettings settings)
	{
        BuildSettings buildsettings = settings.buildSettings;
		m_app.addBuildSettings(buildsettings, settings.platform, settings.config);

        generateProjectFile(pack, buildsettings);
        generateDProjectOptionsFile(pack, buildsettings, settings.platform, settings.compiler);
        generateBuildPathFile(pack, buildsettings);
        generateSettings();
    }
}
