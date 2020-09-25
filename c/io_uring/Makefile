CCFLAGS ?= -Wall -O3 -D_GNU_SOURCE -luring

.PHONY: liburing
liburing:
	if [ ! -d "./liburing" ]; then git clone git@github.com:axboe/liburing.git; fi
	+$(MAKE) -C ./liburing

.PHONY: http_uring
http_uring: liburing
	$(CC) http_uring.c -o ./http_uring -I./liburing/src/include/ -L./liburing/src/ ${CCFLAGS}
