#!/bin/env dub
/+ dub.sdl:
    name "app"
    dependency "arsd-official:cgi" version=">=8.4.3"
+/

// import std;
import arsd.cgi;

void hello(Cgi cgi) {
    cgi.setResponseContentType("text/plain");
    cgi.write("Hello, World!");
}

mixin GenericMain!hello;
