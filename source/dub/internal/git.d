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

	if (const describeOutput = exec("git", git_dir_param, "describe", "--long", "--tags")) {
		if (const ver = determineVersionFromGitDescribe(describeOutput))
			return ver;
	}

	auto branch = exec("git", git_dir_param, "rev-parse", "--abbrev-ref", "HEAD");
	if (branch !is null) {
		if (branch != "HEAD") return "~" ~ branch;
	}

	return null;
}

private string determineVersionFromGitDescribe(string describeOutput)
{
	import dub.semver : isValidVersion;
	import std.conv : to;

	const parts = describeOutput.split("-");
	const commit = parts[$-1];
	const num = parts[$-2].to!int;
	const tag = parts[0 .. $-2].join("-");
	if (tag.startsWith("v") && isValidVersion(tag[1 .. $])) {
		if (num == 0) return tag[1 .. $];
		const i = tag.indexOf('+');
		return format("%s%scommit.%s.%s", tag[1 .. $], i >= 0 ? '.' : '+', num, commit);
	}
	return null;
}

unittest {
	// tag v1.0.0
	assert(determineVersionFromGitDescribe("v1.0.0-0-deadbeef") == "1.0.0");
	// 1 commit after v1.0.0
	assert(determineVersionFromGitDescribe("v1.0.0-1-deadbeef") == "1.0.0+commit.1.deadbeef");
	// tag v1.0.0+2.0.0
	assert(determineVersionFromGitDescribe("v1.0.0+2.0.0-0-deadbeef") == "1.0.0+2.0.0");
	// 12 commits after tag v1.0.0+2.0.0
	assert(determineVersionFromGitDescribe("v1.0.0+2.0.0-12-deadbeef") == "1.0.0+2.0.0.commit.12.deadbeef");
	// tag v1.0.0-beta.1
	assert(determineVersionFromGitDescribe("v1.0.0-beta.1-0-deadbeef") == "1.0.0-beta.1");
	// 2 commits after tag v1.0.0-beta.1
	assert(determineVersionFromGitDescribe("v1.0.0-beta.1-2-deadbeef") == "1.0.0-beta.1+commit.2.deadbeef");
	// tag v1.0.0-beta.2+2.0.0
	assert(determineVersionFromGitDescribe("v1.0.0-beta.2+2.0.0-0-deadbeef") == "1.0.0-beta.2+2.0.0");
	// 3 commits after tag v1.0.0-beta.2+2.0.0
	assert(determineVersionFromGitDescribe("v1.0.0-beta.2+2.0.0-3-deadbeef") == "1.0.0-beta.2+2.0.0.commit.3.deadbeef");

	// invalid tags
	assert(determineVersionFromGitDescribe("1.0.0-0-deadbeef") is null);
	assert(determineVersionFromGitDescribe("v1.0-0-deadbeef") is null);
}

/** Clones a repository into a new directory.

	Params:
		remote = The (possibly remote) repository to clone from
		reference = The branch to check out after cloning
		destination = Repository destination directory

	Returns:
		Whether the cloning succeeded.
*/
bool cloneRepository(string remote, string reference, string destination)
{
	import std.process : Pid, spawnProcess, wait;

	Pid command;

	if (!exists(destination)) {
		string[] args = ["git", "clone", "--no-checkout"];
		if (getLogLevel > LogLevel.diagnostic) args ~= "-q";

		command = spawnProcess(args~[remote, destination]);
		if (wait(command) != 0) {
			return false;
		}
	}

	string[] args = ["git", "-C", destination, "checkout", "--detach"];
	if (getLogLevel > LogLevel.diagnostic) args ~= "-q";
	command = spawnProcess(args~[reference]);

	if (wait(command) != 0) {
		rmdirRecurse(destination);
		return false;
	}

	return true;
}
