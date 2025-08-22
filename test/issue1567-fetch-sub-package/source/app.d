import common;

import std.algorithm;
import std.file;
import std.path;
import std.process;

void main () {
	immutable pkgName = "fetch-sub-package-dubpackage";
	immutable subPkgName = pkgName ~ ":my-sub-package";

	execute([dub, "remove", pkgName]);

	auto p = spawnProcess([dub, "fetch", subPkgName, "--skip-registry=all", "--registry=file://" ~ getcwd().buildPath("sample")]);
	if (p.wait != 0)
		die("Dub fetch failed");

	if (spawnProcess([dub, "remove", pkgName ~ "@1.0.1"]).wait != 0)
		die("DUB did not install package $packname:$sub_packagename.");
}
