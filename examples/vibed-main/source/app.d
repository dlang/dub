import vibe.vibe;

void main()
{
	listenHTTP(new HTTPServerSettings, &handleRequest);
	lowerPrivileges();
	runEventLoop();
}

void handleRequest(HTTPServerRequest req, HTTPServerResponse res)
{
	res.writeBody("Hello, World!");
}
