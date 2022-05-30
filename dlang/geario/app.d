#!/bin/env dub
/+ dub.sdl:
    name "app"
    dependency "geario" version=">=0.1.0"
    dependency "mir-cpuid" version=">=1.2.7"
+/

import geario.event;
import geario.logging;

import geario.net.TcpListener;
import geario.net.TcpStream;

import cpuid.unified;

import std.conv : to;

void main(string[] args)
{
    static immutable ubyte[] response = cast(immutable ubyte[])(
                "HTTP/1.1 200 OK\r\n"
                ~ "Server: Geario\r\n"
                ~ "Connection: keep-alive\r\n"
                ~ "X-Test: 01231231231231231234\r\n"
                ~ "Content-Type: text/plain\r\n"
                ~ "Content-Length: 13\r\n"
                ~ "\r\n"
                ~ "Hello, World!");

    EventLoop loop = new EventLoop();

    TcpListener listener = new TcpListener(loop);
    listener.Threads((args.length > 1) ? args[1].to!uint : threads);
    listener.Bind(8080)
        .Accepted((TcpListener listener, TcpStream connection)
        {
            connection.Received((buf)
                {
                    // writeln(buf.date());
                    connection.Write(response);
                });
        }).Error((IoError error) {
            // on error ..
        }).Start();

    loop.Run();
}
