module diamond.dummy;

template hasVersion(string v)
{
	mixin("version ("~v~") enum hasVersion = true; else enum hasVersion = false;");
}

template hasDebugVersion(string v)
{
	mixin("debug ("~v~") enum hasDebugVersion = true; else enum hasDebugVersion = false;");
}

// checking inference here
version (Parent) {} else static assert(0, "Expected Parent to be set");
version (Daughter) {} else static assert(0, "Expected Daughter to be set");
static assert(!hasVersion!"Son");
static assert(!hasVersion!"Diamond");

debug (dParent) {} else static assert(0, "Expected dParent to be set");
static assert(!hasDebugVersion!"dDaughter");
debug (dSon) {} else static assert(0, "Expected dSon to be set");
static assert(!hasDebugVersion!"dDiamond");

static assert(!hasVersion!"Have_daughter");
static assert(!hasVersion!"Have_son");
static assert(!hasVersion!"Have_diamond");
