import dub.compilers.buildsettings;
import dub.compilers.compiler;
import dub.dub;
import dub.generators.generator;
import dub.internal.vibecompat.inet.path;
import std.algorithm;
import std.file;
import std.path;
import std.stdio;

void main()
{
	auto project = buildNormalizedPath(getcwd, "subproject");
	chdir(buildNormalizedPath(getcwd, ".."));

	bool found;

	auto dub = new Dub(project, null, SkipPackageSuppliers.none);
	dub.packageManager.getOrLoadPackage(NativePath(project));
	dub.loadPackage();
	dub.project.validate();

	GeneratorSettings gs;
	gs.buildType = "debug";
	gs.config = "application";
	gs.compiler = getCompiler(dub.defaultCompiler);
	gs.run = false;
	gs.force = true;
	gs.tempBuild = true;
	gs.platform = gs.compiler.determinePlatform(gs.buildSettings,
		dub.defaultCompiler, dub.defaultArchitecture);

	gs.compileCallback = (status, output) {
		writeln(output);
		found = output.canFind("FIND_THIS_STRING");
		if (!found) {
			writeln("[ERROR]: Did not find the requiring string!");
			writeln("Exit status: ", status);
			writeln("Output:");
			writeln(output);
			writeln("[FAIL]: Could not find the requiring string");
		}
	};

	stderr.writeln("Checking if building works from a library in a different cwd:");
	dub.generateProject("build", gs);
	stderr.writeln("Success: ", found);

	assert(found);
}
