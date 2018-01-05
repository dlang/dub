/**
    Generator for CMake build scripts

    Copyright: © 2015 Steven Dwy
    License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
    Authors: Steven Dwy
*/
module dub.generators.cmake;

import dub.compilers.buildsettings;
import dub.generators.generator;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.inet.path;
import dub.project;

import std.algorithm: map, uniq;
import std.algorithm : stdsort = sort; // to avoid clashing with built-in sort
import std.array: appender, join, replace;
import std.stdio: File, write;
import std.string: format;

class CMakeGenerator: ProjectGenerator
{
    this(Project project)
    {
        super(project);
    }

    override void generateTargets(GeneratorSettings settings, in TargetInfo[string] targets)
    {
        auto script = appender!(char[]);
        auto scripts = appender!(string[]);
        bool[string] visited;
        NativePath projectRoot = m_project.rootPackage.path;
        NativePath cmakeListsPath = projectRoot ~ "CMakeLists.txt";

        foreach(name, info; targets)
        {
            if(visited.get(name, false))
                continue;

            visited[name] = true;
            name = name.sanitize;
            string targetType;
            string libType;
            bool addTarget = true;

            switch(info.buildSettings.targetType) with(TargetType)
            {
                case autodetect:
                    throw new Exception("Don't know what to do about autodetect target type");
                case executable:
                    targetType = "executable";

                    break;
                case dynamicLibrary:
                    libType = "SHARED";

                    goto case;
                case library:
                case staticLibrary:
                    targetType = "library";

                    break;
                case sourceLibrary:
                    addTarget = false;

                    break;
                case none:
                    continue;
                default:
                    assert(false);
            }

            script.put("include(UseD)\n");
            script.put(
                "add_d_conditions(VERSION %s DEBUG %s)\n".format(
                    info.buildSettings.versions.dup.join(" "),
                    info.buildSettings.debugVersions.dup.join(" "),
                )
            );

            foreach(directory; info.buildSettings.importPaths)
                script.put("include_directories(%s)\n".format(directory.sanitizeSlashes));

            if(addTarget)
            {
                script.put("add_%s(%s %s\n".format(targetType, name, libType));

                foreach(file; info.buildSettings.sourceFiles)
                    script.put("    %s\n".format(file.sanitizeSlashes));

                script.put(")\n");
                script.put(
                    "target_link_libraries(%s %s %s)\n".format(
                        name,
                        (info.dependencies ~ info.linkDependencies).dup.stdsort.uniq.map!(s => sanitize(s)).join(" "),
                        info.buildSettings.libs.dup.join(" ")
                    )
                );
                script.put(
                    `set_target_properties(%s PROPERTIES TEXT_INCLUDE_DIRECTORIES "%s")`.format(
                        name,
                        info.buildSettings.stringImportPaths.map!(s => sanitizeSlashes(s)).join(";")
                    ) ~ "\n"
                );
            }

            string filename = (projectRoot ~ "%s.cmake".format(name)).toNativeString;
            File file = File(filename, "w");

            file.write(script.data);
            file.close;
            script.shrinkTo(0);
            scripts.put(filename);
        }

        if(!cmakeListsPath.existsFile)
        {
            logWarn("You must use a fork of CMake which has D support for these scripts to function properly.");
            logWarn("It is available at https://github.com/trentforkert/cmake");
            logInfo("Generating default CMakeLists.txt");
            script.put("cmake_minimum_required(VERSION 3.0)\n");
            script.put("project(%s D)\n".format(m_project.rootPackage.name));

            foreach(path; scripts.data)
                script.put("include(%s)\n".format(path));

            File file = File(cmakeListsPath.toNativeString, "w");

            file.write(script.data);
            file.close;
        }
    }
}

///Transform a package name into a valid CMake target name.
private string sanitize(string name)
{
    return name.replace(":", "_");
}

private string sanitizeSlashes(string path)
{
    version(Windows)
        return path.replace("\\", "/");
    else
        return path;
}
