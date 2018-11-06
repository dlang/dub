module son.dummy;

version (Parent) {} else static assert(0, "Expected Parent to be set"); // via dependency
version (Daughter) {} else static assert(0, "Expected Daughter to not be set"); // via diamond dependency
version (Son) {} else static assert(0, "Expected Son to be set"); // local
version (Diamond) static assert(0, "Expected Diamond to not be set");

debug (dParent) {} else static assert(0, "Expected dParent to be set"); // via dependency
debug (dDaughter) static assert(0, "Expected dDaughter to not be set"); // via diamond dependency
debug (dSon) {} else static assert(0, "Expected dSon to be set"); // local
debug (dDiamond) static assert(0, "Expected dDiamond to not be set");

version (Have_daughter) static assert(0, "Expected Have_daughter to not be set");
version (Have_son) static assert(0, "Expected Have_son to not be set");
version (Have_diamond) static assert(0, "Expected Have_diamond to not be set");
