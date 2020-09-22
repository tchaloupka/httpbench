module listener;

import common;
import during;

import core.stdc.stdio;
import core.stdc.stdlib;
import core.sys.linux.errno;
import core.sys.linux.netinet.tcp;
import core.sys.posix.netinet.in_;
import core.sys.posix.unistd;
import core.sys.posix.sys.socket;

nothrow @nogc:

alias OnClientCB = int function(ref Uring io, int listenFd, int clientFd, const(char)* addr, ushort port);

struct AcceptCtx
{
    IOContext ioCtx;
    sockaddr_in addr;
    socklen_t addrLen = sockaddr_in.sizeof;
}

AcceptCtx acceptCtx;

/// Returns listener socket
int startTCPListener(ref Uring io, ushort port, OnClientCB onClient)
{
    enum SOCK_NONBLOCK = 0x800;
    assert(onClient !is null, "Callback not set");

    int listenFd;
    sockaddr_in serverAddr;

    serverAddr.sin_family = AF_INET;
    serverAddr.sin_addr.s_addr = htonl(INADDR_ANY);
    serverAddr.sin_port = htons(port);

    if ((listenFd = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK, IPPROTO_TCP)) == -1)
    {
        perror("socket()");
        return -errno;
    }

    int flags = 1;
    if (setsockopt(listenFd, SOL_SOCKET, SO_REUSEADDR, cast(void*)&flags, int.sizeof) == -1
        || setsockopt(listenFd, SOL_SOCKET, SO_REUSEPORT, cast(void*)&flags, int.sizeof) == -1
        || setsockopt(listenFd, IPPROTO_TCP, TCP_NODELAY, cast(void*)&flags, int.sizeof) == -1)
    {
        perror("setsockopt()");
        return -errno;
    }

    if (bind(listenFd, cast(sockaddr*)&serverAddr, sockaddr.sizeof) == -1)
    {
        perror("bind()");
        return -errno;
    }

    if (listen(listenFd, 32) == -1)
    {
        perror("listen()");
        return -errno;
    }

    // start listening
    acceptCtx.ioCtx.onCompletion = &onAcceptCompleted;
    acceptCtx.ioCtx.fd = listenFd;
    acceptCtx.ioCtx.data = cast(void*)onClient;

    int ret = acceptNext(io, acceptCtx);
    if (ret < 0) return ret;

    return listenFd;
}

private:

// resubmit poll on listening socket
int acceptNext(ref Uring io, ref AcceptCtx ctx) @nogc
{
    // poll for new clients
    io.putWith!((ref SubmissionEntry e, ref AcceptCtx ctx)
        {
            e.prepAccept(ctx.ioCtx.fd, ctx.addr, ctx.addrLen);
            e.setUserData(ctx);
        })(ctx);

    return 0;
}

// we can accept new client now
int onAcceptCompleted(ref Uring io, ref IOContext ctx, int res)
{
    if (res < 0) return res;

    assert(ctx.data !is null, "Context not set");
    auto ac = cast(AcceptCtx*)(&ctx);
    assert(ac.ioCtx.data !is null, "Callback not set");
    auto cb = cast(OnClientCB)ac.ioCtx.data;

    in_addr i_addr;
    i_addr.s_addr = ac.addr.sin_addr.s_addr;

    immutable ret = cb(io, ctx.fd, res, inet_ntoa(i_addr), ntohs(ac.addr.sin_port));
    if (ret < 0) return ret;

    return io.acceptNext(*ac); // wait for next client to be acceptable
}
