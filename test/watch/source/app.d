import counter, core.thread, std.stdio;

void main()
{
	static if (count < 3)
	{
		enum path = __FILE__[0 .. $ - "app.d".length] ~ "counter.d";
		File(path, "w").writefln("enum count = %s;", count + 1);
		Thread.sleep(10.seconds);
	}
}
