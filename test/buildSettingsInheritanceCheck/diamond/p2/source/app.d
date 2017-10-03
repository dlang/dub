version (A) version (C) version (D) enum a = true;
version (B) enum a = false;

static assert(a);
