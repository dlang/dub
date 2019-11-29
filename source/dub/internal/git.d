module dub.internal.git;

import dub.internal.vibecompat.core.file;
import dub.internal.vibecompat.core.log;
import std.file;
import std.string;

version (Windows)
{
	import dub.internal.vibecompat.data.json;

	string determineVersionWithGit(NativePath path)
	{
		// On Windows, which is slow at running external processes,
		// cache the version numbers that are determined using
		// git to speed up the initialization phase.
		import dub.internal.utils : jsonFromFile;

		// quickly determine head commit without invoking git
		string head_commit;
		auto hpath = (path ~ ".git/HEAD").toNativeString();
		if (exists(hpath)) {
			auto head_ref = readText(hpath).strip();
			if (head_ref.startsWith("ref: ")) {
				auto rpath = (path ~ (".git/"~head_ref[5 .. $])).toNativeString();
				if (exists(rpath))
					head_commit = readText(rpath).strip();
			}
		}

		// return the last determined version for that commit
		// not that this is not always correct, most notably when
		// a tag gets added/removed/changed and changes the outcome
		// of the full version detection computation
		auto vcachepath = path ~ ".dub/version.json";
		if (existsFile(vcachepath)) {
			auto ver = jsonFromFile(vcachepath);
			if (head_commit == ver["commit"].opt!string)
				return ver["version"].get!string;
		}

		// if no cache file or the HEAD commit changed, perform full detection
		auto ret = determineVersionWithGitTool(path);

		// update version cache file
		if (head_commit.length) {
			import dub.internal.utils : atomicWriteJsonFile;

			if (!existsFile(path ~".dub")) createDirectory(path ~ ".dub");
			atomicWriteJsonFile(vcachepath, Json(["commit": Json(head_commit), "version": Json(ret)]));
		}

		return ret;
	}
}
else
{
	string determineVersionWithGit(NativePath path)
	{
		return determineVersionWithGitTool(path);
	}
}

// determines the version of a package that is stored in a Git working copy
// by invoking the "git" executable
private string determineVersionWithGitTool(NativePath path)
{
	import dub.semver;
	import std.algorithm : canFind;
	import std.conv : to;
	import std.process;

	auto git_dir = path ~ ".git";
	if (!existsFile(git_dir) || !isDir(git_dir.toNativeString)) return null;
	auto git_dir_param = "--git-dir=" ~ git_dir.toNativeString();

	static string exec(scope string[] params...) {
		auto ret = executeShell(escapeShellCommand(params));
		if (ret.status == 0) return ret.output.strip;
		logDebug("'%s' failed with exit code %s: %s", params.join(" "), ret.status, ret.output.strip);
		return null;
	}

	auto tag = exec("git", git_dir_param, "describe", "--long", "--tags");
	if (tag !is null) {
		auto parts = tag.split("-");
		auto commit = parts[$-1];
		auto num = parts[$-2].to!int;
		tag = parts[0 .. $-2].join("-");
		if (tag.startsWith("v")) tag = tag[1 .. $];
		if (isValidVersion(tag)) {
			if (num == 0) return tag;
			else if (tag.canFind("+")) return format("%s.commit.%s.%s", tag, num, commit);
			else return format("%s+commit.%s.%s", tag, num, commit);
		}
	}

	auto branch = exec("git", git_dir_param, "rev-parse", "--abbrev-ref", "HEAD");
	if (branch !is null) {
		if (branch != "HEAD") return "~" ~ branch;
	}

	return null;
}
