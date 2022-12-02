/** Some test code for ImportC */
module app.d;

import std.algorithm.iteration;
import std.array;
import std.conv;
import std.exception;
import std.range;
import std.stdio;
import std.string;

import some_c_code;

void main()
{
	doCCalls();
}

/// Call C functions in zstd_binding module
void doCCalls()
{
	relatedCode(42);

	ulong a = 3;
	uint b = 4;
	auto rs0 = multiplyU64byU32(&a, &b);
	writeln("Result of multiplyU64byU32(3,4) = ", rs0);

	uint[8] arr = [1, 2, 3, 4, 5, 6, 7, 8];
	auto rs1 = multiplyAndAdd(arr.ptr, arr.length, 3);
	writeln("Result of sum(%s*3) = ".format(arr), rs1);

	foreach (n; 1 .. 20)
	{
		writeln("fac(", n, ") = ", fac(n));
	}
}
