// originating version hash: d8563d057179bd93dc4f6b3f6d098fea72d28cef
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/signal.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/epoll.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>

#define BACKLOG 512
#define MAX_EVENTS 128
#define MAX_MESSAGE_LEN 4096
#define MAX_CLIENTS 2048
#define MAX_RESPONSES 512

void error(char* msg);
void closeClient(int epollfd, int clientfd);
int countRequests(char *buf, int len, int *nextReq);

struct Client {
    char *buffer;
    int len;
};

const char response[] =
    "HTTP/1.1 200 OK\r\n"
    "Server: epoll/raw_0123456789012345678901234567890123456789\r\n"
    "X-Test: 01234567890123456789\r\n"
    "Connection: keep-alive\r\n"
    "Content-Type: text/plain\r\n"
    "Content-Length: 13\r\n"
    "\r\n"
    "Hello, World!";

const char sep[] = "\r\n\r\n";

char *responseBuff;

int main(int argc, char *argv[])
{
    if (argc < 2) {
        printf("Please give a port number: ./epoll_echo_server [port]\n");
        exit(0);
    }

    // some variables we need
    int portno = strtol(argv[1], NULL, 10);
    struct sockaddr_in server_addr, client_addr;
    socklen_t client_len = sizeof(client_addr);

    struct Client clients[MAX_CLIENTS];

    // disable SIGPIPE
    if (signal(SIGPIPE, SIG_IGN) == SIG_ERR) {
        perror("signal()");
        return 1;
    }

    // setup socket
    int sock_listen_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (sock_listen_fd < 0) {
        error("Error creating socket..\n");
    }
    const int val = 1;
    if (setsockopt(sock_listen_fd, SOL_SOCKET, SO_REUSEADDR, &val, sizeof(val)) == -1
        || setsockopt(sock_listen_fd, SOL_SOCKET, SO_REUSEPORT, &val, sizeof(val)) == -1
        || setsockopt(sock_listen_fd, IPPROTO_TCP, TCP_NODELAY, &val, sizeof(val)) == -1) {
        perror("setsockopt()");
        exit(1);
    }

    memset((char *)&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(portno);
    server_addr.sin_addr.s_addr = INADDR_ANY;

    // bind socket and listen for connections
    if (bind(sock_listen_fd, (struct sockaddr *)&server_addr, sizeof(server_addr)) < 0)
        error("Error binding socket..\n");

    if (listen(sock_listen_fd, BACKLOG) < 0) {
        error("Error listening..\n");
    }
    printf("http server listening for connections on port: %d\n", portno);

    struct epoll_event ev, events[MAX_EVENTS];
    int new_events, sock_conn_fd, epollfd;

    epollfd = epoll_create(MAX_EVENTS);
    if (epollfd < 0) {
        error("Error creating epoll..\n");
    }
    ev.events = EPOLLIN;
    ev.data.fd = sock_listen_fd;

    if (epoll_ctl(epollfd, EPOLL_CTL_ADD, sock_listen_fd, &ev) == -1) {
        error("Error adding new listeding socket to epoll..\n");
    }

    // prep sendbuffer
    responseBuff = malloc(MAX_RESPONSES * (sizeof(response) - 1));
    for (int i = 0; i < MAX_RESPONSES; ++i) {
        memcpy(responseBuff + i*(sizeof(response) - 1), response, (sizeof(response) - 1));
    }

    while(1)
    {
        new_events = epoll_wait(epollfd, events, MAX_EVENTS, -1);

        if (new_events == -1) {
            error("Error in epoll_wait..\n");
        }

        for (int i = 0; i < new_events; ++i) {
            if (events[i].data.fd == sock_listen_fd) {
                sock_conn_fd = accept4(sock_listen_fd, (struct sockaddr *)&client_addr, &client_len, SOCK_NONBLOCK);
                if (__builtin_expect(sock_conn_fd == -1, 0)) {
                    error("Error accepting new connection..\n");
                }

                #ifdef EDGE
                    ev.events = EPOLLIN | EPOLLRDHUP | EPOLLET;
                #else
                    ev.events = EPOLLIN | EPOLLRDHUP;
                #endif
                ev.data.fd = sock_conn_fd;
                if (__builtin_expect(epoll_ctl(epollfd, EPOLL_CTL_ADD, sock_conn_fd, &ev) == -1, 0)) {
                    error("Error adding new event to epoll..\n");
                }
                clients[sock_conn_fd].len = 0; // reset client buffer len
                clients[sock_conn_fd].buffer = malloc(MAX_MESSAGE_LEN);
                #ifdef DEBUG
                printf("new client: fd=%d\n", sock_conn_fd);
                #endif
            }
            else
            {
                int clientfd = events[i].data.fd;

                if (__builtin_expect(events[i].events & EPOLLRDHUP, 0)) {
                    closeClient(epollfd, clientfd);
                    continue;
                }

                // for edge triggered events, we need to read all that's available
                read: ;

                int bytes = recv(clientfd,
                    clients[clientfd].buffer + clients[clientfd].len,
                    MAX_MESSAGE_LEN - clients[clientfd].len, 0
                );

                if (bytes <= 0) {
                    #ifdef EDGE
                        if (__builtin_expect(errno == EAGAIN, 1)) goto parse;
                    #endif
                    closeClient(epollfd, clientfd);
                    continue;
                }
                clients[clientfd].len += bytes;
                #ifdef DEBUG
                printf("client read: fd=%d, bytes=%d, inbuf=%d\n", clientfd, bytes, clients[clientfd].len);
                #endif
                #ifdef EDGE
                    goto read;
                #endif

                parse: ;
                // Check if http request is complete (very simplistic parser unusable in real servers)
                int nextReq;
                int numReq = countRequests(clients[clientfd].buffer, clients[clientfd].len, &nextReq);

                if (numReq) {
                    if (__builtin_expect(numReq > MAX_RESPONSES, 0)) {
                        fprintf(stderr, "FIXME: Too many responses needed\n");
                        exit(1);
                    }
                    bytes = send(clientfd, responseBuff, numReq * (sizeof(response) - 1), 0);
                    if (__builtin_expect(bytes <= 0, 0)) {
                        if (errno == EAGAIN) {
                            fprintf(stderr, "FIXME: System send buffer full\n");
                            exit(1);
                        }
                        closeClient(epollfd, clientfd);
                    }

                    if (__builtin_expect(bytes != numReq * (sizeof(response) - 1), 0)) {
                        fprintf(stderr, "FIXME: Whole response not sent\n");
                        exit(1);
                    }

                    if (nextReq == clients[clientfd].len) {
                        clients[clientfd].len = 0; // whole requests handled
                        continue;
                    }

                    if (nextReq) {
                        // we don't care about content, just looking for the request separator -> 4B are enough
                        printf("copy\n");
                        memcpy(clients[clientfd].buffer, clients[clientfd].buffer + clients[clientfd].len - 4, 4);
                        clients[clientfd].len = 4;
                    }
                }
            }
        }
    }
}

void closeClient(int epollfd, int clientfd) {
    #ifdef DEBUG
    printf("closing client: fd=%d\n", clientfd);
    #endif
    epoll_ctl(epollfd, EPOLL_CTL_DEL, clientfd, NULL);
    close(clientfd);
}

int countRequests(char *buf, int len, int *nextReq) {
    if (__builtin_expect(len < 4, 0)) return 0;

    int res = 0;
    *nextReq = 0;
    for (int idx = 0; idx <= len - 4; ++idx) {
        if (__builtin_expect(buf[idx] == '\r', 0)) {
            if (bcmp(sep, buf + idx, 4) != 0) {
                idx += 4;
                continue;
            }

            *nextReq = idx+4;
            ++res;
        }
    }

    return res;
}

void error(char* msg)
{
    perror(msg);
    printf("erreur...\n");
    exit(1);
}
