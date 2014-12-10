import std.stdio;

import std.process : execute;
int main(string[] args)
{
    writefln("Executing init test - fail");
    auto script = args[0] ~ ".sh";
    auto dubInit = execute(script);
    return dubInit.status;
}
