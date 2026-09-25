/**
	Local at-rest protection helpers for registry credentials.

	Passwords cannot be stored as one-way hashes if they must be sent to the
	registry later. On Windows the secret is protected with DPAPI (bound to the
	current user). Elsewhere it is Base64-encoded for file storage (callers
	should use mode 0600).

	Copyright: © 2026 DUB contributors
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module dub.registry_secrets;

import std.base64;
import std.exception : enforce;
import std.string : representation;

/**
	Protect a secret for local at-rest storage.

	Passwords cannot be stored as one-way hashes if they must be sent to the
	registry later. Industry practice for reusable login secrets is OS-backed
	reversible protection (Windows DPAPI) or a vault/keyring.
*/
string protectSecret(string plaintext)
{
	version (Windows)
		return "dpapi:" ~ cast(string) Base64.encode(dpapiProtect(plaintext.representation));
	else
		return "file:" ~ cast(string) Base64.encode(cast(immutable(ubyte)[]) plaintext.representation);
}

/// Reverse of protectSecret. Throws if the blob cannot be unlocked on this machine/user.
string unprotectSecret(string stored)
{
	import std.algorithm : startsWith;
	if (stored.startsWith("dpapi:"))
	{
		version (Windows)
			return cast(string) dpapiUnprotect(Base64.decode(stored[6 .. $]));
		else
			throw new Exception("Credential was protected with Windows DPAPI; cannot unlock here");
	}
	if (stored.startsWith("file:"))
		return cast(string) Base64.decode(stored[5 .. $]);
	// Legacy plaintext line (pre-protected store)
	return stored;
}

bool isProtectedSecret(string stored)
{
	import std.algorithm : startsWith;
	return stored.startsWith("dpapi:") || stored.startsWith("file:");
}

version (Windows)
{
	pragma(lib, "crypt32");

	import core.sys.windows.windows;

	private struct DATA_BLOB
	{
		DWORD cbData;
		BYTE* pbData;
	}

	private extern (Windows) @nogc nothrow
	{
		BOOL CryptProtectData(DATA_BLOB* pDataIn, LPCWSTR szDataDescr, DATA_BLOB* pOptionalEntropy,
			PVOID pvReserved, void* pPromptStruct, DWORD dwFlags, DATA_BLOB* pDataOut);
		BOOL CryptUnprotectData(DATA_BLOB* pDataIn, LPWSTR* ppszDataDescr, DATA_BLOB* pOptionalEntropy,
			PVOID pvReserved, void* pPromptStruct, DWORD dwFlags, DATA_BLOB* pDataOut);
	}

	private enum CRYPTPROTECT_UI_FORBIDDEN = 0x1;

	private ubyte[] dpapiProtect(const(ubyte)[] data)
	{
		DATA_BLOB input;
		input.cbData = cast(DWORD) data.length;
		input.pbData = cast(BYTE*) data.ptr;

		DATA_BLOB output;
		auto ok = CryptProtectData(&input, null, null, null, null, CRYPTPROTECT_UI_FORBIDDEN, &output);
		enforce(ok != FALSE, "CryptProtectData failed (Windows DPAPI)");
		scope (exit) LocalFree(cast(HLOCAL) output.pbData);

		auto copy = new ubyte[](output.cbData);
		copy[] = (cast(ubyte*) output.pbData)[0 .. output.cbData];
		return copy;
	}

	private ubyte[] dpapiUnprotect(const(ubyte)[] data)
	{
		DATA_BLOB input;
		input.cbData = cast(DWORD) data.length;
		input.pbData = cast(BYTE*) data.ptr;

		DATA_BLOB output;
		auto ok = CryptUnprotectData(&input, null, null, null, null,
			CRYPTPROTECT_UI_FORBIDDEN, &output);
		enforce(ok != FALSE, "CryptUnprotectData failed — credential may belong to another Windows user");
		scope (exit) LocalFree(cast(HLOCAL) output.pbData);

		auto copy = new ubyte[](output.cbData);
		copy[] = (cast(ubyte*) output.pbData)[0 .. output.cbData];
		return copy;
	}
}

/// Read a password from a file (first line, trimmed). Prefer this over `-p` for agents/scripts.
string readPasswordFile(string path)
{
	import std.file : exists, readText;
	import std.range : empty, front;
	import std.string : chomp, lineSplitter, strip;
	enforce(path.length, "password file path is empty");
	enforce(exists(path), "password file not found: " ~ path);
	auto text = readText(path);
	auto lines = text.lineSplitter;
	enforce(!lines.empty, "password file is empty: " ~ path);
	auto pw = lines.front.chomp.strip;
	enforce(pw.length, "password file first line is empty: " ~ path);
	return pw;
}

/// Read a password from the console without echoing (TTY). Opt-in via --prompt-password.
string promptPassword(string prompt = "Password: ")
{
	import std.stdio : stderr, stdin;
	import std.string : chomp;

	stderr.write(prompt);
	stderr.flush();

	version (Windows)
	{
		import core.sys.windows.winbase : GetStdHandle, INVALID_HANDLE_VALUE, STD_INPUT_HANDLE;
		import core.sys.windows.wincon : ENABLE_ECHO_INPUT, GetConsoleMode, SetConsoleMode;
		import core.sys.windows.windef : DWORD;

		auto hIn = GetStdHandle(STD_INPUT_HANDLE);
		DWORD mode = 0;
		bool toggled;
		if (hIn !is null && hIn !is INVALID_HANDLE_VALUE && GetConsoleMode(hIn, &mode))
		{
			auto newMode = mode & ~ENABLE_ECHO_INPUT;
			if (SetConsoleMode(hIn, newMode))
				toggled = true;
		}
		scope (exit)
		{
			if (toggled)
				SetConsoleMode(hIn, mode);
			stderr.writeln();
		}
		return stdin.readln().chomp;
	}
	else
	{
		import core.sys.posix.termios;
		import core.sys.posix.unistd : STDIN_FILENO, isatty;

		termios oldt;
		bool toggled;
		if (isatty(STDIN_FILENO))
		{
			if (tcgetattr(STDIN_FILENO, &oldt) == 0)
			{
				auto newt = oldt;
				newt.c_lflag &= ~(ECHO);
				if (tcsetattr(STDIN_FILENO, TCSANOW, &newt) == 0)
					toggled = true;
			}
		}
		scope (exit)
		{
			if (toggled)
				tcsetattr(STDIN_FILENO, TCSANOW, &oldt);
			stderr.writeln();
		}
		return stdin.readln().chomp;
	}
}

unittest
{
	import std.algorithm : startsWith;
	import std.file : remove, tempDir, write;
	import std.path : buildPath;

	auto stored = protectSecret("unit-test-secret");
	version (Windows)
		assert(stored.startsWith("dpapi:"));
	else
		assert(stored.startsWith("file:"));
	assert(unprotectSecret(stored) == "unit-test-secret");
	assert(unprotectSecret("legacy-plain") == "legacy-plain");

	auto path = buildPath(tempDir(), "dub-registry-pw-test.txt");
	write(path, "file-secret\nignored\n");
	scope (exit)
		remove(path);
	assert(readPasswordFile(path) == "file-secret");
}
