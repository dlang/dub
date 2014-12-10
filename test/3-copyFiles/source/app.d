import std.algorithm, std.array, std.file, std.path;

void main(string[] args)
{
	immutable root = args[0].dirName; // get the bin dir
	immutable pfx = root.length + "/".length;
	auto files = dirEntries(root, SpanMode.breadth).map!(n => n[pfx .. $]).array.sort().release;

	assert(files ==
		[
			"copyfiles-test", "file_to_copy.txt", "file_to_copy_mask1.txt",
			"file_to_copy_mask2.txt", "hdpi", "hdpi/file1.txt", "hdpi/file2.txt",
			"hdpi/file3.txt", "hdpi/nested_dir", "hdpi/nested_dir/nested_file.txt",
			"ldpi", "ldpi/file1.txt", "ldpi/file2.txt", "ldpi/file3.txt", "mdpi",
			"mdpi/file1.txt", "mdpi/file2.txt", "mdpi/file3.txt", "res",
			"res/.nocopy", "res/.nocopy/file_inside_dot_prefixed_dir.txt",
			"res/hdpi", "res/hdpi/file1.txt", "res/hdpi/file2.txt", "res/hdpi/file3.txt",
			"res/hdpi/nested_dir", "res/hdpi/nested_dir/nested_file.txt", "res/i18n",
			"res/i18n/resource_en.txt", "res/i18n/resource_fr.txt", "res/ldpi",
			"res/ldpi/file1.txt", "res/ldpi/file2.txt", "res/ldpi/file3.txt", "res/mdpi",
			"res/mdpi/file1.txt", "res/mdpi/file2.txt", "res/mdpi/file3.txt"
		], files.join(", ")
	);
}
