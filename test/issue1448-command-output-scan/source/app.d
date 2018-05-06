
void main() {}

unittest {
	enum str = import("file1") ~ import("file2") ~ import("file3") ~ import("file4");
	assert(str == "string from non-default dirs set with script.sh");
}
