module modA;

int addOne(int x) { return x + 1; }

@("Unittest A")
unittest {
    assert(addOne(1) == 2);
}
