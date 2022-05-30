#!/bin/env dub
/+ dub.sdl:
    name "app"
    dependency "archttp" version=">=1.1.0"
    dependency "mir-cpuid" version=">=1.2.7"
+/

import archttp;

import std.conv : to;

import cpuid.unified;

void main(string[] args)
{
    Archttp app  = new Archttp((args.length > 1) ? args[1].to!uint : threads);

    app.get("/", (HttpRequest req, HttpResponse res) {
        res.header("Content-Type", "text/plain");
        res.header("X-Test", "11111111111111111111111111111111111111111111");
        res.send("Hello, World!");
    });

    app.listen(8080);
}
