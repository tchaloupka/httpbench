# http bench

Simple framework to test HTTP servers, inspired by [Simple Web Benchmark](https://github.com/nuald/simple-web-benchmark) but focused on [dlang](https://dlang.org) frameworks and libraries.

It measures achievable RPS (requests per second) in a simple plaintext response test scenario.

Tests were gathered or modified from various places (including [TechEmpower](https://github.com/TechEmpower/FrameworkBenchmarks)).

It uses [docker](https://www.docker.com) container to build and host services on and can run locally or use load tester from remote host.

[wrk](https://github.com/wg/wrk) is used as a default load generator and requests statistics collector, but [hey](https://github.com/rakyll/hey) is supported too (just use `--tool` switch).

Tests can be run without docker too, one just needs to have installed tested language compilers and [wrk](https://github.com/wg/wrk)/[hey](https://github.com/rakyll/hey) workload generator (but this has been tested on linux only).

**Note for io_uring tests:**

* At least Linux kernel 5.7 is needed for tests to work.
* Problems with user limits on locked memory (`ulimit -l`) are possible too when run with regular user.
* There is some performance regression starting from [Kernel 5.7.16](https://github.com/axboe/liburing/issues/215). See also these: [#189](https://github.com/axboe/liburing/issues/189), [#8](https://github.com/frevib/io_uring-echo-server/issues/8).

## Tests

Tests are divided to two types:

* **singleCore** - services are started in single core mode to measure performance without multiple threads / processes (default)
* **multiCore**  - services are started to use all hosts CPU cores

Some of the tests are written just with a single thread usage. To be comparable with frameworks that can utilize more threads, `prefork.d` was added to the suite, that just forks multiple processes and pin them to separate CPUs (tests are named `prefork` or has `(PF)` in the name).

## Usage

### Build execution container

* `make build` - build execution container
* `make shell` - enter container

**Note:** Performance governor is set to `performance` with this command.

### Test runner

For simplicity, one can just run one of these commands (in the container shell):

```
make all        # runs all tests
make single     # runs tests limited to single CPU core usage
make multi      # runs tests limited to multiple CPU cores usage
```

Main entry point to more advanced tests is in `_suite/runner.d` which is a runnable CLI script.

* `_suite/runner.d list` - list available benchmarks
* `_suite/runner.d bench` - runs benchmarks
* `_suite/runner.d responses` - prints out sampled response from each benchmark service
* `_suite/runner.d versions` - prints out used language versions in Markdown table format

Use `_suite/runner.d -h` to print out CLI interface help.

Sample:

```
_suite/runner.d bench --type singleCore dlang rust # runs all dlang and rust tests
```

#### Remote host testing

As localhost only benchmarking is discouraged (see ie https://www.mnot.net/blog/2011/05/18/http_benchmark_rules), CLI supports executing of load tester from the remote host.

Steps:

* on a host that would run servers, enter the container shell
* from that run something like `_suite/runner.d bench --type singleCore -r foo@192.168.0.3 --host 192.168.0.2 dlang`

Where `-r` or `--remote` specifies username and hostname used for executing load tester through ssh.
`--host` is not in most cases necessary as CLI determines host IP from default route, but it's added for cases when it's needed anyway.

It's easier to generate ssh key and copy it's identity to the load generator host as otherwise underlying ssh command'll ask for password twice for each test (warmup and test itself).

Load tester (hey) must be installed on the load tester host.

Host that generates load should be ideally more performant (in a way that workload generator doesn't saturate the used CPUs).

### Frameworks / libraries

Some of the top of the [Techempower](https://www.techempower.com/benchmarks/#section=data-r19&hw=ph&test=plaintext) frameworks were added as a reference point.

Many of the tests there are using various tweaks unusable in a real life scenarios.

* no router (ie only match on path length, etc.)
* no HTTP request parser
* no Date header in the response
* prebuilt static text for response
* etc.

I've tried at least make response sizes to be of the same size for all the tests to be more fair.

#### C

These are added to determine the potential of the test environment configuration. They don't try to work as a generic HTTP servers, but just utilize the eventloop at the top speed.

Epoll and io_uring are added. Both named as `raw`.

#### dlang

##### [archttp](https://github.com/kerisy/archttp)

New http server framework using async io (epoll, kqueue, ...).

##### [arsd-official](https://code.dlang.org/packages/arsd-official)

I've wanted to add this popular library in the mix just for comparison. Currently three configurations of internal http servers are used:

* process - forked process, each serving one request
* threads - threadpool to handle connected clients
* hybrid - an experimental Linux-only hybrid implementation of forked processes, worker threads, and fibers in an event loop

They are the same in both type tests as they don't use (at the moment) some eventloop so we can compare this traditional way against the others.

See Adam's [description](http://dpldocs.info/this-week-in-d/Blog.Posted_2020_09_21.html#on-cgi.d-performance) for more.

##### [during](https://code.dlang.org/packages/during)

* **raw** - test that tries to be as fast as possible to make a theoretical limit of the used system facility (so no parsers, routers, ... - just plain event loop)

Using new asynchronous I/O [io_uring](https://lwn.net/Articles/776703/) it's interesting to compare against mostly used epoll on Linux systems.

##### [epoll](https://man7.org/linux/man-pages/man7/epoll.7.html)

Not a library, but just an underlying polling mechanism used by most frameworks.
Added to test theoretical limit of the system we measure on - same as `during/raw`

##### [eventcore](https://github.com/vibe-d/eventcore)

Library that is a basis for [vibe-d](https://github.com/vibe-d/vibe.d) framework. It generalizes event loop against epoll on linux (iocp and kqueue on windows and MacOS).

It's a microbenchmark as it has no proper http parser, router or response writer and currently only shows event loop potential of the library.

* callbacks - uses just callbacks to handle socket events
* fibers - uses fibers to emulate sync behavior on async events

##### [geario](https://github.com/kerisy/geario)

Asynchronous I/O library used by [archttp](https://github.com/kerisy/archttp) to show event base loop performance (micro benchmark).

##### [hunt](https://github.com/huntlabs/hunt-framework)

* hunt-http - idiomatic use of the framework (HTTP router, parser and all)
* hunt-pico - highly customized and optimized test that uses [picohttpparser](https://github.com/h2o/picohttpparser) and tweaked handlers for just the test purpose (prebuilt responses, no router, ...) - no wonder that it's relatively high in [Techempower](https://www.techempower.com/benchmarks/#section=data-r19&hw=ph&test=plaintext)

##### [lighttp](https://code.dlang.org/packages/lighttp)

Found this on [code.dlang.org](https://code.dlang.org/) so I've added it to the mix too.

It has parser, router, and response writer.

**Note:** Currently it's disabled due to the https://github.com/etcimon/libasync/issues/90

##### [mecca](https://code.dlang.org/packages/mecca)

Core library from [Weka](https://www.weka.io/).

It uses it's own low level fibers implementation.

**Note:** Uses some hacks to access `druntime` internals so it'd be able to switch fibers. But it won't compile with current release and some compilers. I've tried to patch it, but it still can have some problems.

##### [photon](https://github.com/DmitryOlshansky/photon)

It's not on [code.dlang.org](https://code.dlang.org/) but is an interesting library that rewrites glibc syscalls and emulates them via epoll eventloop and fibers underneath.

Test uses nodejs [http-parser](https://github.com/nodejs/http-parser) (not that fast as pico) and doesn't use router.

##### [serverino](https://github.com/trikko/serverino)

New simple to use HTTP server that uses managed subprocesses as a worker pool to handle individual requests. Single dependency library, using just standard phobos features.

It falls to the same category as `arsd`.

There are two variants of tests, one that uses same number if worker processes as is available CPUs and one that uses pool of 16 workers.

##### [vibe-core](https://github.com/vibe-d/vibe-core)

Higher level library that uses [eventcore](https://github.com/vibe-d/eventcore) and adds fiber backed tasks framework to handle event callbacks.

Still a microbenchmark as it only uses `TCPConnection` and reads request line by line and then just writes static response text.

No router or http parser used.

##### [vibe-d](https://github.com/vibe-d/vibe.d)

Finally most popular [dlang](https://dlang.org) web framework that has it all.

#### dotnet

[ASP.Net Core](https://docs.microsoft.com/en-us/aspnet/core/?view=aspnetcore-3.1) is used as a reference.

It has multiple tweaks mentioned above (simplistic router, prepared plaintext responses, ...).
It does some magic when HTTP pipelining is used.

#### golang

[fasthttp](https://github.com/valyala/fasthttp) is used as a reference.

Test uses HTTP parser, but no router.

#### rust

[Actix](https://actix.rs/) is used for comparison in two variants:

* actix-web - simple generic usage of the library
* actix-raw - more tweaked version with less generically used features and static responses

### Results

Currently test runner outputs results in a Markdown formatted table.

Column description:

* Res[B] - size of the sample response in bytes - to check responses are of the same size ideally
* Req - total number of requests load generator generated
* Err - number of responses with other than 200 OK results
* RPS - requests per second
* BPS - bytes per second
* min - minimal request time in [ms]
* 25% - 25% of requests has been completed within this time in [ms]
* 50% - 50% of requests has been completed within this time in [ms] (median)
* 75% - 75% of requests has been completed within this time in [ms]
* 99% - 99% of requests has been completed within this time in [ms]
* max - maximal request time in [ms]

#### Environment

| Language | Version  |
| -------- | -------- |
| go       | go1.18.1 |
| ldc2     | 1.29.0   |
| rust     | 1.61.0   |
| dotnet   | 6.0.300  |

* **Host:** AMD Ryzen 7 3700X 8-Core (16 threads), kernel 5.17.9, Fedora 36
* **Workload generator:** KVM VM with 14 pinned CPUs, Ubuntu 22.04 LTS, kernel 5.15.0-33
* **Service runner:** KVM VM with 2 pinned CPUs, Ubuntu 22.04 LTS, kernel 5.15.0-33
* **Network:** bridged network on the host
* **wrk version:** 4.1.0
* **hey version:** 0.1.4

**Note:** Only 2 cores for server and 14 for clients as otherwise `wrk` will saturate the CPUs, affecting the results (we need to utilize http server cores and not client workers) - should've bought a threadripper instead ;-)

#### Multi core results

* **Test command:** `for i in 8 64 128 256; do _suite/runner.d bench --type multiCore -r tomas@192.168.122.176 --host 192.168.122.175 --tool wrk -d 30 -c $i; done`

##### 2 concurrent clients

| Language | Framework | Category |      Name       |   Req   |  RPS  |   BPS   |  min  |  25%  |  50%  |  75%   |  99%   |  max   |
|:--------:|:---------:|:--------:|:---------------:| -------:| -----:| -------:| -----:| -----:| -----:| ------:| ------:| ------:|
|  dlang   |   epoll   |  micro   | raw - lvl (PF)  | 1316945 | 43752 | 8400446 | 0.026 | 0.041 | 0.044 |  0.048 |  0.071 |  3.351 |
|  dlang   |   epoll   |  micro   | raw - edge (PF) | 1297196 | 43096 | 8274472 | 0.027 | 0.042 | 0.045 |  0.048 |  0.069 |  5.888 |
|  dlang   |   mecca   |  micro   |     prefork     | 1289957 | 42855 | 8228297 | 0.028 | 0.042 | 0.045 |  0.048 |  0.067 |  1.875 |
|  dlang   | eventcore |  micro   |     cb (PF)     | 1284316 | 42668 | 8192314 | 0.027 | 0.043 | 0.045 |  0.048 |  0.069 |  1.591 |
|  dlang   | eventcore |  micro   |   fibers (PF)   | 1267849 | 42121 | 8087276 | 0.027 | 0.043 | 0.046 |   0.05 |   0.07 |  1.275 |
|  dlang   |  during   |  micro   |    raw (PF)     | 1246284 | 41404 | 7949718 | 0.027 | 0.044 | 0.047 |   0.05 |  0.069 |   3.06 |
|  dlang   | adio-http | platform |   epoll (PF)    | 1237865 | 41125 | 7896015 | 0.029 | 0.044 | 0.047 |  0.051 |   0.07 |  9.233 |
|    c     |   epoll   |  micro   | raw - edge (PF) | 1201327 | 39911 | 7662949 | 0.029 | 0.045 | 0.048 |  0.052 |  0.081 |  7.757 |
|    c     |   epoll   |  micro   | raw - lvl (PF)  | 1200583 | 39886 | 7658203 | 0.029 | 0.045 | 0.048 |  0.053 |  0.074 |  4.531 |
|  dlang   |  geario   |  micro   | geario (multi)  | 1175768 | 39062 | 7499915 | 0.029 | 0.046 | 0.049 |  0.054 |  0.073 |  6.632 |
|  dlang   | vibe-core |  micro   |     prefork     | 1166130 | 38741 | 7438437 | 0.027 | 0.046 |  0.05 |  0.054 |  0.077 |  5.855 |
|  dlang   |   hunt    |  micro   |    hunt-pico    | 1161331 | 38582 | 7407825 | 0.029 | 0.044 | 0.048 |  0.054 |  0.907 |  5.268 |
|  dotnet  |  aspcore  | platform |                 | 1155459 | 38387 | 7370369 | 0.031 | 0.046 | 0.049 |  0.054 |  0.308 | 10.679 |
|    c     | io_uring  |  micro   |    raw (PF)     | 1139972 | 37872 | 7271582 |  0.03 | 0.048 | 0.051 |  0.055 |  0.076 |  2.174 |
|    c     |   nginx   | platform |                 | 1110345 | 36888 | 7082599 |  0.03 | 0.048 | 0.052 |  0.057 |  0.079 |  3.845 |
|  golang  | fasthttp  | platform |                 | 1108316 | 36821 | 7069656 | 0.029 | 0.045 | 0.051 |  0.059 |  0.092 |  5.502 |
|  dlang   | adio-http | platform |  io_uring (PF)  | 1091040 | 36247 | 6959457 | 0.032 |  0.05 | 0.053 |  0.058 |  0.077 |  4.449 |
|   rust   | actix-raw |  micro   |                 | 1068205 | 35488 | 6813799 |  0.03 |  0.05 | 0.054 |  0.059 |  0.084 |   8.98 |
|  dlang   |  photon   |  micro   |                 | 1041491 | 34601 | 6643397 | 0.033 | 0.052 | 0.056 |  0.061 |  0.085 |  2.802 |
|  dlang   |   arsd    | platform |     hybrid      | 1018431 | 33834 | 6496304 | 0.036 | 0.052 | 0.056 |  0.061 |  0.124 |  8.286 |
|   rust   | actix-web | platform |                 | 1004730 | 33379 | 6408908 | 0.037 | 0.053 | 0.057 |  0.063 |  0.088 |  6.853 |
|  dlang   |   arsd    | platform |    processes    |  930335 | 30908 | 5934362 |  0.04 | 0.057 | 0.062 |  0.068 |  0.099 |  3.741 |
|  dlang   |  vibe-d   | platform |   manual (PF)   |  887273 | 29477 | 5659681 | 0.044 | 0.061 | 0.065 |  0.071 |  0.098 |  5.109 |
|  dlang   | serverino | platform |    serverino    |  790659 | 26267 | 5043406 | 0.051 | 0.066 | 0.073 |  0.082 |   0.12 |  1.077 |
|  dlang   | serverino | platform | serverino (16)  |  778587 | 25866 | 4966402 | 0.051 | 0.068 | 0.075 |  0.082 |  0.122 |  1.159 |
|  dlang   |  vibe-d   | platform |     gc (PF)     |  744552 | 24735 | 4749301 | 0.049 | 0.072 | 0.078 |  0.086 |  0.115 |  2.028 |
|  dlang   |   arsd    | platform |     threads     |  732525 | 24417 | 4688160 | 0.038 | 0.054 | 0.062 |  0.084 |  1.274 | 11.121 |
|  dlang   |  vibe-d   | platform |     manual      |  706821 | 23560 | 4523654 | 0.042 | 0.073 |  0.08 |  0.088 |  0.867 |  4.975 |
|  dlang   |  vibe-d   | platform |       gc        |  697335 | 23167 | 4448116 | 0.043 | 0.071 | 0.078 |  0.087 |  1.028 |  3.664 |
|  dlang   |  archttp  | platform | archttp (multi) |  239090 |  7943 | 1525092 | 0.015 | 0.098 | 8.904 | 26.506 | 43.522 | 48.034 |
|  dlang   |   hunt    | platform |    hunt-http    |   97055 |  3224 |  619088 | 0.064 | 0.097 | 0.156 | 19.925 | 43.427 | 44.241 |

##### 8 concurrent clients

| Language | Framework | Category |      Name       |   Req   |  RPS  |   BPS    |  min  |  25%  |  50%  |   75%   |   99%   |   max   |
|:--------:|:---------:|:--------:|:---------------:| -------:| -----:| --------:| -----:| -----:| -----:| -------:| -------:| -------:|
|  dlang   |   epoll   |  micro   | raw - lvl (PF)  | 2827675 | 93942 | 18036996 |  0.03 | 0.072 | 0.082 |   0.094 |   0.145 |    9.47 |
|  dlang   | eventcore |  micro   |     cb (PF)     | 2690728 | 89392 | 17163447 | 0.028 | 0.074 | 0.085 |   0.099 |   0.181 |   2.171 |
|    c     |   epoll   |  micro   | raw - lvl (PF)  | 2676087 | 88906 | 17070056 |  0.03 | 0.074 | 0.086 |   0.099 |   0.182 |   8.085 |
|  dlang   | vibe-core |  micro   |     prefork     | 2652698 | 88129 | 16920864 |  0.03 | 0.067 | 0.084 |   0.105 |   0.226 |   8.889 |
|  dlang   |   epoll   |  micro   | raw - edge (PF) | 2609447 | 86692 | 16644977 | 0.033 | 0.077 | 0.089 |   0.102 |   0.173 |   6.064 |
|  dlang   |  during   |  micro   |    raw (PF)     | 2603657 | 86500 | 16608044 | 0.032 |  0.07 | 0.085 |   0.106 |   0.205 |    2.38 |
|    c     |   epoll   |  micro   | raw - edge (PF) | 2584113 | 85850 | 16483378 | 0.031 | 0.072 | 0.087 |   0.106 |   0.208 |   8.438 |
|   rust   | actix-raw |  micro   |                 | 2560103 | 85053 | 16330225 | 0.033 | 0.073 | 0.087 |   0.107 |   0.223 |   9.417 |
|  dlang   | eventcore |  micro   |   fibers (PF)   | 2514774 | 83547 | 16041083 | 0.031 | 0.075 | 0.089 |   0.107 |   0.251 |   8.924 |
|  dlang   |   mecca   |  micro   |     prefork     | 2464883 | 81889 | 15722841 |  0.03 | 0.069 | 0.092 |   0.119 |    0.22 |   8.896 |
|  dlang   | adio-http | platform |  io_uring (PF)  | 2445958 | 81261 | 15602124 | 0.033 |  0.08 | 0.094 |    0.11 |   0.197 |   2.121 |
|    c     |   nginx   | platform |                 | 2431028 | 80765 | 15506889 | 0.034 | 0.074 | 0.091 |   0.115 |   0.221 |   2.427 |
|  dlang   | adio-http | platform |   epoll (PF)    | 2405297 | 79910 | 15342758 | 0.031 | 0.072 | 0.086 |   0.112 |   0.538 |   6.418 |
|  dlang   |   hunt    |  micro   |    hunt-pico    | 2366765 | 78630 | 15096972 | 0.028 | 0.067 | 0.084 |   0.114 |   1.233 |   7.417 |
|   rust   | actix-web | platform |                 | 2302597 | 76498 | 14687661 | 0.035 | 0.078 | 0.096 |   0.121 |   0.255 |   4.159 |
|    c     | io_uring  |  micro   |    raw (PF)     | 2278916 | 75711 | 14536607 | 0.034 | 0.068 | 0.083 |   0.129 |   0.421 |   4.659 |
|  golang  | fasthttp  | platform |                 | 2249368 | 74729 | 14348128 |  0.03 | 0.076 | 0.098 |   0.124 |   5.835 |  15.134 |
|  dlang   |  photon   |  micro   |                 | 2153010 | 71528 | 13733485 | 0.032 | 0.083 | 0.099 |    0.12 |   1.135 |   21.05 |
|  dlang   |  geario   |  micro   | geario (multi)  | 2118013 | 70365 | 13510249 | 0.038 | 0.106 | 0.114 |   0.122 |   0.165 |   7.373 |
|  dotnet  |  aspcore  | platform |                 | 1988982 | 66079 | 12687194 | 0.038 | 0.092 |  0.11 |   0.135 |   3.843 |  30.757 |
|  dlang   |   arsd    | platform |    processes    | 1575228 | 52333 | 10047965 | 0.043 | 0.103 | 0.134 |   0.184 |   1.199 |  11.995 |
|  dlang   |   arsd    | platform |     hybrid      | 1297644 | 43240 |  8302154 |  0.04 | 0.072 | 0.136 |   0.357 |   2.368 |   9.136 |
|  dlang   |  vibe-d   | platform |   manual (PF)   | 1247306 | 41438 |  7956237 | 0.046 | 0.141 |  0.17 |    0.23 |   0.463 |   6.198 |
|  dlang   |  vibe-d   | platform |     manual      | 1200248 | 39875 |  7656066 | 0.047 | 0.156 | 0.182 |    0.22 |    1.14 |   7.362 |
|  dlang   |  vibe-d   | platform |     gc (PF)     | 1197073 | 39769 |  7635814 | 0.049 | 0.162 | 0.188 |   0.226 |   0.443 |   8.018 |
|  dlang   | serverino | platform | serverino (16)  | 1150992 | 38238 |  7341875 | 0.051 | 0.145 | 0.192 |   0.251 |   0.708 |   4.853 |
|  dlang   |   arsd    | platform |     threads     | 1120041 | 37322 |  7165873 | 0.036 |  0.07 | 0.107 |    0.69 |   2.972 |  16.095 |
|  dlang   |  vibe-d   | platform |       gc        | 1074108 | 35803 |  6874291 | 0.048 | 0.151 | 0.188 |   0.262 |   1.707 |   16.34 |
|  dlang   |  archttp  | platform | archttp (multi) |  714054 | 23722 |  4554763 | 0.008 | 0.129 | 8.958 |  26.506 |    43.4 |  56.037 |
|  dlang   | serverino | platform |    serverino    |  651551 | 21696 |  4165760 | 0.053 | 0.084 |   0.1 | 2080.22 | 5833.28 | 6004.01 |
|  dlang   |   hunt    | platform |    hunt-http    |  341609 | 11349 |  2179034 | 0.069 | 0.107 | 0.164 |  20.117 |  43.332 |  48.096 |


##### 64 concurrent clients

| Language | Framework | Category |      Name       |   Req   |   RPS  |   BPS    |  min  |  25%  |  50%  |  75%   |   99%   |   max   |
|:--------:|:---------:|:--------:|:---------------:| -------:| ------:| --------:| -----:| -----:| -----:| ------:| -------:| -------:|
|    c     |   epoll   |  micro   | raw - lvl (PF)  | 5627346 | 187141 | 35931174 | 0.034 | 0.244 | 0.279 |  0.325 |   1.018 |  12.675 |
|  dlang   |   epoll   |  micro   | raw - lvl (PF)  | 5313638 | 176532 | 33894302 | 0.036 | 0.258 | 0.299 |  0.353 |   0.702 |  12.268 |
|    c     |   epoll   |  micro   | raw - edge (PF) | 5210803 | 173116 | 33238344 | 0.035 | 0.263 | 0.306 |  0.362 |   0.797 |  14.538 |
|  dlang   | eventcore |  micro   |     cb (PF)     | 5028078 | 167045 | 32072789 | 0.033 | 0.268 | 0.319 |  0.382 |   0.643 |   13.84 |
|  dlang   |   epoll   |  micro   | raw - edge (PF) | 5016841 | 166672 | 32001112 | 0.038 | 0.271 | 0.321 |  0.379 |    0.78 |  16.443 |
|    c     | io_uring  |  micro   |    raw (PF)     | 4684383 | 155627 | 29880449 | 0.037 | 0.281 | 0.342 |  0.416 |   0.699 |  11.766 |
|  dlang   |  during   |  micro   |    raw (PF)     | 4537648 | 150752 | 28944465 | 0.038 | 0.287 | 0.353 |   0.43 |   0.941 |  25.645 |
|  dlang   |   mecca   |  micro   |     prefork     | 4351115 | 144555 | 27754620 | 0.031 | 0.298 | 0.372 |  0.452 |   1.013 | 203.219 |
|  dlang   | eventcore |  micro   |   fibers (PF)   | 4341419 | 144233 | 27692772 | 0.033 | 0.302 | 0.376 |  0.453 |   0.809 |  24.307 |
|   rust   | actix-raw |  micro   |                 | 4200034 | 139536 | 26790914 | 0.037 |  0.31 | 0.387 |   0.47 |   0.879 |  27.138 |
|  dlang   | vibe-core |  micro   |     prefork     | 4134974 | 137374 | 26375913 | 0.034 | 0.311 | 0.394 |  0.481 |   0.946 |   20.58 |
|  dlang   | adio-http | platform |   epoll (PF)    | 4110871 | 136573 | 26222167 | 0.032 | 0.323 |   0.4 |   0.48 |   0.765 |   5.571 |
|  dlang   | adio-http | platform |  io_uring (PF)  | 4089210 | 135854 | 26083997 | 0.036 | 0.314 | 0.389 |  0.486 |   0.844 |  15.739 |
|    c     |   nginx   | platform |                 | 3862444 | 128320 | 24637516 | 0.042 | 0.335 | 0.413 |  0.512 |   0.878 |  11.056 |
|  dlang   |   hunt    |  micro   |    hunt-pico    | 3722501 | 123671 | 23744856 | 0.034 | 0.274 |  0.36 |   0.53 |    1.97 |  17.355 |
|   rust   | actix-web | platform |                 | 2964415 |  98485 | 18909225 | 0.051 | 0.417 | 0.523 |  0.683 |   1.319 |  10.352 |
|  golang  | fasthttp  | platform |                 | 2958469 |  98288 | 18871297 | 0.029 | 0.306 |  0.47 |  0.786 |   7.043 |  21.361 |
|  dlang   |  geario   |  micro   | geario (multi)  | 2819321 |  93665 | 17983708 | 0.043 | 0.301 | 0.717 |  0.811 |   1.163 |  10.923 |
|  dlang   |  photon   |  micro   |                 | 2434113 |  80867 | 15526567 | 0.031 | 0.178 |  0.34 |  0.393 |   1.612 |   9.751 |
|  dotnet  |  aspcore  | platform |                 | 2224500 |  73903 | 14189501 |  0.04 | 0.391 | 0.587 |   1.02 |   8.914 |  31.024 |
|  dlang   |   arsd    | platform |     hybrid      | 1696761 |  56370 | 10823193 | 0.041 | 0.136 | 0.631 |  2.353 |   9.328 |  26.921 |
|  dlang   |   arsd    | platform |    processes    | 1592590 |  52945 | 10165468 |  0.04 | 0.108 | 0.142 |  0.186 |   0.308 |  10.517 |
|  dlang   |  archttp  | platform | archttp (multi) | 1515304 |  50375 |  9672153 | 0.007 | 0.381 | 8.412 | 26.301 |  43.898 |  55.388 |
|  dlang   |  vibe-d   | platform |   manual (PF)   | 1445595 |  48074 |  9230270 | 0.048 | 0.919 | 1.099 |  1.434 |   2.485 |  14.146 |
|  dlang   |  vibe-d   | platform |     gc (PF)     | 1408010 |  46808 |  8987297 |  0.05 |  0.87 | 1.046 |  1.536 |   3.008 |  24.329 |
|  dlang   |  vibe-d   | platform |     manual      | 1302742 |  43280 |  8309849 | 0.045 | 0.902 | 1.101 |  1.662 |    3.53 |  30.144 |
|  dlang   |  vibe-d   | platform |       gc        | 1275478 |  42431 |  8146765 | 0.048 | 0.835 | 1.112 |  1.728 |   6.206 |  56.107 |
|  dlang   |   arsd    | platform |     threads     | 1132973 |  37640 |  7226937 | 0.036 | 0.063 | 0.075 |  0.107 |   2.339 |   9.042 |
|  dlang   |   hunt    | platform |    hunt-http    |  864997 |  28737 |  5517588 | 0.072 | 0.262 | 0.445 | 19.564 |  44.002 |  50.542 |
|  dlang   | serverino | platform |    serverino    |  668074 |  22217 |  4265720 | 0.053 | 0.075 | 0.091 |  0.102 | 19137.7 | 24316.2 |
|  dlang   | serverino | platform | serverino (16)  |  620034 |  20619 |  3958979 | 0.055 | 0.583 | 0.757 |  0.911 | 1074.18 | 2515.51 |

##### 128 concurrent clients

| Language | Framework | Category |      Name       |  Req    |  RPS   |   BPS    |  min  |  25%  |  50%   |  75%   |   99%   |   max   |
|:--------:|:---------:|:--------:|:---------------:| -------:| ------:| --------:| -----:| -----:| ------:| ------:| -------:| -------:|
|  dlang   |   epoll   |  micro   | raw - edge (PF) | 7072751 | 234975 | 45115222 |  0.05 | 0.466 |   0.52 |  0.581 |   0.885 |  17.171 |
|  dlang   |   epoll   |  micro   | raw - lvl (PF)  | 6984380 | 232039 | 44551526 | 0.049 | 0.469 |  0.523 |  0.585 |   0.962 |  28.866 |
|    c     |   epoll   |  micro   | raw - lvl (PF)  | 6815637 | 226433 | 43475159 |  0.04 | 0.478 |  0.534 |  0.601 |   1.012 |  20.963 |
|  dlang   |  during   |  micro   |    raw (PF)     | 6679695 | 221916 | 42608021 |  0.04 | 0.457 |  0.532 |   0.63 |   1.331 |  23.282 |
|    c     |   epoll   |  micro   | raw - edge (PF) | 6531244 | 216984 | 41661091 | 0.046 | 0.491 |  0.555 |  0.638 |   1.212 |  21.052 |
|  dlang   | eventcore |  micro   |     cb (PF)     | 6078832 | 201954 | 38775273 | 0.033 |  0.51 |  0.593 |  0.696 |   2.463 |  19.506 |
|  dlang   |   mecca   |  micro   |     prefork     | 5709961 | 189699 | 36422342 | 0.033 | 0.545 |  0.641 |  0.752 |   1.207 | 407.954 |
|    c     | io_uring  |  micro   |    raw (PF)     | 5568514 | 185000 | 35520089 | 0.028 | 0.531 |  0.635 |  0.767 |   4.337 |  20.171 |
|  dlang   | eventcore |  micro   |   fibers (PF)   | 5324433 | 176891 | 33963160 | 0.035 |  0.57 |   0.68 |  0.803 |   4.519 |  16.985 |
|   rust   | actix-raw |  micro   |                 | 5103294 | 169544 | 32552573 | 0.048 | 0.606 |   0.72 |  0.843 |   2.285 |  22.292 |
|  dlang   | adio-http | platform |   epoll (PF)    | 4743039 | 157576 | 30254600 | 0.034 | 0.639 |  0.781 |  0.925 |    3.55 |  20.308 |
|  dlang   |  geario   |  micro   | geario (multi)  | 4701167 | 156340 | 30017428 | 0.051 | 0.436 |  0.527 |  1.075 |   2.115 |  98.489 |
|  dlang   | adio-http | platform |  io_uring (PF)  | 4703045 | 156247 | 29999489 | 0.039 | 0.621 |  0.769 |  0.947 |   2.314 |    21.8 |
|  dlang   |   hunt    |  micro   |    hunt-pico    | 4181250 | 138911 | 26671096 | 0.043 | 0.505 |  0.757 |  1.131 |   3.646 |  23.918 |
|    c     |   nginx   | platform |                 | 3862522 | 128322 | 24638014 | 0.041 | 0.736 |  0.958 |  1.191 |   2.031 |  29.225 |
|   rust   | actix-web | platform |                 | 3357019 | 111528 | 21413543 | 0.104 | 0.801 |  1.078 |  1.412 |   2.836 |  21.864 |
|  golang  | fasthttp  | platform |                 | 3140006 | 104319 | 20029274 |  0.03 | 0.617 |  1.063 |  1.732 |   8.255 |  38.465 |
|  dlang   |  photon   |  micro   |                 | 3026070 | 100533 | 19302506 | 0.036 | 0.443 |  0.605 |  1.376 |    5.03 |  35.768 |
|  dotnet  |  aspcore  | platform |                 | 2394041 |  79536 | 15270959 | 0.039 | 0.915 |  1.293 |  2.032 |  10.216 |  30.163 |
|  dlang   |   arsd    | platform |     hybrid      | 1862934 |  61953 | 11895022 | 0.042 | 0.558 |  0.942 |  6.163 |  20.563 |  76.829 |
|  dlang   |   arsd    | platform |    processes    | 1600493 |  53190 | 10212517 |  0.04 | 0.108 |  0.143 |  0.183 |   0.301 |   4.672 |
|  dlang   |  vibe-d   | platform |   manual (PF)   | 1468587 |  48806 |  9370844 | 0.049 | 1.809 |  2.388 |  3.328 |   7.578 |  44.817 |
|  dlang   |  vibe-d   | platform |     gc (PF)     | 1423990 |  47340 |  9089297 | 0.048 | 2.112 |  2.354 |  3.463 |   6.608 |  64.523 |
|  dlang   |  archttp  | platform | archttp (multi) | 1413128 |  46963 |  9016968 | 0.008 | 0.997 | 11.483 | 29.116 |  46.461 |  55.152 |
|  dlang   |  vibe-d   | platform |       gc        | 1339297 |  44524 |  8548704 | 0.045 |  1.72 |  2.612 |  3.723 |   10.68 |  50.342 |
|  dlang   |  vibe-d   | platform |     manual      | 1322315 |  43974 |  8443115 | 0.046 | 1.999 |   2.28 |  3.857 |   8.176 |  77.187 |
|  dlang   |   arsd    | platform |     threads     | 1140145 |  37903 |  7277521 | 0.037 |  0.06 |  0.072 |  0.104 |   2.343 |  10.562 |
|  dlang   |   hunt    | platform |    hunt-http    |  752325 |  25019 |  4803671 |  0.07 | 0.497 |  2.513 | 23.563 |  46.902 |  54.783 |
|  dlang   | serverino | platform |    serverino    |  676916 |  22488 |  4317869 | 0.055 |  0.07 |  0.078 |  0.102 | 18361.5 | 24081.2 |
|  dlang   | serverino | platform | serverino (16)  |  605569 |  20118 |  3862765 | 0.055 | 0.571 |   0.75 |  0.937 |  99.112 | 2356.72 |
|  dlang   | vibe-core |  micro   |     prefork     | 4996132 | 165984 | 31869014 | 0.032 | 0.604 |  0.736 |  0.864 |   4.641 |  32.442 |

##### 256 concurrent clients

| Language | Framework | Category |      Name       |  Req    |  RPS   |   BPS    |  min  |  25%  |  50%   |  75%   |   99%   |   max   |
|:--------:|:---------:|:--------:|:---------------:| -------:| ------:| --------:| -----:| -----:| ------:| ------:| -------:| -------:|
|  dlang   |   epoll   |  micro   | raw - lvl (PF)  | 8320651 | 276433 | 53075248 |  0.06 | 0.777 |  0.881 |  0.998 |   1.777 |   17.47 |
|  dlang   |   epoll   |  micro   | raw - edge (PF) | 7878303 | 261737 | 50253627 | 0.073 |  0.84 |  0.936 |  1.042 |   1.779 |   12.73 |
|    c     |   epoll   |  micro   | raw - lvl (PF)  | 7869349 | 261440 | 50196511 | 0.049 | 0.807 |  0.918 |   1.05 |   4.203 |  23.584 |
|  dlang   | eventcore |  micro   |     cb (PF)     | 7817616 | 259721 | 49866520 | 0.036 | 0.832 |  0.931 |  1.058 |   1.772 |  20.822 |
|    c     |   epoll   |  micro   | raw - edge (PF) | 7780451 | 258486 | 49629454 | 0.067 | 0.834 |  0.946 |  1.061 |   2.597 |  13.222 |
|  dlang   |  during   |  micro   |    raw (PF)     | 7623010 | 253256 | 48625180 | 0.043 | 0.831 |  0.944 |   1.08 |   2.461 |  19.509 |
|    c     | io_uring  |  micro   |    raw (PF)     | 7429070 | 246812 | 47388087 | 0.052 | 0.848 |  0.959 |  1.104 |   3.353 |  22.446 |
|  dlang   | eventcore |  micro   |   fibers (PF)   | 7233458 | 240314 | 46140330 | 0.033 | 0.871 |  0.994 |  1.151 |   3.312 |  18.625 |
|  dlang   |   mecca   |  micro   |     prefork     | 6186368 | 205527 | 39461217 |  0.03 |  0.96 |  1.152 |  1.379 |   6.946 | 839.203 |
|  dlang   | vibe-core |  micro   |     prefork     | 5614008 | 186511 | 35810283 | 0.033 | 1.066 |  1.297 |   1.53 |   6.699 |  31.666 |
|   rust   | actix-raw |  micro   |                 | 5594392 | 185921 | 35697017 | 0.061 | 1.082 |  1.305 |  1.529 |   5.673 |  21.137 |
|  dlang   | adio-http | platform |   epoll (PF)    | 5475263 | 182144 | 34971739 | 0.032 | 1.085 |  1.335 |  1.597 |   5.205 | 213.225 |
|  dlang   | adio-http | platform |  io_uring (PF)  | 5413654 | 179855 | 34532278 | 0.047 | 1.028 |  1.312 |  1.658 |   4.116 | 208.183 |
|  dlang   |  geario   |  micro   | geario (multi)  | 5232089 | 173939 | 33396312 |  0.11 | 0.843 |  1.001 |  2.133 |   4.309 | 224.177 |
|    c     |   nginx   | platform |                 | 4410031 | 146610 | 28149134 | 0.075 | 1.184 |  1.676 |  2.059 |   5.458 |  52.411 |
|   rust   | actix-web | platform |                 | 3830410 | 127425 | 24465692 |  0.07 | 1.253 |  1.911 |    2.5 |   5.891 |  35.206 |
|  dlang   |   hunt    |  micro   |    hunt-pico    | 3530619 | 117374 | 22535865 | 0.069 |  1.18 |  1.929 |  2.904 |   8.324 |  25.105 |
|  dlang   |  photon   |  micro   |                 | 3387719 | 112548 | 21609370 | 0.033 | 0.729 |  1.025 |  1.994 |   6.775 |  20.236 |
|  golang  | fasthttp  | platform |                 | 3334498 | 110780 | 21269887 | 0.032 | 1.321 |  2.066 |  3.075 |   8.758 |  40.004 |
|  dotnet  |  aspcore  | platform |                 | 2362570 |  78569 | 15085249 |  0.04 | 1.779 |   2.76 |  4.348 |  13.526 |  34.656 |
|  dlang   |   arsd    | platform |     hybrid      | 1796748 |  59752 | 11472418 | 0.041 | 0.981 |  2.424 |  9.234 |  22.832 |  99.006 |
|  dlang   |   arsd    | platform |    processes    | 1580837 |  52554 | 10090448 |  0.04 | 0.108 |  0.142 |  0.187 |   0.323 |   9.946 |
|  dlang   |  vibe-d   | platform |     manual      | 1530483 |  50880 |  9769040 | 0.048 | 3.013 |  4.603 |  6.533 |  13.285 |  51.639 |
|  dlang   |  vibe-d   | platform |   manual (PF)   | 1519494 |  50515 |  9698897 | 0.044 | 3.383 |  4.194 |  6.656 |   13.98 |  50.202 |
|  dlang   |  vibe-d   | platform |     gc (PF)     | 1491812 |  49578 |  9519039 | 0.045 | 3.584 |  4.946 |  6.377 |  10.759 |  36.438 |
|  dlang   |  archttp  | platform | archttp (multi) | 1461728 |  48578 |  9327077 | 0.005 | 3.438 | 14.787 | 32.665 |  51.619 | 301.141 |
|  dlang   |  vibe-d   | platform |       gc        | 1316828 |  43792 |  8408080 | 0.045 | 3.759 |  5.585 |  7.426 |  19.904 |  67.111 |
|  dlang   |   arsd    | platform |     threads     | 1137409 |  37800 |  7257644 | 0.037 | 0.059 |  0.071 |  0.103 |    2.33 |  11.058 |
|  dlang   | serverino | platform |    serverino    |  703161 |  23391 |  4491247 | 0.053 | 0.071 |  0.078 |    0.1 | 16682.8 |   28452 |
|  dlang   |   hunt    | platform |    hunt-http    |  700928 |  23294 |  4472521 | 0.072 | 1.293 |  7.334 |  30.04 |  51.487 |  61.043 |
|  dlang   | serverino | platform | serverino (16)  |  530500 |  17630 |  3385044 | 0.056 | 0.545 |  0.946 |  1.108 |   3.698 | 2280.68 |

#### Pipelining

For an idea of how HTTP pipelining is handled in the frameworks, here are some results.

**Command:** `_suite/runner.d bench --type multiCore -r tomas@192.168.122.176 --host 192.168.122.175 --tool wrk -d 30 -c 256 --pipeline 10`

| Language | Framework | Category |      Name       |   Req    |   RPS   |    BPS    |  min  |  25%   |  50%   |  75%   |   99%   |   max   |
|:--------:|:---------:|:--------:|:---------------:| --------:| -------:| ---------:| -----:| ------:| ------:| ------:| -------:| -------:|
|    c     |   epoll   |  micro   | raw - lvl (PF)  | 64200830 | 2132917 | 409520244 | 0.072 |  0.399 |  0.677 |  0.968 |    2.68 |  15.774 |
|  dlang   |   epoll   |  micro   | raw - lvl (PF)  | 62465150 | 2075254 | 398448797 | 0.064 |  0.409 |  0.695 |  0.987 |   4.849 |  19.534 |
|  dlang   |  during   |  micro   |    raw (PF)     | 60572640 | 2012380 | 386376972 | 0.113 |  0.422 |  0.717 |   1.03 |   2.087 |   15.62 |
|    c     |   epoll   |  micro   | raw - edge (PF) | 60367460 | 2005563 | 385068183 | 0.072 |  0.423 |  0.719 |  1.024 |   5.345 |  21.092 |
|  dlang   |   epoll   |  micro   | raw - edge (PF) | 58338900 | 1938169 | 372128531 | 0.108 |  0.439 |  0.746 |  1.057 |   1.718 |  22.185 |
|    c     | io_uring  |  micro   |    raw (PF)     | 57151970 | 1898736 | 364557416 | 0.107 |  0.447 |  0.761 |   1.08 |   1.848 |  17.091 |
|  dlang   |   mecca   |  micro   |     prefork     | 56798510 | 1886993 | 362302788 | 0.042 |  0.449 |  0.763 |  1.089 |   5.322 |  408.63 |
|   rust   | actix-raw |  micro   |                 | 34853450 | 1159462 | 222616846 | 0.092 |  0.734 |  1.257 |  1.961 |   5.736 |  23.369 |
|  dotnet  |  aspcore  | platform |                 | 24219490 |  804901 | 154541112 | 0.046 |  1.061 |  1.845 |  2.918 |     9.9 |  35.599 |
|  dlang   | adio-http | platform |  io_uring (PF)  | 18702980 |  621361 | 119301400 | 0.092 |  1.373 |  2.368 |  3.555 |   7.398 | 232.723 |
|  dlang   | adio-http | platform |   epoll (PF)    | 18505080 |  615400 | 118156812 | 0.047 |  1.406 |  2.496 |  4.002 |  10.479 |  206.82 |
|  dlang   |   hunt    |  micro   |    hunt-pico    | 17854979 |  593188 | 113892224 | 0.136 |  1.437 |  2.461 |  3.668 |  36.006 |  64.379 |
|  dlang   | eventcore |  micro   |     cb (PF)     | 17830078 |  592361 | 113733387 | 0.089 |   1.44 |  2.476 |  3.688 |   37.86 |  66.244 |
|  dlang   | eventcore |  micro   |   fibers (PF)   | 17758857 |  589995 | 113279087 | 0.097 |  1.445 |  2.487 |  3.725 |  37.311 |  63.008 |
|  dlang   | vibe-core |  micro   |     prefork     | 16909359 |  561959 | 107896208 | 0.079 |  1.519 |  2.627 |  4.095 |  42.644 |  77.024 |
|  golang  | fasthttp  | platform |                 | 16635590 |  552677 | 106114062 | 0.048 |  1.577 |  2.838 |  4.533 |  10.817 |  59.784 |
|   rust   | actix-web | platform |                 | 15935000 |  529577 | 101678963 |   0.1 |  1.577 |  2.773 |  4.039 |  18.829 |  65.503 |
|  dlang   |  photon   |  micro   |                 |  8801333 |  292500 |  56160051 | 0.075 |  2.329 |  4.599 |  8.442 |  45.838 |  83.562 |
|    c     |   nginx   | platform |                 |  6023810 |  200126 |  38424302 | 0.173 |  4.309 |  7.861 | 12.989 |  43.237 | 112.092 |
|  dlang   |  archttp  | platform | archttp (multi) |  3225950 |  107174 |  20577488 | 0.011 |  0.122 |  0.127 |  0.132 |   0.181 |   4.953 |
|  dlang   |  vibe-d   | platform |     manual      |  2706937 |   89961 |  17272579 | 0.138 |  9.564 | 16.894 | 28.604 | 560.433 | 1687.64 |
|  dlang   |  vibe-d   | platform |     gc (PF)     |  2616634 |   87018 |  16707473 | 0.134 |  9.869 | 17.331 | 28.298 | 358.139 | 1884.48 |
|  dlang   |  vibe-d   | platform |   manual (PF)   |  2565922 |   85274 |  16372782 | 0.127 | 10.109 | 17.509 | 27.832 |  140.48 | 1176.18 |
|  dlang   |  vibe-d   | platform |       gc        |  2031871 |   67526 |  12965079 | 0.235 | 12.752 | 22.097 |  33.79 | 548.096 | 2267.84 |
|  dlang   |   hunt    | platform |    hunt-http    |  1383454 |   45977 |   8827622 | 2.078 | 19.197 | 31.107 | 44.548 |  84.404 | 119.169 |

**Note:** `arsd`, `geario` and `serverino` have problems with this and doesn't finish

#### Special note

As `arsd` (excluding `arsd/hybrid`) and `serverino` doesn't use async IO, requests can be blocked for some time when keep-alive connections are used (on by default). With `wrk` it's not visible much, as it just bursts requests from any client that communicates and some of the clients doesn't receive any response.

To make it stand out more, here are some results with `hey` with number of clients equal to available CPU cores (so they should be completed without waiting in queue) and a multiple of that.

**Command:** `for i in 2 16; do _suite/runner.d bench --type multiCore -r tomas@192.168.122.176 --host 192.168.122.175 --tool hey -b 2 -c $i arsd serverino actix-web; done`

##### 2 concurrent clients

| Language | Framework | Category |      Name      |  Req  |  RPS  |   BPS   | min | 25% | 50% | 75% | 99% | max |
|:--------:|:---------:|:--------:|:--------------:| -----:| -----:| -------:| ---:| ---:| ---:| ---:| ---:| ---:|
|   rust   | actix-web | platform |                | 2000 | 19436 | 3731778 | 0.1 | 0.1 | 0.1 | 0.1 | 0.2 | 1.1 |
|  dlang   |   arsd    | platform |    threads     | 2000 | 18709 | 3592142 | 0.1 | 0.1 | 0.1 | 0.1 | 0.3 | 1.2 |
|  dlang   |   arsd    | platform |   processes    | 2000 | 17921 | 3440860 | 0.1 | 0.1 | 0.1 | 0.1 | 0.2 | 1.3 |
|  dlang   |   arsd    | platform |     hybrid     | 2000 | 17528 | 3365468 | 0.1 | 0.1 | 0.1 | 0.1 | 0.2 | 1.2 |
|  dlang   | serverino | platform | serverino (16) | 2000 | 16611 | 3189368 | 0.1 | 0.1 | 0.1 | 0.1 | 0.3 | 4.4 |
|  dlang   | serverino | platform |   serverino    | 2000 | 15625 | 3000000 | 0.1 | 0.1 | 0.1 | 0.1 | 0.3 | 1.1 |

##### 64 concurrent clients

| Language | Framework | Category |      Name      |  Req  |  RPS  |   BPS   | min | 25% | 50% | 75% |  99%  |  max   |
|:--------:|:---------:|:--------:|:--------------:| -----:| -----:| -------:| ---:| ---:| ---:| ---:| -----:| ------:|
|   rust   | actix-web | platform |                | 16000 | 51101 | 9811561 | 0.1 | 0.2 | 0.2 | 0.3 |   1.3 |    9.5 |
|  dlang   |   arsd    | platform |     hybrid     | 16000 | 35938 | 6900269 | 0.1 | 0.1 | 0.2 | 0.4 |   2.6 |    7.8 |
|  dlang   | serverino | platform | serverino (16) | 16000 | 13412 | 2575236 | 0.1 | 0.4 | 0.5 | 0.6 |   1.9 | 1082.3 |
|  dlang   |   arsd    | platform |    threads     | 16000 |  4165 |  799833 | 0.1 | 0.1 | 0.2 | 0.2 | 2.301 | 3538.1 |
|  dlang   |   arsd    | platform |   processes    | 16000 |  2450 |  470400 | 0.1 | 0.1 | 0.2 | 0.2 |   0.8 | 6430.2 |
|  dlang   | serverino | platform |   serverino    | 16000 |  1812 |  347971 | 0.1 | 0.1 | 0.1 | 0.1 |   0.3 |   8690 |
