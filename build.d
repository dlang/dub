#!/usr/bin/env rdmd
/*******************************************************************************

    Standalone build script for DUB

    This script can be called from anywhere, as it deduces absolute paths
    based on the script's placement in the repository.

    Invoking it while making use of all the options would like like this:
    DUB= dub DMD=ldmd2 GITVER="1.2.3" ./build.d -b release

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
/// Path at which the newly built `dub` binary will be
immutable DubBinPath = RootPath.buildPath("bin", "dub");

// Flags for DMD
immutable OutputFlag = "-of" ~ DubBinPath;
immutable IncludeFlag = "-I" ~ RootPath.buildPath("source");

/// Entry point
int main(string[] args)
{
    // This does not have a 'proper' CLI interface, as it's only used in
    // special cases (e.g. package maintainers can use it for bootstrapping),
    // not for general / everyday usage by newcomer.
    // So the following is just an heuristic / best effort approach.
    if (args.canFind("--help", "/?", "-h"))
    {
        writeln("USAGE: ./build.d [dub args]");
        writeln();
        writeln("  DUB is self hosted since v1.22.0. A `dub` binary is required to build it.");
        writeln("  The host DUB can be specified via the environment variables `HOST_DUB` or `DUB`.");
        writeln("  If not present, it will be looked up in the PATH.");
        writeln("  Those host dub's default compiler will be used, unless `DC`, ",
                "`HOST_DC` (for compatibility with DMD build process), or `DMD` ",
                "(for legacy reason) is provided.");
        writeln("  Additionally, if a compiler is provided, a `dub` instance will ",
                "be looked up in the same folder before the `dub` in the path is attempted.");
        writeln("  Any extra argument will be provided verbatim to dub: this can be used e.g. ",
                "to use a specific build mode (`-b release`)");
        writeln();
        writeln("  In order to build DUB, a version module must also be generated.");
        writeln("  If the GITVER environment variable is present, it will be used to generate the version module.");
        writeln("  Otherwise this script will look for a pre-existing version module.");
        writeln("  If no GITVER is provided and no version module exists, `git describe` will be called");
        return 1;
    }

    immutable hostTools = getHostTools();
    if (!hostTools.dub.length)
        return 1;

    immutable dubVersion = environment.get("GITVER", "");
    if (!writeVersionFile(dubVersion))
        return 1;

    const extraArgs = args[1 .. $];

    // Compiler says no to immutable (because it can't handle the appending)
    const(string)[] command = [ hostTools.dub, "--root", RootPath, "build" ] ~ extraArgs;
    if (hostTools.dc.length)
        command ~= ("--compiler=" ~ hostTools.dc);

    writefln("Building dub using %s (compiler: %s%s%(s %)), this may take a while...",
             hostTools.dub, hostTools.dc.length ? hostTools.dc : "default",
             (extraArgs.length ? ", extra arguments: " : ""),
             (extraArgs.length ? extraArgs : null));

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
   Detect which `dub` && compiler is available

   Since v1.22.0, `dub` is self-hosted.
   In order for one to be able to build `dub`, a previously-built
   version of `dub` is needed. Usage of v1.21.0 is recommended.

   To provide a custom dub, the user has to set the `HOST_DUB` env variable.
   Alternatively, if the user provides a custom compiler, the `dub` instance
   adjacent to it will be used. If none is available, the path will be looked
   up as a last resort.
   A user may provide a custom compiler, or use the default detected by `dub`.
   Examples include using LDC with a DMD-packaged `dub`, or using LDC
   with an independent `dub` that defaults to DMD or GDC.

   Default to DMD, then LDC (ldmd2), then GDC (gdmd).
   If none is in the PATH, an error will be thrown.

   Returns:
     A struct containing the needed host tools.
 */
HostTools getHostTools ()
{
    HostTools result;

    // If the user asked for a compiler explicitly, respect it
    // DC is the 'standard' variable name for a D compiler
    if (auto env_dc = environment.get("DC", null))
        result.dc = env_dc;
    // This is used by the DMD build process
    else if (auto env_host_dc = environment.get("HOST_DC", null))
        result.dc = env_host_dc;
    // Support legacy name
    else if (auto env_dmd = environment.get("DMD", null))
        result.dc = env_dmd;

    if (result.dc.length && !checkRun(result.dc))
    {
        writeln("Error: A compiler was provided via environment variable (",
                result.dc, ") but it does not execute with `--versiion`");
        return HostTools.init;
    }

    // Check for user-provided `dub`
    // Notice the priority is inversed between `DUB` and `HOST_DUB`.
    // This is because we don't want to conflict with a user setting:
    // the `HOST_` prefix is used *when building the tool itself*.
    if (auto env_host_dub = environment.get("HOST_DUB", null))
        result.dub = env_host_dub;
    else if (auto env_dub = environment.get("DUB", null))
        result.dub = env_dub;

    if (result.dub.length)
    {
        if (auto working = checkRun(result.dub))
            return result;
        writeln("The provided dub executable (via `HOST_DUB` or `DUB`) doesn't seem to work");
        writeln("Tried command: ", result.dub, " --version");
        return HostTools.init;
    }

    // If it wasn't specified explicitly by the user, but the user supplied
    // a compiler, try that
    // Note that if the user gave a compiler in the path (e.g. `ldc2`), and
    // dub lives next to it, then `dub` should be in the path, too,
    // hence the `std.file.exists` call.
    string errMsg = "";
    if (std.file.exists(result.dc))
    {
        if (auto working = checkRun(result.dc.dirName.buildPath("dub")))
        {
            result.dub = working;
            return result;
        }
        // Provide user friendly error message
        errMsg = "no working `dub` executable was found next to \"" ~
            result.dc ~ "\", ";
    }

    // Finally, try to get it from the path
    if (auto path_dub = checkRun("dub"))
    {
        result.dub = path_dub;
        return result;
    }

    writeln("Error: No `HOST_DUB` or `DUB` environement variable was provided, ",
            errMsg, "and `dub` was not found in `PATH`");
    writeln("`dub` is self hosted since v1.22.0. Please provide a binary to build");
    writeln("If you don't have any, you can download one from https://dlang.org ",
            "or by using the `install.sh` script (also available on dlang.org");
    writeln("Alternatively, you can bootstrap by checking out v1.21.0 and running this script.");
    return HostTools.init;
}

struct HostTools
{
    /// Host dub, cannot be null
    string dub;
    /// Host compiler, can be null
    string dc;
}

/// Check if the provided program runs by calling `--version`.
/// Returns: `bin` if it does, `null` otherwise
string checkRun (string bin) nothrow @safe
{
    try
    {
        auto pid = execute([bin, "--version"]);
        if (pid.status == 0)
            return bin;
    }
    catch (Exception e) {}
    return null;
}
