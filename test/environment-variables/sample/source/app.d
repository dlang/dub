import std.stdio;
import std.process;

void main()
{
	writeln("app.run: ", environment.get("VAR1", ""));
	writeln("app.run: ", environment.get("VAR2", ""));
	writeln("app.run: ", environment.get("VAR3", ""));
	writeln("app.run: ", environment.get("VAR4", ""));
	writeln("app.run: ", environment.get("VAR5", ""));
	writeln("app.run: ", environment.get("SYSENVVAREXPCHECK", ""));
}
