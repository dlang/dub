module son.dummy;

version (Parent) {} else static assert(0, "Expected Parent to be set");
version (Daughter) static assert(0, "Expected Daughter to not be set");
version (Son) {} else static assert(0, "Expected Son to be set");
