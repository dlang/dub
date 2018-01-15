/+dub.sdl:
dependency "vibe-d" version="~>0.8.2"
versions "VibeNoSSL"
+/

void main(string[] args)
{
	import std.conv, vibe.d;
	string folder;
	uint port = 12345;
	readOption("folder", &folder, "Folder to service files from.");
	readOption("port", &port, "Port to use");
	auto router = new URLRouter;
	router.get("stop", (HTTPServerRequest req, HTTPServerResponse res){
		res.writeVoidBody;
		exitEventLoop();
	});
	router.get("*", folder.serveStaticFiles);
	listenHTTP(text(":", port), router);
	runApplication();
}
