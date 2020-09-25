module app;

import common;
import magicrb;
import listener;
import during;

import core.stdc.stdio;
import core.stdc.stdlib;
import core.sys.linux.errno;
import core.sys.posix.signal;

import std.conv : emplace;

nothrow @nogc:

alias PClient = ClientContext*;

PClient pool;

int main()
{
    Uring io;
    auto ret = io.setup(512); // max 1024 entries in submission queue
    if (ret < 0)
    {
        fprintf(stderr, "Failed to initialize io_uring: %d\n", ret);
        return 1;
    }

    ret = registerSignalHandler();
    if (ret > 0) return ret;

    immutable serverFd = io.startTCPListener(8080, &onAccept);
    if (serverFd < 0)
    {
        fprintf(stderr, "startTCPListener(): %d\n", serverFd);
        return -serverFd;
    }

    scope (exit)
    {
        // TODO: cleanup
    }

    // run event loop
    while (true)
    {
        ret = io.submit(1); // submit queue and wait at least for one completion
        if (ret < 0)
        {
            perror("io.submit()");
            return ret;
        }

        if (io.empty)
        {
            fprintf(stderr, "empty queue after wait: signal?\n");
            return 0;
        }

        auto ctx = cast(IOContext*)io.front.user_data;
        debug fprintf(stderr, "op completed: ctx=%p, fd=%d, res=%d\n", ctx, ctx.fd, io.front.res);
        assert(ctx.onCompletion !is null, "ctx.onCompletion is null");
        ret = ctx.onCompletion(io, *ctx, io.front.res);
        if (ret < 0)
        {
            fprintf(stderr, "Operation %p completed with error %d", ctx, ret);
            return ret;
        }
        io.popFront();
    }
}

int onAccept(ref Uring io, int listenFd, int clientFd, const(char)* addr, ushort port) nothrow
{
    debug fprintf(stderr, "client fd=%d from %s:%d\n", clientFd, addr, port);
    PClient clientCtx;
    if (pool)
    {
        clientCtx = pool;
        pool = pool.next;
        clientCtx.fd = clientFd;
        clientCtx.readOp.fd = clientFd;
        clientCtx.writeOp.fd = clientFd;
        clientCtx.closeOp.fd = clientFd;
    }
    else
    {
        clientCtx = cast(PClient)malloc(ClientContext.sizeof);
        clientCtx.emplace(clientFd);
    }

    return (*clientCtx).readNext(io);
}

struct ClientContext
{
    int fd;
    IOContext readOp, writeOp, closeOp;
    ClientContext* next;
    RingBuffer!ubyte readBuffer;
    RingBuffer!ubyte writeBuffer;
    bool disconnect;

    nothrow @nogc:

    this(int fd)
    {
        debug fprintf(stderr, "createdClient: fd=%d, rd=%p, wr=%p, cl=%p\n", fd, &readOp, &writeOp, &closeOp);
        this.fd = fd;
        readOp.fd = writeOp.fd = closeOp.fd = fd;
        readOp.data = writeOp.data = closeOp.data = cast(void*)&this;
        closeOp.onCompletion = &onCloseCompleted;
    }

    int readNext(ref Uring io)
    {
        assert(!readOp.onCompletion, "Already reading");
        immutable res = readBuffer.reserve(1400);
        if (_expect(res < 1400, false)) return -ENOMEM;

        readOp.onCompletion = &onReadCompleted;
        readOp.buffer = readBuffer[$-res .. $];
        io.putWith!((ref SubmissionEntry e, ref IOContext ctx)
        {
            e.prepRecv(ctx.fd, ctx.buffer, MsgFlags.NONE);
            e.setUserData(ctx);
        })(readOp);
        return 0;
    }

    int writeNext(ref Uring io)
    {
        assert(!writeOp.onCompletion, "Already writing");

        writeOp.onCompletion = &onWriteCompleted;
        writeOp.buffer = writeBuffer[];
        io.putWith!((ref SubmissionEntry e, ref IOContext ctx)
        {
            e.prepSend(ctx.fd, ctx.buffer, MsgFlags.NONE);
            e.setUserData(ctx);
        })(writeOp);
        return 0;
    }

    void terminate(ref Uring io)
    {
        disconnect = true;

        if (readOp.onCompletion || writeOp.onCompletion) return; // operation still active

        debug fprintf(stderr, "Client %d terminating\n", fd);
        io.putWith!((ref SubmissionEntry e, ref IOContext ctx)
        {
            e.prepClose(ctx.fd);
            e.setUserData(ctx);
        })(closeOp);
    }

    int handleRequest(ref Uring io)
    {
        static immutable ubyte[4] separator = [13, 10, 13, 10];

        // if (_expect(writeOp.onCompletion !is null, false)) return 0; // wait for prev response to be written first
        assert(writeOp.onCompletion is null, "Write operation still active");

        // TODO: parse request properly
        size_t idx;
        import std.algorithm;
        if (readBuffer[].endsWith(separator[])) idx = readBuffer.length - separator.length;
        else idx = readBuffer[].countUntil(separator[]);

        if (idx > 0)
        {
            debug fprintf(stderr, "On request");
            readBuffer.popFront(idx + separator.length);

            writeBuffer ~= cast(ubyte[])(
                "HTTP/1.1 200 OK\r\n"
                ~ "Server: during/raw_012345678901234567890123456789012345678\r\n"
                ~ "Connection: keep-alive\r\n"
                ~ "Content-Type: text/plain\r\n"
                ~ "Content-Length: 13\r\n"
                ~ "\r\n"
                ~ "Hello, World!");

            immutable ret = writeNext(io);
            if (_expect(ret != 0, false)) return ret;
        }

        return readNext(io);
    }
}

int onReadCompleted(ref Uring io, ref IOContext ctx, int res)
{
    auto cli = cast(PClient)ctx.data;

    with (cli)
    {
        readOp.onCompletion = null;
        if (res <= 0)
        {
            debug fprintf(stderr, "Client %d err: %d\n", ctx.fd, res);
            terminate(io);
            return 0;
        }

        if (_expect(disconnect, false)) terminate(io);
        readBuffer.popBack(ctx.buffer.length - res);
        return handleRequest(io);
    }
}

int onWriteCompleted(ref Uring io, ref IOContext ctx, int res)
{
    auto cli = cast(PClient)ctx.data;

    with (cli)
    {
        writeOp.onCompletion = null;
        if (res <= 0)
        {
            debug fprintf(stderr, "Client %d err: %d\n", ctx.fd, res);
            terminate(io);
            return 0;
        }

        if (_expect(disconnect, false)) terminate(io);
        writeBuffer.popFront(res);
        if (_expect(writeBuffer.length > 0, false)) return writeNext(io);
        return 0;
    }
}

int onCloseCompleted(ref Uring io, ref IOContext ctx, int res)
{
    auto cli = cast(PClient)ctx.data;

    with (cli)
    {
        debug fprintf(stderr, "Client %d terminated: res=%d\n", fd, res);

        readBuffer.clear();
        writeBuffer.clear();
        disconnect = false;
        next = pool;
        pool = cli;
    }

    return res;
}

int registerSignalHandler()
{
    if (
        signal(SIGPIPE, SIG_IGN) == SIG_ERR // disable SIGPIPE
        || signal(SIGINT, &onSignal) == SIG_ERR || signal(SIGTERM, &onSignal) == SIG_ERR
    )
    {
        perror("signal()");
        return errno;
    }

    return 0;
}

private:

extern(C) void onSignal(int sig)
{
    fprintf(stderr, "onSignal: %s\n", strsignal(sig));
}

extern(C) char* strsignal(int sig);
