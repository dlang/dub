import vibe.d;

shared static this()
{
	listenHTTP(new HTTPServerSettings, &handleRequest);
}

void handleRequest(HTTPServerRequest req, HTTPServerResponse res)
{
	res.writeBody("Hello, World!");
}
