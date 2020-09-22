docker_build = docker build _suite/ -t httpbench

.PHONY: build
build:
	$(docker_build)

.PHONY: rebuild
rebuild:
	$(docker_build) --no-cache

.PHONY: performance_governor
performance_governor:
	sudo cpupower frequency-set -g performance

.PHONY: shell
shell: performance_governor
	docker run -it --rm --privileged -v $(shell pwd):/src:Z --network="host" httpbench

.PHONY: versions
versions:
	_suite/runner.d versions

.PHONY: all
all:
	_suite/runner.d bench --type all

.PHONY: single
single:
	_suite/runner.d bench --type singleCore

.PHONY: multi
multi:
	_suite/runner.d bench --type multiCore
