module daughter.dummy;

version (Parent) {} else static assert(0, "Expected Parent to be set");
version (Daughter) {} else static assert(0, "Expected Daughter to be set");
version (Son) static assert(0, "Expected Son to no be set");
