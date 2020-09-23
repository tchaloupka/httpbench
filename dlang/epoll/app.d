#!/bin/env dub
/+ dub.sdl:
    name "app"
+/

import core.stdc.stdio;
import core.stdc.stdlib;
import core.sys.linux.epoll;
import core.sys.linux.errno;
import core.sys.linux.netinet.tcp;
import core.sys.posix.netinet.in_;
import core.sys.posix.unistd;
import core.sys.posix.sys.socket;

nothrow @nogc:

enum BACKLOG = 512;
enum MAX_EVENTS = 256;
enum MAX_CLIENTS = 512;
enum MAX_MESSAGE_LEN = 1024;
enum SOCK_NONBLOCK = 0x800;

extern(C) void main()
{
    static immutable ubyte[4] reqTerm = [13, 10, 13, 10];
    static immutable ubyte[] response = cast(immutable ubyte[])(
                "HTTP/1.1 200 OK\r\n"
                ~ "Server: epoll/raw_0123456789012345678901234567890123456789\r\n"
                ~ "Connection: keep-alive\r\n"
                ~ "Content-Type: text/plain\r\n"
                ~ "Content-Length: 13\r\n"
                ~ "\r\n"
                ~ "Hello, World!");

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

    // init epoll
    epoll_event ev;
    epoll_event[MAX_EVENTS] events;
    int epollfd;

    epollfd = epoll_create(MAX_EVENTS);
    if (epollfd < 0) error!"epoll_create()";

    // register listenFd
    ev.events = EPOLLIN;
    ev.data.fd = listenFd;
    if (epoll_ctl(epollfd, EPOLL_CTL_ADD, listenFd, &ev) == -1)
        error!"Error adding new listeding socket to epoll..";

    // setup clients
    Client[MAX_CLIENTS] clients;

    // start loop
    while (true)
    {
        immutable newEvents = epoll_wait(epollfd, &events[0], MAX_EVENTS, -1);
        if (_expect(newEvents == -1, false)) error!"epoll_wait()";

        for (int i = 0; i < newEvents; ++i)
        {
            if (events[i].data.fd == listenFd)
            {
                // accept new client
                sockaddr_in addr;
                socklen_t addrLen = sockaddr_in.sizeof;
                immutable cfd = accept4(listenFd, cast(sockaddr*)&addr, &addrLen, SOCK_NONBLOCK);
                if (_expect(cfd == -1, false)) error!"Error accepting new connection..";
                clients[cfd].len = 0;

                ev.events = EPOLLIN | EPOLLRDHUP | EPOLLET;
                ev.data.fd = cfd;
                if (_expect(epoll_ctl(epollfd, EPOLL_CTL_ADD, cfd, &ev) == -1, false))
                    error!"Error adding new event to epoll..";
                debug printf("Accepted new client: fd=%d\n", cfd);
                continue;
            }

            immutable fd = events[i].data.fd;
            if (events[i].events & EPOLLRDHUP)
            {
                closeClient(epollfd, fd, EPOLLRDHUP);
                continue;
            }

            read:
            immutable bytes = recv(fd, &clients[fd].buffer[clients[fd].len], MAX_MESSAGE_LEN - clients[fd].len, 0);
            if (bytes <= 0)
            {
                if (errno == EWOULDBLOCK) goto parse;
                closeClient(epollfd, fd, errno);
                continue;
            }
            clients[fd].len += bytes;
            goto read;

            parse:
            // parse request
            import std.algorithm : endsWith;
            if (clients[fd].buffer[0..clients[fd].len].endsWith(reqTerm[]))
            {
                send(fd, &response[0], response.length, 0);
                clients[fd].len = 0;
            }
        }
    }
}

void closeClient(int epollfd, int fd, int err)
{
    debug printf("Closing client: fd=%d, err=%d\n", fd, err);
    epoll_ctl(epollfd, EPOLL_CTL_DEL, fd, null);
    // shutdown(fd, SHUT_RDWR);
    close(fd);
}

struct Client
{
    ubyte[MAX_MESSAGE_LEN] buffer;
    int len;
}

void error(string msg)() { perror(msg); exit(1); }

extern (C) int accept4(int, sockaddr*, socklen_t*, int);

version(LDC) public import ldc.intrinsics: _expect = llvm_expect;
else
{
    T _expect(T)(T val, T expected_val) if (__traits(isIntegral, T))
    {
        pragma(inline, true);
        return val;
    }
}
