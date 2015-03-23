// need module declarations as '.' is not allowed in module names
module hidden;
static assert(0, "Dub should not compile "~__FILE__~".");
