#!/bin/env dub
/+ dub.sdl:
    name "app"
    dependency "lighttp" version=">=0.5.4"
+/

import lighttp;

void main(string[] args) {

    Server server = new Server();
    server.host("0.0.0.0", 8080);
    server.router.add(new Router());
    server.run();
}

final class Router
{
    // GET /
    @Get("") get(ServerResponse response) {
        response.headers["Content-Type"] = "text/plain; charset=utf-8";
        response.headers["X-Test"] = "0123456789012345678901234567890123456789012345678901234567890123456789";
        response.body = "Hello, World!";
    }
}
