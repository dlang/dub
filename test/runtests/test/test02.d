void main()
{
	import std.process, std.path, std.file, std.string;
	string binName = "../runtests";
	version (Windows)
		binName ~= ".exe";
	auto res = execute([binName, "--DRT-covopt=srcpath:..", "--DRT-covopt=merge:1"]);
	assert(res.status == 0);
	res = execute([binName, "42", "--DRT-covopt=srcpath:..", "--DRT-covopt=merge:1"]);
	assert(res.status == 42);
	res = execute([binName, "123", "test", "--DRT-covopt=srcpath:..", "--DRT-covopt=merge:1"]);
	assert(res.status == 123);
	assert(res.output.chomp == "test");
}
