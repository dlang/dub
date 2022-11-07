#!/usr/bin/env rdmd
/*******************************************************************************

    Standalone build script for DUB

    This script can be called from anywhere, as it deduces absolute paths
    based on the script's placement in the repository.

    Invoking it while making use of all the options would like like this:
    DMD=ldmd2 DFLAGS="-O -inline" ./build.d my-dub-version
    Using an environment variable for the version is also supported:
    DMD=dmd DFLAGS="-w -g" GITVER="1.2.3" ./build.d

    Copyright: D Language Foundation
    Authors: Mathias 'Geod24' Lang
    License: MIT

*******************************************************************************/
module build;

private:

import std.algorithm;
static import std.file;
import std.format;
import std.path;
import std.process;
import std.stdio;
import std.string;

/// Root of the `git` repository
immutable RootPath = __FILE_FULL_PATH__.dirName;
/// Path to the version file
immutable VersionFilePath = RootPath.buildPath("source", "dub", "version_.d");
/// Path to the file containing the files to be built
immutable SourceListPath = RootPath.buildPath("build-files.txt");
/// Path at which the newly built `dub` binary will be
version (Windows) {
	immutable DubBinPath = RootPath.buildPath("bin", "dub.exe");
} else {
	immutable DubBinPath = RootPath.buildPath("bin", "dub");
}

// Flags for DMD
immutable OutputFlag = "-of" ~ DubBinPath;
immutable IncludeFlag = "-I" ~ RootPath.buildPath("source");
immutable DefaultDFLAGS = [ "-g", "-O", "-w" ];


/// Entry point
int main(string[] args)
{
    // This does not have a 'proper' CLI interface, as it's only used in
    // special cases (e.g. package maintainers can use it for bootstrapping),
    // not for general / everyday usage by newcomer.
    // So the following is just an heuristic / best effort approach.
    if (args.canFind("--help", "/?", "-h"))
    {
        writeln("USAGE: ./build.d [compiler args (default:", DefaultDFLAGS, "]");
        writeln();
        writeln("  In order to build DUB, a version module must first be generated.");
        writeln("  If the GITVER environment variable is present, it will be used to generate the version module.");
        writeln("  Otherwise this script will look for a pre-existing version module.");
        writeln("  If no GITVER is provided and no version module exists, `git describe` will be called");
        writeln("  Build flags can be provided as arguments.");
        writeln("  LDC or GDC can be used by setting the `DMD` value to " ~
                "`ldmd2` and `gdmd` (or their path), respectively.");
        return 1;
    }

    immutable dubVersion = environment.get("GITVER", "");
    if (!writeVersionFile(dubVersion))
        return 1;

    immutable dmd = getCompiler();
    if (!dmd.length) return 1;
    const dflags = args.length > 1 ? args[1 .. $] : DefaultDFLAGS;

    // Compiler says no to immutable (because it can't handle the appending)
    const command = [
        dmd,
        OutputFlag, IncludeFlag,
        "-version=DubUseCurl", "-version=DubApplication",
        ] ~ dflags ~ [ "@build-files.txt" ];

    writeln("Building dub using ", dmd, " (dflags: ", dflags, "), this may take a while...");
    auto proc = execute(command);
    if (proc.status != 0)
    {
        writeln("Command `", command, "` failed, output was:");
        writeln(proc.output);
        return 1;
    }

    writeln("DUB has been built as: ", DubBinPath);
    version (Posix)
        writeln("You may want to run `sudo ln -s ", DubBinPath, " /usr/local/bin` now");
    else version (Windows)
        writeln("You may want to add the following entry to your PATH " ~
                "environment variable: ", DubBinPath);
    return 0;
}

/**
   Generate the version file describing DUB's version / commit

   Params:
     dubVersion = User provided version file. Can be `null` / empty,
                  in which case the existing file (if any) takes precedence,
                  or the version is infered with `git describe`.
                  A non-empty parameter will always override the existing file.
 */
bool writeVersionFile(string dubVersion)
{
    if (!dubVersion.length)
    {
        if (std.file.exists(VersionFilePath))
        {
            writeln("Using pre-existing version file. To force a rebuild, " ~
                    "provide an explicit version (first argument) or remove: ",
                    VersionFilePath);
            return true;
        }

        auto pid = execute(["git", "describe"]);
        if (pid.status != 0)
        {
            writeln("Could not determine version with `git describe`. " ~
                    "Make sure 'git' is installed and this is a git repository. " ~
                    "Alternatively, you can provide a version explicitly via the " ~
                    "`GITVER environment variable or pass it as the first " ~
                    "argument to this script");
            return false;
        }
        dubVersion = pid.output.strip();
    }

    try
    {
        std.file.write(VersionFilePath, q{
/**
   DUB version file

   This file is auto-generated by 'build.d'. DO NOT EDIT MANUALLY!
 */
module dub.version_;

enum dubVersion = "%s";
}.format(dubVersion));
        writeln("Wrote version_.d` file with version: ", dubVersion);
        return true;
    }
    catch (Exception e)
    {
        writeln("Writing version file to '", VersionFilePath, "' failed: ", e.msg);
        return false;
    }
}

/**
   Detect which compiler is available

   Default to DMD, then LDC (ldmd2), then GDC (gdmd).
   If none is in the PATH, an error will be thrown.

   Note:
     It would be optimal if we could get the path of the compiler
     invoking this script, but AFAIK this isn't possible.
 */
string getCompiler ()
{
    auto env = environment.get("DMD", "");
    // If the user asked for a compiler explicitly, respect it
    if (env.length)
        return env;

    static immutable Compilers = [ "dmd", "ldmd2", "gdmd" ];
    foreach (bin; Compilers)
    {
        try
        {
            auto pid = execute([bin, "--version"]);
            if (pid.status == 0)
                return bin;
        }
        catch (Exception e)
            continue;
    }
    writeln("No compiler has been found in the PATH. Attempted values: ", Compilers);
    writeln("Make sure one of those is in the PATH, or set the `DMD` variable");
    return null;
}
