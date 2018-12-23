/**
    Generator for Ninja build scripts

    Copyright: © 2018 Martin Nowak
    License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
    Authors: Martin Nowak
*/
module dub.generators.ninja;

import dub.compilers.buildsettings;
import dub.generators.generator;
import dub.internal.vibecompat.core.log;
import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.inet.path;
import dub.package_ : Package;
import dub.project;

import std.algorithm: endsWith, filter, map, startsWith;
import std.array: replace;
import std.format : formattedWrite;
import std.stdio: File, write;
import std.string: format;

class NinjaGenerator: ProjectGenerator
{
    this(Project project)
    {
        super(project);
    }

    override void generateTargets(GeneratorSettings settings, in TargetInfo[string] targets)
    {
		auto path = (m_project.rootPackage.path ~ "build.ninja").toNativeString;
		auto script = File(path, "w").lockingTextWriter();

		script.formattedWrite(`
dc = %1$s

rule dc
     depfile = $out.deps
     command = $dc -c %2$s $dflags %3$-(%s %) $in; echo $out: $$(sed 's|.*(\(.*\)).*|\1|' $out.deps.tmp | sort | uniq | tr '\n' ' ') > $out.deps; rm $out.deps.tmp
     description = DC $in
rule link
     command = $dc %3$-(%s %) @$out.rsp $lflags
     rspfile = $out.rsp
     rspfile_content = $in
     description = LINK $out
rule ar
     command = rm -f $out && ar rcs $out $in
     description = AR $out
`,
			settings.platform.compilerBinary,
			settings.compiler.name == "gdc" ? "-fdeps=$out.deps.tmp" : "-deps=$out.deps.tmp",
			settings.compiler.outFileFlags("$out"));

		immutable rootPackageDir = m_project.rootPackage.path.toNativeString;
		string[string] targetPaths;
		foreach (name, ti; targets)
		{
			import std.path : buildPath;

			auto bs = &ti.buildSettings;
			targetPaths[name] = buildPath(bs.targetPath, settings.compiler.getTargetFileName(*bs, settings.platform));
		}
		foreach (name, ti; targets)
		{
			auto bs = ti.buildSettings.dup;
			assert(bs.targetType != TargetType.sourceLibrary && bs.targetType != TargetType.none);
			name = name.replace(":", "_");
			settings.compiler.prepareBuildSettings(bs, BuildSetting.commandLineSeparate|BuildSetting.sourceFiles);
			writeBuildScript(rootPackageDir, ti, settings, bs, targetPaths);
			script.formattedWrite("subninja build_%s.ninja\n", name);
		}
    }
}

void writeBuildScript(string rootPackageDir, in ref ProjectGenerator.TargetInfo ti, in ref GeneratorSettings settings, in ref BuildSettings bs, in string[string] targetPaths)
{
	import std.array : array;
	import std.algorithm : splitter;
	import std.conv : to;
	import std.path : absolutePath, buildPath, dirName, relativePath, setExtension;
	import std.range : zip;
	import dub.generators.build : BuildGenerator;

	auto scriptPath = buildPath(rootPackageDir, "build_%-(%s_%).ninja".format(ti.pack.name.splitter(":")));
	auto script = File(scriptPath, "w").lockingTextWriter;

	/// Objects are written relative to .dub/obj/ninja/<pkg> of the
	/// root package, this reflects the semantic of ninja, where the
	/// generator tool is rerun to build different configurations.
	auto packageName = ti.pack.basePackage is null ? ti.pack.name : ti.pack.basePackage.name;
	auto objDir = format(".dub/ninja/%s/", packageName);
	auto packDir = ti.pack.path.toNativeString;

	string shrinkPath(string path)
	{
		if (path.startsWith(rootPackageDir))
			return path[rootPackageDir.length .. $];
		return path;
	}
	auto srcs = bs.sourceFiles.filter!(s => s.endsWith(".d")).map!absolutePath.map!shrinkPath.array;
	auto objs = srcs.map!(src => buildPath(objDir, BuildGenerator.pathToObjName(src))).array;

	script.formattedWrite("dflags = %-(%s %)\n", bs.dflags);
	foreach (src, obj; zip(srcs, objs))
		script.formattedWrite("build %s: dc %s\n", obj, src);

	if (bs.targetType == TargetType.staticLibrary)
		script.formattedWrite("build %s: ar %-(%s %)\n", targetPaths[ti.pack.name], objs);
	else
	{
		script.formattedWrite("lflags = %-(%s %)\n", settings.compiler.targetTypeFlags(bs.targetType) ~ settings.compiler.lflagsToDFlags(bs.lflags));
		script.formattedWrite("build %s: link %-(%s %) %-(%s %)\n", targetPaths[ti.pack.name], objs,
			ti.linkDependencies.map!(ldep => buildPath(ldep.replace(":", "_"), targetPaths[ldep])));
	}
}
