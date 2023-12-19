/*******************************************************************************

    Represent a target platform

    Platform informations can be embedded in recipe, such that some settings
    only target a certain platform (e.g. sourceFiles, lflags, etc...).
    The struct in this module represent that information, structured.

*******************************************************************************/

module dub.data.platform;

/// Represents a platform a package can be build upon.
struct BuildPlatform {
	/// Special constant used to denote matching any build platform.
	enum any = BuildPlatform(null, null, null, null, -1);

	/// Platform identifiers, e.g. ["posix", "windows"]
	string[] platform;
	/// CPU architecture identifiers, e.g. ["x86", "x86_64"]
	string[] architecture;
	/// Canonical compiler name e.g. "dmd"
	string compiler;
	/// Compiler binary name e.g. "ldmd2"
	string compilerBinary;
	/// Compiled frontend version (e.g. `2067` for frontend versions 2.067.x)
	int frontendVersion;
	/// Compiler version e.g. "1.11.0"
	string compilerVersion;
	/// Frontend version string from frontendVersion
	/// e.g: 2067 => "2.067"
	string frontendVersionString() const
	{
		import std.format : format;

		const maj = frontendVersion / 1000;
		const min = frontendVersion % 1000;
		return format("%d.%03d", maj, min);
	}
	///
	unittest
	{
		BuildPlatform bp;
		bp.frontendVersion = 2067;
		assert(bp.frontendVersionString == "2.067");
	}

	/// Checks to see if platform field contains windows
	bool isWindows() const {
		import std.algorithm : canFind;
		return this.platform.canFind("windows");
	}
	///
	unittest {
		BuildPlatform bp;
		bp.platform = ["windows"];
		assert(bp.isWindows);
		bp.platform = ["posix"];
		assert(!bp.isWindows);
	}
}

/** Matches a platform specification string against a build platform.

	Specifications are build upon the following scheme, where each component
	is optional (indicated by []), but the order is obligatory:
	"[-platform][-architecture][-compiler]"

	So the following strings are valid specifications: `"-windows-x86-dmd"`,
	`"-dmd"`, `"-arm"`, `"-arm-dmd"`, `"-windows-dmd"`

	Params:
		platform = The build platform to match against the platform specification
	    specification = The specification being matched. It must either be an
			empty string or start with a dash.

	Returns:
	    `true` if the given specification matches the build platform, `false`
	    otherwise. Using an empty string as the platform specification will
	    always result in a match.
*/
bool matchesSpecification(in BuildPlatform platform, const(char)[] specification)
{
    import std.range : empty;
	import std.string : chompPrefix, format;
	import std.algorithm : canFind, splitter;
	import std.exception : enforce;

	if (specification.empty) return true;
	if (platform == BuildPlatform.any) return true;

	auto splitted = specification.chompPrefix("-").splitter('-');
	enforce(!splitted.empty, format("Platform specification, if present, must not be empty: \"%s\"", specification));

	if (platform.platform.canFind(splitted.front)) {
		splitted.popFront();
		if (splitted.empty)
			return true;
	}
	if (platform.architecture.canFind(splitted.front)) {
		splitted.popFront();
		if (splitted.empty)
			return true;
	}
	if (platform.compiler == splitted.front) {
		splitted.popFront();
		enforce(splitted.empty, "No valid specification! The compiler has to be the last element: " ~ specification);
		return true;
	}
	return false;
}

///
unittest {
	auto platform = BuildPlatform(["posix", "linux"], ["x86_64"], "dmd");
	assert(platform.matchesSpecification(""));
	assert(platform.matchesSpecification("posix"));
	assert(platform.matchesSpecification("linux"));
	assert(platform.matchesSpecification("linux-dmd"));
	assert(platform.matchesSpecification("linux-x86_64-dmd"));
	assert(platform.matchesSpecification("x86_64"));
	assert(!platform.matchesSpecification("windows"));
	assert(!platform.matchesSpecification("ldc"));
	assert(!platform.matchesSpecification("windows-dmd"));

	// Before PR#2279, a leading '-' was required
	assert(platform.matchesSpecification("-x86_64"));
}
