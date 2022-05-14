#!/bin/env dub
/+ dub.sdl:
    name "app"
    dependency "archttp" version=">=0.0.1"
+/

import archttp;

import std.conv : to;

void main(string[] args)
{
    Archttp app;

    if (args.length > 1)
        app = new Archttp(args[1].to!uint);
    else
        app = new Archttp;

    app.Bind(8080);

    app.Get("/", (ctx) {
        ctx.response.header("Content-Type", "text/plain");
        ctx.response.header("X-Test", "11111111111111111111111111111111");
        ctx.response.body("Hello, World!");
    });

    app.Run();
}
