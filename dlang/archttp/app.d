#!/bin/env dub
/+ dub.sdl:
    name "app"
    dependency "archttp" version=">=1.0.0"
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

    app.bind(8080);

    app.get("/", (HttpRequest req, HttpResponse res) {
        res.header("Content-Type", "text/plain");
        res.header("X-Test", "11111111111111111111111111111111111111111111");
        res.send("Hello, World!");
    });

    app.run();
}
