#!/usr/bin/env dub
/+dub.sdl:
dependency "vibe-d" version="~>0.8.5"
versions "VibeNoSSL"
+/

import vibe.d;

/*
Provide a special API File Handler as Vibe.d's builtin serveStaticFiles
doesn't deal well with query params.
This will blindly check if the requestURI payload exists on the filesystem and if so, return the file.

It replaces `?` with `__` for Windows compatibility.

Params:
    skip = initial part of the requestURI to skip over
    folder = the base directory from which to serve API requests from
*/
auto apiFileHandler(string skip, string folder) {
    import std.functional : toDelegate;
    void handler(HTTPServerRequest req, HTTPServerResponse res) {
        import std.algorithm : skipOver;
        import std.path : buildPath;
        import std.file : exists;
        // ? can't be part of path names on Windows
        auto requestURI = req.requestURI.replace("?", "__");
        requestURI.skipOver(skip);
        const reqFile = buildPath(folder, requestURI);
        if (reqFile.exists) {
            return req.sendFile(res, PosixPath(reqFile));
        }
    }
    return toDelegate(&handler);
}

void main(string[] args)
{
	import std.conv;
	immutable folder = readRequiredOption!string("folder", "Folder to service files from.");
	immutable port = readRequiredOption!ushort("port", "Port to use");
	auto router = new URLRouter;
	router.get("stop", (HTTPServerRequest req, HTTPServerResponse res){
		res.writeVoidBody;
		exitEventLoop();
	});
	router.get("/packages/gitcompatibledubpackage/1.0.2.zip", (req, res) {
		res.writeBody("", HTTPStatus.badGateway);
	});
	router.get("*", folder.serveStaticFiles);
	router.get("/fallback/*", folder.serveStaticFiles(new HTTPFileServerSettings("/fallback")));
	router.get("/api/*", apiFileHandler("/", folder));
	router.get("/fallback/api/*", apiFileHandler("/fallback/", folder));
	listenHTTP(text(":", port), router);
	runApplication();
}
