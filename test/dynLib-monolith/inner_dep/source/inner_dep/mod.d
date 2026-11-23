module inner_dep.mod;

void innerDepFunction()
{
    import staticlib.app;
    entry();
}
