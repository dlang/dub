/*******************************************************************************

    Functions and types used to test dub

*******************************************************************************/

module dub.test.base;

version (unittest):

import dub.dub;

public import std.algorithm;
import std.exception;
public static import std.file;
public import std.path;

import core.sys.posix.stdlib;
import core.sys.posix.unistd;

/*******************************************************************************

    Run a full-fledged Dub binary

    This allow to do end-to-end testing for dub. Ideally, it should be seldom
    used, if at all, but dub currently doesn't do a good job at having its
    dependencies being injectable.

    Note that to ensure proper cleanup after itself, it is best to instantiate
    this class on the stack, as follow:
    ```
    unitest {
        scope dub = new TestCLIApp();
        auto res = dub.run(["init", "-n", "pack"]);
        assert(res.status == 0);
        assert(res.stdout.length != 0);
        assert(res.stderr.length == 0);
        assert(std.file.exists(dub.path.buildPath("pack", "dub.json")));
        // At the end of this scope, folder `dub.path()` points to will be deleted
    }
    ```

*******************************************************************************/

public class TestCLIApp
{
    /// Directory in which this application will run
    private string dir;

    ///
    public this ()
    {
        static immutable Pattern = "/tmp/dub-testsuite-XXXXXX";
        char[256] buffer = 0;
        buffer[0 .. Pattern.length] = Pattern;
        enforce(mkdtemp(buffer.ptr) !is null, "Calling `mkdtemp` failed");
        // Ensure we have a terminating \0 so we can call C API,
        // but let it outside the slice to avoid tripping up D functions
        this.dir = cast(string) (buffer[0 .. Pattern.length] ~ "/\0")[0 .. $ - 1];
    }

    public ~this ()
    {
        // destroy dir
        std.file.rmdirRecurse(this.dir);
        this.dir = null;
    }

    /// Run the application with the provided arguments
    public Result run (string[] args, string stdin = null)
    {
        int[2][3] stdfd;
        foreach (ref fdp; stdfd)
            enforce(pipe(fdp) != -1, "Calling `pipe()` on an fd pair failed");

        int pid = fork();
        enforce(pid != -1, "Calling `fork()` failed");

        if (pid == 0)
            return this.runChild(args, stdfd);
        else
            return this.runParent(pid, stdfd, stdin);
    }

    /// Child part of the `fork()` performed in `run`
    private Result runChild(scope string[] args, int[2][3] stdfd)
    {
        import dub.commandline : runDubCommandLine;

        // Prepare stdin, stdout, stderr
        close(stdfd[0][1]);
        close(stdfd[1][0]);
        close(stdfd[2][0]);
        dup2(stdfd[0][0], STDIN_FILENO);
        dup2(stdfd[1][1], STDOUT_FILENO);
        dup2(stdfd[2][1], STDERR_FILENO);

        chdir(this.dir.ptr);
        _exit(runDubCommandLine("dub" ~ args));
        assert(0);
    }

    /// Parent part of the `fork()` performed in `run`
    private Result runParent(int pid, int[2][3] stdfd, string stdin)
    {
        int wstatus;
        close(stdfd[0][0]);
        close(stdfd[1][1]);
        close(stdfd[2][1]);

        if (stdin.length)
            write(stdfd[0][1], stdin.ptr, stdin.length);

        enforce(waitpid(pid, &wstatus, 0) == pid, "Calling `waitpid()` failed");
        Result res;
        if (WIFEXITED(wstatus))
            res.status = WEXITSTATUS(wstatus);
        else if (WIFSIGNALED(wstatus))
            res.status = WTERMSIG(wstatus);
        else
            enforce(0, "Termination method not supported");

        res.stdout = drain(stdfd[1][0]);
        res.stderr = drain(stdfd[2][0]);

        close(stdfd[0][1]);
        close(stdfd[1][0]);
        close(stdfd[2][0]);
        return res;
    }

    /// Returns: The path of the temporary directory created for this instance
    public string path () const @safe pure nothrow @nogc
    {
        return this.dir;
    }

    /// Returns: A `Dub` class initialized to point to `path`
    public Dub makeLib (string path = path())
    {
        return new Dub(path);
    }
}

///
public struct Result
{
    /// Exit code (positive) or signal that terminated the process (negative)
    public int status;

    /// Content of stdout
    public string stdout;

    /// Content of stderr
    public string stderr;

    /// Debugging utility
    public void dump () const @safe
    {
        import std.stdio : writeln;

        writeln("Exit code: ", this.status);
        writeln("===== STDOUT =====");
        writeln(this.stdout);
        writeln("===== STDERR =====");
        writeln(this.stderr);
        writeln("==================");
    }
}

/// Drain a file descriptor of its content and returns it
private string drain (int fd)
{
    ssize_t size;
    string result;
    char[4096] buffer;
    do {
        size = read(fd, buffer.ptr, buffer.length);
        enforce(size != -1, "Error while draining file description");
        result ~= buffer[0 .. size];
    } while (size == buffer.length);
    return result;
}
