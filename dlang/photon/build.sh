#!/bin/bash

# build C http-parser
cc -static -O3 -Wall -fPIC -c -Iphoton/3rd-party/http-parser/ photon/3rd-party/http-parser/http_parser.c photon/src/utils/http.c

# build service
ldc2 $DFLAGS \
    -I=photon/src/ \
    app.d photon/src/photon/package.d \
    photon/src/photon/linux/core.d photon/src/photon/linux/support.d photon/src/photon/linux/syscalls.d \
    photon/src/utils/http_parser.d photon/src/utils/http_server.d \
    photon/src/photon/ds/intrusive_queue.d \
    http_parser.o http.o
