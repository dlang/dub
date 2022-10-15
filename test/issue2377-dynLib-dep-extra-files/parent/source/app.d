module app;

// Add a dummy export to enforce creation of import .lib and .exp file for the (Windows) executable.
// They shouldn't be copied to the output dir though.
export void dummy() {}

void main() {
    import parent;
    parent_bar();
    dummy();
}
