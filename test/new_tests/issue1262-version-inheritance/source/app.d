version (Parent) {} else static assert(0, "Expected Parent to be set");
version (Daughter) {} else static assert(0, "Expected Daughter to be set");
version (Son) {} else static assert(0, "Expected Son to be set");

void main()
{
}
