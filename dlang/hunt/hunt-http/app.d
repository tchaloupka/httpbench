#!/bin/env dub
/+ dub.sdl:
    name "app"
    dependency "hunt-http" version=">=0.6.9"
    // versions "HUNT_IO_DEBUG"
+/

import hunt.http;
import std.conv : to;

void main(string[] args)
{
    auto builder = HttpServer.builder()
        .setListener(8080, "0.0.0.0");

    if (args.length > 1) builder.ioThreadSize(args[1].to!int);
    builder.addRoute("/", ((RoutingContext context) {
        context.responseHeader(HttpHeader.CONTENT_TYPE, MimeType.TEXT_PLAIN_VALUE);
        context.responseHeader("X-Test", "0123456789012345678901234567890123456789012");
        context.end("Hello, World!");
    }));

    auto server = builder.build();
    server.start();
}
