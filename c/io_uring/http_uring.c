// originating version hash: d4542ed2415cf2adfcb4505c3228aa70a1d4725c
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/poll.h>
#include <sys/socket.h>
#include <unistd.h>

#include "liburing.h"

#define MAX_CONNECTIONS     4096
#define BACKLOG             512
#define MAX_MESSAGE_LEN     2048
#define BUFFERS_COUNT       MAX_CONNECTIONS
#define MAX_RESPONSES 512

void add_accept(struct io_uring *ring, int fd, struct sockaddr *client_addr, socklen_t *client_len);
void add_socket_read(struct io_uring *ring, int fd, unsigned gid, size_t size, unsigned flags);
void add_socket_write(struct io_uring *ring, int fd, int numResp);
void add_provide_buf(struct io_uring *ring, __u16 bid, unsigned gid);
int countRequests(char *buf, int len, int *nextReq);

enum {
    ACCEPT,
    READ,
    WRITE,
    PROV_BUF,
};

typedef struct conn_info {
    __u32 fd;
    __u16 type;
    __u16 len;
} conn_info;

char bufs[BUFFERS_COUNT][MAX_MESSAGE_LEN] = {0};
int group_id = 1337;

const char response[] =
    "HTTP/1.1 200 OK\r\n"
    "Server: io_uring/raw_0123456789012345678901234567890123456\r\n"
    "X-Test: 01234567890123456789\r\n"
    "Connection: keep-alive\r\n"
    "Content-Type: text/plain\r\n"
    "Content-Length: 13\r\n"
    "\r\n"
    "Hello, World!";

const char sep[] = "\r\n\r\n";

char *responseBuff;

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Please give a port number: ./io_uring_echo_server [port]\n");
        exit(0);
    }

    // some variables we need
    int portno = strtol(argv[1], NULL, 10);
    struct sockaddr_in serv_addr, client_addr;
    socklen_t client_len = sizeof(client_addr);

    // disable SIGPIPE
    if (signal(SIGPIPE, SIG_IGN) == SIG_ERR) {
        perror("signal()");
        return 1;
    }

    // setup socket
    int sock_listen_fd = socket(AF_INET, SOCK_STREAM, 0);
    const int val = 1;
    if (setsockopt(sock_listen_fd, SOL_SOCKET, SO_REUSEADDR, &val, sizeof(val)) == -1
        || setsockopt(sock_listen_fd, SOL_SOCKET, SO_REUSEPORT, &val, sizeof(val)) == -1
        || setsockopt(sock_listen_fd, IPPROTO_TCP, TCP_NODELAY, &val, sizeof(val)) == -1) {
        perror("setsockopt()");
        exit(1);
    }

    memset(&serv_addr, 0, sizeof(serv_addr));
    serv_addr.sin_family = AF_INET;
    serv_addr.sin_port = htons(portno);
    serv_addr.sin_addr.s_addr = INADDR_ANY;

    // bind and listen
    if (bind(sock_listen_fd, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0) {
        perror("Error binding socket");
        exit(1);
    }
    if (listen(sock_listen_fd, BACKLOG) < 0) {
        perror("Error listening on socket");
        exit(1);
    }
    printf("io_uring echo server listening for connections on port: %d\n", portno);

    // initialize io_uring
    struct io_uring_params params;
    struct io_uring ring;
    memset(&params, 0, sizeof(params));

    if (io_uring_queue_init_params(512, &ring, &params) < 0) {
        perror("io_uring_init_failed...\n");
        exit(1);
    }

    // check if IORING_FEAT_FAST_POLL is supported
    if (!(params.features & IORING_FEAT_FAST_POLL)) {
        printf("IORING_FEAT_FAST_POLL not available in the kernel, quiting...\n");
        exit(0);
    }

    // check if buffer selection is supported
    struct io_uring_probe *probe;
    probe = io_uring_get_probe_ring(&ring);
    if (!probe || !io_uring_opcode_supported(probe, IORING_OP_PROVIDE_BUFFERS)) {
        printf("Buffer select not supported, skipping...\n");
        exit(0);
    }
    free(probe);

    // register buffers for buffer selection
    struct io_uring_sqe *sqe;
    struct io_uring_cqe *cqe;

    sqe = io_uring_get_sqe(&ring);
    io_uring_prep_provide_buffers(sqe, bufs, MAX_MESSAGE_LEN, BUFFERS_COUNT, group_id, 0);

    io_uring_submit(&ring);
    io_uring_wait_cqe(&ring, &cqe);
    if (cqe->res < 0) {
        printf("cqe->res = %d\n", cqe->res);
        exit(1);
    }
    io_uring_cqe_seen(&ring, cqe);

    // add first accept SQE to monitor for new incoming connections
    add_accept(&ring, sock_listen_fd, (struct sockaddr *)&client_addr, &client_len);

    // prep sendbuffer
    responseBuff = malloc(MAX_RESPONSES * (sizeof(response) - 1));
    for (int i = 0; i < MAX_RESPONSES; ++i) {
        memcpy(responseBuff + i*(sizeof(response) - 1), response, (sizeof(response) - 1));
    }

    // start event loop
    while (1) {
        io_uring_submit_and_wait(&ring, 1);
        struct io_uring_cqe *cqe;
        unsigned head;
        unsigned count = 0;

        // go through all CQEs
        io_uring_for_each_cqe(&ring, head, cqe) {
            ++count;
            struct conn_info conn_i;
            memcpy(&conn_i, &cqe->user_data, sizeof(conn_i));

            int type = conn_i.type;
            if (cqe->res == -ENOBUFS) {
                fprintf(stdout, "bufs in automatic buffer selection empty, this should not happen...\n");
                fflush(stdout);
                exit(1);
            } else if (type == PROV_BUF) {
                if (cqe->res < 0) {
                    printf("cqe->res = %d\n", cqe->res);
                    exit(1);
                }
            } else if (type == ACCEPT) {
                int sock_conn_fd = cqe->res;
                // only read when there is no error, >= 0
                if (sock_conn_fd >= 0) {
                    add_socket_read(&ring, sock_conn_fd, group_id, MAX_MESSAGE_LEN, IOSQE_BUFFER_SELECT);
                }

                // new connected client; read data from socket and re-add accept to monitor for new connections
                add_accept(&ring, sock_listen_fd, (struct sockaddr *)&client_addr, &client_len);
            } else if (type == READ) {
                int bytes_read = cqe->res;
                if (cqe->res <= 0) {
                    // connection closed or error
                    close(conn_i.fd);
                    if (cqe->flags & IORING_CQE_F_BUFFER) {
                        // give the buffer back
                        int bid = cqe->flags >> 16;
                        add_provide_buf(&ring, bid, group_id);
                    }
                } else {
                    // check for complete request
                    int bid = cqe->flags >> 16;

                    int nextReq;
                    int numReq = countRequests(bufs[bid], bytes_read, &nextReq);
                    if (numReq == 0 || nextReq != bytes_read) {
                        fprintf(stderr, "FIXME: partial request read!\n");
                        exit(1);
                    }

                    // give the buffer back
                    add_provide_buf(&ring, bid, group_id);

                    // write response
                    add_socket_write(&ring, conn_i.fd, numReq);

                    // add a new read for the existing connection
                    add_socket_read(&ring, conn_i.fd, group_id, MAX_MESSAGE_LEN, IOSQE_BUFFER_SELECT);
                }
            } else if (type == WRITE) {
                if (cqe->res <= 0) {
                    // connection closed or error
                    close(conn_i.fd);
                }
            }
        }

        io_uring_cq_advance(&ring, count);
    }
}

void add_accept(struct io_uring *ring, int fd, struct sockaddr *client_addr, socklen_t *client_len) {
    struct io_uring_sqe *sqe = io_uring_get_sqe(ring);
    io_uring_prep_accept(sqe, fd, client_addr, client_len, 0);

    conn_info conn_i = {
        .fd = fd,
        .type = ACCEPT,
    };
    memcpy(&sqe->user_data, &conn_i, sizeof(conn_i));
}

void add_socket_read(struct io_uring *ring, int fd, unsigned gid, size_t message_size, unsigned flags) {
    struct io_uring_sqe *sqe = io_uring_get_sqe(ring);
    io_uring_prep_recv(sqe, fd, NULL, message_size, 0);
    io_uring_sqe_set_flags(sqe, flags);
    sqe->buf_group = gid;

    conn_info conn_i = {
        .fd = fd,
        .type = READ,
    };
    memcpy(&sqe->user_data, &conn_i, sizeof(conn_i));
}

void add_socket_write(struct io_uring *ring, int fd, int numResp) {
    if (__builtin_expect(numResp > MAX_RESPONSES, 0)) {
        fprintf(stderr, "FIXME: Too many responses needed\n");
        exit(1);
    }

    struct io_uring_sqe *sqe = io_uring_get_sqe(ring);
    io_uring_prep_send(sqe, fd, responseBuff, numResp * (sizeof(response)-1), 0);

    conn_info conn_i = {
        .fd = fd,
        .type = WRITE,
    };
    memcpy(&sqe->user_data, &conn_i, sizeof(conn_i));
}

void add_provide_buf(struct io_uring *ring, __u16 bid, unsigned gid) {
    struct io_uring_sqe *sqe = io_uring_get_sqe(ring);
    io_uring_prep_provide_buffers(sqe, bufs[bid], MAX_MESSAGE_LEN, 1, gid, bid);

    conn_info conn_i = {
        .fd = 0,
        .type = PROV_BUF,
    };
    memcpy(&sqe->user_data, &conn_i, sizeof(conn_i));
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
