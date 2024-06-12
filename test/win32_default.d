/+ dub.json: {
   "name": "win32_default",
   "configurations": [
       {
           "name": "Default",
           "versions": [ "Default" ]
       },
       {
           "name": "MsCoff",
           "versions": [ "MsCoff" ]
       },
       {
           "name": "MsCoff64",
           "versions": [ "MsCoff", "Is64" ]
       }
   ]
} +/

module dynlib.app;

pragma(msg, "Frontend: ", __VERSION__);

// Object format should match the expectation
version (MsCoff)
{
    // Should be a 32 bit build
    version (Is64)  enum expSize = 8;
    else            enum expSize = 4;

    enum expFormat = "coff";
}
else version (Default)
{
    enum expSize = 4;
    enum expFormat = __VERSION__ >= 2099 ? "coff" : "omf";
}
else
{
    static assert(false, "Missing version flag!");
}

enum actFormat = __traits(getTargetInfo, "objectFormat");

static assert(actFormat == expFormat);
static assert((int*).sizeof == expSize);
