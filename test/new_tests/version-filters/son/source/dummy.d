module son.dummy;

version (Parent) static assert(0, "Expected Parent to not be set");
version (Daughter) static assert(0, "Expected Daughter to not be set");
version (Son) {} else static assert(0, "Expected Son to be set");

debug (dParent) static assert(0, "Expected dParent to not be set");
debug (dDaughter) static assert(0, "Expected dDaughter to not be set");
debug (dSon) {} else static assert(0, "Expected dSon to be set");

version (Have_daughter) static assert(0, "Expected Have_daughter to not be set");
version (Have_son) static assert(0, "Expected Have_son to not be set");
