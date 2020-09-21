#!/bin/env dub
/+ dub.sdl:
    name "app"
    dependency "arsd-official:cgi" version=">=8.4.4"
    // the threads version works better on benchmarks due to various tradeoffs
    subConfiguration "arsd-official:cgi" "embedded_httpd_threads"
+/

// import std;
import arsd.cgi;

void hello(Cgi cgi) {
    cgi.setResponseContentType("text/plain");
    cgi.write("Hello, World!");
}

mixin GenericMain!hello;
