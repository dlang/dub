version (Parent) {} else static assert(0, "Expected Parent to be set"); // local
version (Daughter) {} else static assert(0, "Expected Daughter to not be set"); // via dependency
version (Son) {} else static assert(0, "Expected Son to not be set"); // via dependency
version (Diamond) static assert(0, "Expected Diamond to not be set"); // unused by dependencies

debug (dParent) {} else static assert(0, "Expected dParent to be set"); // local
debug (dDaughter) {} else static assert(0, "Expected dDaughter to be set"); // via dependency
debug (dSon) {} else static assert(0, "Expected dSon to not be set"); // via dependency
debug (dDiamond) static assert(0, "Expected dDiamond to not be set"); // unused by dependencies

version (Have_daugther) static assert(0, "Expected Have_daugther to not be set");
version (Have_son) static assert(0, "Expected Have_son to not be set");
version (Have_diamond) static assert(0, "Expected Have_diamond to not be set");

void main()
{
}
