/**
    Generator for CMake build scripts

    Copyright: © 2015 Steven Dwy
    License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
    Authors: Steven Dwy
*/
module dub.generators.cmake;

import dub.compilers.buildsettings;
import dub.generators.generator;
import dub.project;

import std.algorithm: map, uniq, sort;
import std.array: appender, join;
import std.stdio: File, write;
import std.string: format, replace;

class CMakeGenerator: ProjectGenerator
{
    this(Project project)
    {
        super(project);
    }
    
    override void generateTargets(GeneratorSettings settings, in TargetInfo[string] targets)
    {
        auto script = appender!(char[]);
        bool[string] visited;
        
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
                    info.buildSettings.versions.join(" "),
                    info.buildSettings.debugVersions.join(" "),
                )
            );
            
            foreach(directory; info.buildSettings.importPaths)
                script.put("include_directories(%s)\n".format(directory));
            
            if(addTarget)
            {
                script.put("add_%s(%s %s\n".format(targetType, name, libType));
                
                foreach(file; info.buildSettings.sourceFiles)
                    script.put("    %s\n".format(file));
                
                script.put(")\n");
                script.put(
                    "target_link_libraries(%s %s %s)\n".format(
                        name,
                        (info.dependencies ~ info.linkDependencies).dup.sort.uniq.map!sanitize.join(" "),
                        info.buildSettings.libs.join(" ")
                    )
                );
            }
            
            string filename = "%s/%s.cmake".format(m_project.rootPackage.path.toString, name);
            File file = File(filename, "w");
            
            file.write(script.data);
            file.close;
            script.shrinkTo(0);
        }
    }
}

///Transform a package name into a valid CMake target name.
string sanitize(string name)
{
    return name.replace(":", "_");
}
