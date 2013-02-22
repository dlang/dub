/**
	Downloading and uploading of data from/to URLs.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.inet.urltransfer;

import vibe.core.log;
import vibe.core.file;
import vibe.inet.url;

import std.exception;
import std.net.curl;
import std.string;


/**
	Downloads a file from the specified URL.

	Any redirects will be followed until the actual file resource is reached or if the redirection
	limit of 10 is reached. Note that only HTTP(S) is currently supported.
*/
void download(string url, string filename)
{
	std.net.curl.download(url, filename);
}

/// ditto
void download(Url url, Path filename)
{
	download(url.toString(), filename.toNativeString());
}
