import dub.compilers.buildsettings;
import dub.compilers.compiler;
import dub.dub;
import dub.generators.generator;
import dub.generators.targetdescription;
import dub.internal.vibecompat.inet.path;
import std.algorithm;
import std.conv;
import std.file;
import std.path;
import std.stdio;

void main(string[] args)
{
	auto project = buildNormalizedPath(getcwd, "subproject");
	auto projectPath = NativePath(project);

	auto dub = new Dub(project, null, SkipPackageSuppliers.none);
	dub.packageManager.getOrLoadPackage(NativePath(project));
	dub.loadPackage();
	dub.project.validate();

	GeneratorSettings gs;
	gs.cache = NativePath(tempDir);
	gs.buildType = "debug";
	gs.config = "application";
	gs.compiler = getCompiler(dub.defaultCompiler);

	auto gen = new TargetDescriptionGenerator(dub.project);
	gen.generate(gs);

	assert(gen.targetDescriptions.length == 2);
	assert(gen.targetDescriptionLookup["root"] == 0);
	assert(gen.targetDescriptionLookup["root:sub"] == 1);

	auto rootBs = gen.targetDescriptions[0].buildSettings;
	auto subBs = gen.targetDescriptions[1].buildSettings;

	assert(rootBs.specifiedSourcePaths.length == 1);
	assert(NativePath(rootBs.specifiedSourcePaths[0]).equalsDir(projectPath ~ "source"));
	assert(subBs.specifiedSourcePaths.length == 2);
	assert(NativePath(subBs.specifiedSourcePaths[0]).equalsDir(projectPath ~ "sub" ~ "source"));
	assert(NativePath(subBs.specifiedSourcePaths[1]).equalsDir(projectPath ~ "sub" ~ "impl"));
}

bool equalsDir(NativePath a, NativePath b)
{
	a.endsWithSlash = false;
	b.endsWithSlash = false;
	return a == b;
}
