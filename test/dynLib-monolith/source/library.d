module library;

export void foo()
{
    import inner_dep.mod;
    innerDepFunction();
}
