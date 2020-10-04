#!/bin/env dub
/+ dub.sdl:
    name "app"
    dependency "during" version=">=0.3.0-rc"
+/

import core.stdc.stdio;
import core.stdc.stdlib;
import core.sys.linux.errno;
import core.sys.linux.netinet.tcp;
import core.sys.posix.netinet.in_;
import core.sys.posix.unistd;
import core.sys.posix.sys.socket;

import during;

nothrow @nogc:

enum MAX_SQE             = 512;
enum BACKLOG             = 512;
enum MAX_MESSAGE_LEN     = 1024;
enum BUFFERS_COUNT       = 4096;
enum MAX_RESPONSES = 512;

enum OP : ushort { ACCEPT, READ, WRITE, PROV_BUF }

struct OperationCtx
{
    uint fd;
    OP type;
    ushort bid;
}

alias MsgBuf = ubyte[MAX_MESSAGE_LEN];
alias Buffers = MsgBuf[BUFFERS_COUNT];
Buffers bufs;
enum group_id = 1337;

extern(C) int main()
{
    static immutable ubyte[] response = cast(immutable ubyte[])(
                "HTTP/1.1 200 OK\r\n"
                ~ "Server: epoll/raw_0123456789012345678901234567890123456789\r\n"
                ~ "Connection: keep-alive\r\n"
                ~ "X-Test: 01234567890123456789\r\n"
                ~ "Content-Type: text/plain\r\n"
                ~ "Content-Length: 13\r\n"
                ~ "\r\n"
                ~ "Hello, World!");

    ubyte[] responseBuff = (cast(ubyte*)malloc(MAX_RESPONSES * response.length))[0..MAX_RESPONSES * response.length];
    foreach (i; 0..MAX_RESPONSES)
        responseBuff[i*response.length .. (i+1)*response.length] = response[];

    // setup socket
    immutable listenFd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (listenFd < 0) error!"Error creating socket..";

    int flags = 1;
    if (setsockopt(listenFd, SOL_SOCKET, SO_REUSEADDR, cast(void*)&flags, int.sizeof) == -1
        || setsockopt(listenFd, SOL_SOCKET, SO_REUSEPORT, cast(void*)&flags, int.sizeof) == -1
        || setsockopt(listenFd, IPPROTO_TCP, TCP_NODELAY, cast(void*)&flags, int.sizeof) == -1
    ) error!"setsockopt()";

    // setup bind address
    sockaddr_in serverAddr;
    serverAddr.sin_family = AF_INET;
    serverAddr.sin_port = htons(8080);
    serverAddr.sin_addr.s_addr = INADDR_ANY;

    // bind socket and listen for connections
    if (bind(listenFd, cast(sockaddr*)&serverAddr, serverAddr.sizeof) < 0)
        error!"bind()";

    if (listen(listenFd, BACKLOG) < 0) {
        error!"listen()";
    }

    // initialize io_uring
    Uring io;
    immutable ret = io.setup(512); // max 1024 entries in submission queue
    if (ret < 0)
    {
        fprintf(stderr, "Failed to initialize io_uring: %d\n", ret);
        return 1;
    }

    // check if IORING_FEAT_FAST_POLL is supported
    if (!(io.params.features & SetupFeatures.FAST_POLL)) {
        printf("IORING_FEAT_FAST_POLL not available in the kernel, quiting...\n");
        exit(0);
    }

    // register buffers for buffer selection
    io.next.prepProvideBuffers(bufs, group_id, 0);
    io.submit(1);
    if (io.front.res < 0)
    {
        fprintf(stderr, "provideBuffers(): res=%d\n", io.front.res);
        exit(1);
    }
    io.popFront();

    // add accept op
    sockaddr_in addr;
    socklen_t addrlen = sockaddr_in.sizeof;
    io.next
        .prepAccept(listenFd, addr, addrlen)
        .setUserDataRaw(OperationCtx(listenFd, OP.ACCEPT));

    // start event loop
    while (true)
    {
        io.submit(1);

        foreach (ref CompletionEntry cqe; io) // go through all CQEs
        {
            OperationCtx ctx = cqe.userDataAs!OperationCtx();

            if (_expect(cqe.res == -ENOBUFS, false))
                assert(0, "bufs in automatic buffer selection empty, this should not happen...");

            final switch (ctx.type)
            {
                case OP.PROV_BUF:
                    if (_expect(cqe.res < 0, false))
                    {
                        fprintf(stderr, "provideBuffers(): res=%d\n", cqe.res);
                        exit(1);
                    }
                    // debug printf("Provide buffers completed: res=%d\n", cqe.res);
                    break;
                case OP.ACCEPT:
                    immutable fd = cqe.res;
                    if (fd >= 0) // only read when there is no error, >= 0
                    {
                        debug printf("New client connected: fd=%d\n", fd);
                        io.next
                            .prepRecv(fd, group_id, MAX_MESSAGE_LEN)
                            .setUserDataRaw(OperationCtx(fd, OP.READ));
                    }

                    // accept next client
                    io.next
                        .prepAccept(listenFd, addr, addrlen)
                        .setUserDataRaw(OperationCtx(listenFd, OP.ACCEPT));
                    break;
                case OP.READ:
                    if (_expect(cqe.res <= 0, false))
                    {
                        debug printf("Client disconnect: fd=%d, res=%d, flags=%d\n", ctx.fd, cqe.res, cqe.flags);
                        close(ctx.fd);
                        if (cqe.flags & CQEFlags.BUFFER)
                        {
                            // return buffer too
                            immutable bid = cast(ushort)(cqe.flags >> 16);
                            io.next
                                .prepProvideBuffer(bufs[bid], group_id, bid)
                                .setUserDataRaw(OperationCtx(0, OP.PROV_BUF));
                        }
                        break;
                    }

                    // bytes have been read into bufs, now add write to socket sqe
                    immutable bytes = cqe.res;
                    immutable bid = cast(ushort)(cqe.flags >> 16); // get used buffer id

                    // parse request
                    int nextReq;
                    immutable nReq = countRequests(bufs[bid][0..bytes], nextReq);

                    if (_expect(nReq == 0 || nextReq != bytes, false))
                        assert(0, "FIXME: partial request handling not implemented");

                    if (_expect(nReq > MAX_RESPONSES, false))
                        assert(0, "FIXME: response buffer too small");

                    // re-add the buffer if consumed
                    // debug printf("Provide back unused buffer: fd=%d, bid=%d, flafs=%04x\n", ctx.fd, bid, cqe.flags);
                    io.next
                        .prepProvideBuffer(bufs[bid], group_id, bid)
                        .setUserDataRaw(OperationCtx(0, OP.PROV_BUF));

                    io.next
                        .prepSend(ctx.fd, responseBuff[0..nReq*response.length])
                        .setUserDataRaw(OperationCtx(ctx.fd, OP.WRITE));

                    io.next
                        .prepRecv(ctx.fd, group_id, MAX_MESSAGE_LEN)
                        .setUserDataRaw(OperationCtx(ctx.fd, OP.READ));
                    break;
                case OP.WRITE:
                    if (_expect(cqe.res <= 0, false))
                    {
                        debug printf("Client error: fd=%d, res=%d\n", ctx.fd, cqe.res);
                        close(ctx.fd);
                        break;
                    }
                    break;
            }
        }
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

void error(string msg)() { perror(msg); exit(1); }

version(LDC) public import ldc.intrinsics: _expect = llvm_expect;
else
{
    T _expect(T)(T val, T expected_val) if (__traits(isIntegral, T))
    {
        pragma(inline, true);
        return val;
    }
}
