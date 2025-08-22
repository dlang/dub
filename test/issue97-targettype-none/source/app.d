import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	spawnProcess([dub, "build", "--root=sample"]).wait;
	immutable pkgBuildCache = dubHome.buildPath("cache", "issue97-targettype-none", "~master");
	immutable buildCacheA = pkgBuildCache.buildPath("+a", "build");
	immutable buildCacheB = pkgBuildCache.buildPath("+b", "build");

	if (!exists(buildCacheA))
		die("Generated 'a' subpackage build artifact not found!");
	if (!exists(buildCacheB))
		die("Generated 'b' subpackage build artifact not found!");

	if (spawnProcess([dub, "clean", "--root=sample"]).wait != 0)
		die("dub clean fialed");

	// make sure both sub-packages are cleaned
	if (exists(buildCacheA))
		die("Generated 'a' subpackage build artifact were not cleaned!");
	if (exists(buildCacheB))
		die("Generated 'b' subpackage build artifact were not cleaned!");
}
