// functionality to supply packages from git submodules
module dub.git;

import dub.dependency;
import dub.internal.vibecompat.core.file;
import dub.package_;
import dub.packagemanager;

import std.algorithm;
import std.ascii : newline;
import std.exception : enforce;
import std.range;
import std.string;

/** Adds the git submodules checked out in the root path as direct packages.
	Package version is derived from the submodule's tag by `getOrLoadPackage`.

	Params:
		packageManager = Package manager to track the added packages.
		rootPath = the root path of the git repository to check for submodules.
 */
public void addGitSubmodules(PackageManager packageManager, NativePath rootPath) {
	import std.process : execute;

	const submoduleInfo = execute(["git", "--git-dir=" ~ (rootPath ~ ".git").toNativeString, "submodule", "status"]);

	enforce(submoduleInfo.status == 0,
		format("git submodule status exited with error code %s: %s", submoduleInfo.status, submoduleInfo.output));

	foreach (line; submoduleInfo.output.lines) {
		const parts = line.split(" ").map!strip.filter!(a => !a.empty).array;
		const subPath = rootPath ~ parts[1];
		const packageFile = Package.findPackageFile(subPath);

		if (packageFile != NativePath.init) {
			const scmPath = rootPath ~ NativePath(".git/modules/" ~ parts[1]);
			packageManager.getOrLoadPackage(subPath, packageFile, false, scmPath);
		}
	}
}

private alias lines = text => text.split(newline).map!strip.filter!(a => !a.empty);
