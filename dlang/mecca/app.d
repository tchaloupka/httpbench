#!/bin/env dub
/+ dub.sdl:
    name "app"
    dependency "mecca" version=">=0.0.0"
+/

import std.algorithm : move;
import std.exception: ErrnoException;

import mecca.lib.time;
import mecca.log;
import mecca.reactor;
import mecca.reactor.io.fd;

enum PORT = 8080;
enum CLIENT_TIMEOUT = 20.seconds;

int main() {
    theReactor.setup();
    scope(exit) theReactor.teardown(); // Not really needed outside of UTs

    theReactor.spawnFiber!listeningFiber();
    return theReactor.start();
}

void listeningFiber() {
    auto listeningSock = ConnectedSocket.listen( SockAddrIPv4.any(PORT), true /* reuse address */ );

    while(true) {
        SockAddr clientAddress;
        auto clientSock = listeningSock.accept(clientAddress);
        theReactor.spawnFiber!clientFiber( move(clientSock) );
    }
}

void clientFiber( ConnectedSocket sock ) {

    static immutable ubyte[4] reqTerm = [13, 10, 13, 10];
    static immutable ubyte[] response = cast(immutable ubyte[])(
                "HTTP/1.1 200 OK\r\n"
                ~ "Server: mecca/raw_0123456789012345678901234567890123456789\r\n"
                ~ "Connection: keep-alive\r\n"
                ~ "X-Test: 01234567890123456789\r\n"
                ~ "Content-Type: text/plain\r\n"
                ~ "Content-Length: 13\r\n"
                ~ "\r\n"
                ~ "Hello, World!");

    try {
        char[1024] buffer = void;
        int pos;

        while (true) {
            auto len = sock.read(buffer, Timeout(CLIENT_TIMEOUT));
            if (len <= 0) return;

            pos += len;
            if (pos > 4 && buffer[pos-4..pos] == reqTerm) {
                if (sock.write(response) <= 0) return;
                pos = 0;
            }
        }
    } catch(TimeoutExpired ex) {
        sock.write("K'bye now\n");
    } catch(ErrnoException ex) {
        WARN!"errno: %s"(ex.msg);
    }
}
