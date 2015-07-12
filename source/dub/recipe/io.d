module dub.recipe.io;

import dub.recipe.packagerecipe;
import dub.internal.vibecompat.inet.path;


/** Reads a package recipe from a file.
*/
PackageRecipe readPackageRecipe(string filename, string parent_name = null)
{
	return readPackageRecipe(Path(filename), parent_name);
}
/// ditto
PackageRecipe readPackageRecipe(Path file, string parent_name = null)
{
	import dub.internal.utils : stripUTF8Bom;
	import dub.internal.vibecompat.core.file : openFile, FileMode;

	string text;

	{
		auto f = openFile(file.toNativeString(), FileMode.read);
		scope(exit) f.close();
		text = stripUTF8Bom(cast(string)f.readAll());
	}

	return parsePackageRecipe(text, file.toNativeString(), parent_name);
}

/** Parses an in-memory package recipe.
*/
PackageRecipe parsePackageRecipe(string contents, string filename, string parent_name = null)
{
	import std.algorithm : endsWith;
	import dub.internal.vibecompat.data.json;
	import dub.recipe.json : parseJson;
	import dub.recipe.sdl : parseSDL;

	PackageRecipe ret;

	if (filename.endsWith(".json")) dub.recipe.json.parseJson(ret, parseJsonString(contents, filename), parent_name);
	else if (filename.endsWith(".sdl")) dub.recipe.sdl.parseSDL(ret, contents, parent_name, filename);
	else assert(false, "readPackageRecipe called with filename with unknown extension: "~filename);
	return ret;
}
