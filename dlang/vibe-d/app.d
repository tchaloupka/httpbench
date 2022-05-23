#!/bin/env dub
/+ dub.sdl:
    name "app"
    dependency "vibe-d" version=">=0.9.4"
    dependency "vibe-d:tls" version=">=0.9.4"

    subConfiguration "vibe-d:tls" "notls"
    versions "VibeHighEventPriority" "VibeDisableCommandLineParsing"
+/
import std.conv : to;
import std.process;
import vibe.core.core;
import vibe.core.log;
import vibe.http.server;

void main()
{
    setLogLevel(LogLevel.none);

    auto workers = environment.get("WORKERS");
    if (workers !is null)
    {
        immutable numThreads = workers.to!int;
        if (numThreads > 1)
        {
            setupWorkerThreads(numThreads);
            runWorkerTaskDist(&runServer);
        }
        else runServer();
    }
    else runWorkerTaskDist(&runServer);
    runApplication();
}

void runServer()
{
    auto settings = new HTTPServerSettings;
    settings.options |= HTTPServerOption.reusePort;
    settings.bindAddresses = ["0.0.0.0"];
    settings.port = 8080;
    // settings.serverString ~= "____";
    listenHTTP(settings, &handleRequest);
}

void handleRequest(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
    res.headers["X-Test"] = "01234567890123456789";
    res.writeBody("Hello, World!", "text/plain");
}
