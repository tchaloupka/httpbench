#!/bin/env dub
/+ dub.sdl:
    name "app"
    dependency "serverino" version=">=0.2.2"
+/

import serverino;
mixin ServerinoMain;

void hello(const Request req, Output output)
{
    output.addHeader("X-Test", "0000000000111111111122222222223"); // padding to 192B response size
    output ~= "Hello, World!";
}

@onServerInit
auto setup()
{
    import std.conv : to;
    import std.parallelism : totalCPUs;
    import std.process : environment;

    ServerinoConfig sc = ServerinoConfig.create();
    auto workers = environment.get("WORKERS");
    if (workers !is null) sc.setWorkers(workers.to!int);
    else sc.setWorkers(totalCPUs);
    sc.enableKeepAlive();
    return sc;
}
