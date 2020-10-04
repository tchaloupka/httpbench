#!/bin/env dub
/+ dub.sdl:
    name "app"
    dependency "mecca" version=">=0.0.0"
+/

import std.algorithm;
import std.array : array;
import std.exception: ErrnoException;
import std.range : repeat;

import mecca.lib.time;
import mecca.log;
import mecca.reactor;
import mecca.reactor.io.fd;

enum PORT = 8080;
enum CLIENT_TIMEOUT = 20.seconds;
enum MAX_RESPONSES = 512;

static immutable ubyte[] response = cast(immutable ubyte[])(
        "HTTP/1.1 200 OK\r\n"
        ~ "Server: mecca/raw_0123456789012345678901234567890123456789\r\n"
        ~ "Connection: keep-alive\r\n"
        ~ "X-Test: 01234567890123456789\r\n"
        ~ "Content-Type: text/plain\r\n"
        ~ "Content-Length: 13\r\n"
        ~ "\r\n"
        ~ "Hello, World!");

immutable ubyte[] responseBuff;

shared static this()
{
    responseBuff = response.repeat(MAX_RESPONSES).joiner.array;
}

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
    try {
        ubyte[4096] buffer = void;

        while (true)
        {
            auto len = sock.read(buffer, Timeout(CLIENT_TIMEOUT));
            if (len <= 0) return;

            int nextReq;
            immutable nReq = countRequests(buffer[0..len], nextReq);

            if (_expect(nReq == 0 || nextReq != len, false))
                assert(0, "FIXME: partial request handling not implemented");

            if (_expect(nReq > MAX_RESPONSES, false))
                assert(0, "FIXME: response buffer too small");

            immutable sendBytes = nReq * response.length;
            immutable sentBytes = sock.write(responseBuff[0..sendBytes]);
            if (_expect(sendBytes <= 0, false)) return;
            if (_expect(sentBytes < sendBytes, false)) assert(0, "FIXME: incomplete send");
        }
    } catch(TimeoutExpired ex) {
        sock.write("K'bye now\n");
    } catch(ErrnoException ex) {
        WARN!"errno: %s"(ex.msg);
    }
}

int countRequests(ubyte[] buf, out int nextReq)
{
    static immutable ubyte[4] sep = [13, 10, 13, 10];

    if (_expect(buf.length < 4, false)) return 0;

    int res = 0;
    for (int idx = 0; idx <= buf.length - 4; ++idx)
    {
        if (_expect(buf[idx] == '\r', false))
        {
            if (buf[idx .. idx + 4] != sep)
            {
                idx += 4;
                continue;
            }

            nextReq = idx+4;
            ++res;
        }
    }

    return res;
}

version(LDC) public import ldc.intrinsics: _expect = llvm_expect;
else
{
    T _expect(T)(T val, T expected_val) if (__traits(isIntegral, T))
    {
        pragma(inline, true);
        return val;
    }
}
