version (Parent) static assert(0, "Expected Parent to not be set");
version (SourceDep) {} else static assert(0, "Expected SourceDep to be set");

debug (dParent) static assert(0, "Expected dParent to not be set");
debug (dSourceDep) {} else static assert(0, "Expected dSourceDep to be set");

void main()
{
}
