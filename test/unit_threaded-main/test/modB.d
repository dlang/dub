module modB;

@("Unittest B")
unittest {
    import modA;
    assert(addOne(2) == 3);
}
