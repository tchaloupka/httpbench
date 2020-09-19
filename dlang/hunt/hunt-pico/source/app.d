import std.conv;
import std.stdio;

import hunt.io;
import hunt.system.Memory : totalCPUs;
import http.Processor;
import http.Server;
import http.DemoProcessor;
import std.experimental.allocator;

void main(string[] args) {
    int cpus = totalCPUs;
    if (args.length > 1) cpus = args[1].to!int;

    AbstractTcpServer httpServer = new HttpServer!(DemoProcessor)("0.0.0.0", 8080, cpus);
    writefln("listening on http://%s", httpServer.bindingAddress.toString());
    httpServer.start();
}
