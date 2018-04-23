
void main() {}

unittest {
	assert(import("file") == "string from non-default dir set with script.sh");
}
