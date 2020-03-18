module daughter.dummy;

version (Parent) {} else static assert(0, "Expected Parent to be set");
version (Daughter) {} else static assert(0, "Expected Daughter to be set");
version (Son) static assert(0, "Expected Son to not be set");

debug (dParent) {} else static assert(0, "Expected dParent to be set");
debug (dDaughter) {} else static assert(0, "Expected dDaughter to be set");
debug (dSon) static assert(0, "Expected dSon to not be set");

version (Have_daughter) static assert(0, "Expected Have_daughter to not be set");
version (Have_son) static assert(0, "Expected Have_son to not be set");
