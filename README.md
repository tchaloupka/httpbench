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

##### 8 concurrent clients

| Language | Framework | Category |      Name       |    Req    |  RPS   |    BPS     |  min  |  25%  |  50%  |  75%   |   99%   |   max   |
|:--------:|:---------:|:--------:|:---------------:| ---------:| ------:| ----------:| -----:| -----:| -----:| ------:| -------:| -------:|
|    c     |   epoll   |  micro   | raw - edge (PF) |   2790511 |  92708 |   17799937 |  0.03 | 0.064 | 0.074 |  0.094 |   0.236 |   7.239 |
|  dlang   |   epoll   |  micro   | raw - lvl (PF)  |   2720815 |  90392 |   17355364 |  0.03 | 0.068 |  0.08 |  0.097 |   0.256 |  13.114 |
|  dlang   |   epoll   |  micro   | raw - edge (PF) |   2648211 |  87980 |   16892242 | 0.031 | 0.066 | 0.078 |  0.101 |    0.27 |   9.421 |
|  dlang   | adio-http | platform |   epoll (PF)    |   2573825 |  85509 |   16417754 |  0.03 | 0.064 | 0.077 |  0.106 |   0.532 |   9.721 |
|    c     |   epoll   |  micro   | raw - lvl (PF)  |   2511807 |  83448 |   16022157 |  0.03 | 0.065 | 0.076 |  0.115 |   0.335 |   8.215 |
|  dlang   | adio-http | platform |  io_uring (PF)  |   2440794 |  81089 |   15569184 | 0.032 | 0.064 | 0.076 |  0.123 |   0.287 |  11.848 |
|  dlang   | eventcore |  micro   |     cb (PF)     |   2399193 |  79707 |   15303822 |  0.03 | 0.059 |  0.07 |  0.144 |   0.326 |  19.262 |
|    c     | io_uring  |  micro   |    raw (PF)     |   2384903 |  79232 |   15212670 | 0.029 | 0.066 | 0.078 |  0.127 |   0.342 |   4.451 |
|   rust   | actix-raw |  micro   |                 |   2355355 |  78250 |   15024191 |  0.03 | 0.065 | 0.077 |  0.134 |   0.313 |   4.031 |
|  golang  | fasthttp  | platform |                 |   2322196 |  77149 |   14812678 | 0.031 |  0.07 |  0.09 |   0.12 |   6.828 |   32.07 |
|   rust   | actix-web | platform |                 |   2320963 |  77108 |   14804813 | 0.035 | 0.065 | 0.078 |  0.135 |   0.426 |  13.162 |
|  dlang   |   hunt    |  micro   |    hunt-pico    |   2248670 |  74706 |   14343675 | 0.028 | 0.058 | 0.072 |  0.162 |   1.315 |  18.151 |
|  dlang   | vibe-core |  micro   |     prefork     |   2246583 |  74637 |   14330363 | 0.031 | 0.077 | 0.096 |  0.129 |   0.377 |  13.259 |
|  dlang   |  during   |  micro   |    raw (PF)     |   2217185 |  73660 |   14142841 | 0.034 | 0.062 | 0.075 |  0.154 |   0.327 |   7.125 |
|  dotnet  |  aspcore  | platform |                 |   2147219 |  71336 |   13696546 | 0.034 | 0.078 | 0.097 |  0.128 |   4.719 |  19.982 |
|  dlang   | eventcore |  micro   |   fibers (PF)   |   2123009 |  70531 |   13542117 |  0.03 | 0.057 | 0.078 |  0.169 |   0.287 |  14.366 |
|    c     |   nginx   | platform |                 |   2017077 |  67012 |   12866404 | 0.032 | 0.067 |  0.09 |  0.176 |   0.312 |  16.469 |
|  dlang   |  photon   |  micro   |                 |   1935339 |  64296 |   12345019 | 0.033 | 0.074 | 0.088 |  0.171 |   1.139 |  13.256 |
|  dlang   |   mecca   |  micro   |     prefork     |   1867470 |  62042 |   11912100 |  0.03 | 0.072 | 0.133 |  0.171 |   0.265 |  10.289 |
|  dlang   |   arsd    | platform |    processes    |   1584061 |  52626 |   10104309 | 0.045 | 0.098 | 0.128 |  0.186 |   0.796 |  23.136 |
|  dlang   |   arsd    | platform |     hybrid      |   1532173 |  50902 |    9773329 | 0.048 | 0.127 | 0.136 |  0.173 |   0.293 |   7.827 |
|  dlang   |  vibe-d   | platform |   manual (PF)   |   1196769 |  39879 |    7656769 | 0.047 | 0.094 | 0.135 |  0.369 |   4.094 |  42.847 |
|  dlang   |  vibe-d   | platform |     gc (PF)     |   1105433 |  36725 |    7051266 | 0.042 | 0.079 | 0.174 |  0.418 |   1.444 |  13.305 |
|  dlang   |   arsd    | platform |     threads     |   1096423 |  36535 |    7014768 | 0.038 |  0.07 | 0.113 |  0.686 |   2.958 |  14.707 |
|  dlang   |  vibe-d   | platform |       gc        |   1093941 |  36452 |    6998889 | 0.047 | 0.105 | 0.148 |  0.399 |   3.209 |  13.158 |
|  dlang   |  vibe-d   | platform |     manual      |   1086332 |  36199 |    6950208 | 0.043 |   0.1 | 0.172 |  0.342 |   1.882 |   24.26 |
|  dlang   |  archttp  | platform |     archttp     |    870892 |  29020 |    5397731 | 0.008 | 0.102 |  7.94 | 25.855 |  43.205 |  48.457 |
|  dlang   | serverino | platform |    serverino    |    734680 |  24464 |    4697254 | 0.051 | 0.072 | 0.095 | 1994.2 | 5833.68 | 6003.92 |
|  dlang   |   hunt    | platform |    hunt-http    |    364728 |  12141 |    2331150 |  0.07 | 0.101 | 0.142 | 20.318 |  43.359 |  55.293 |

##### 64 concurrent clients

| Language | Framework | Category |      Name       |    Req    |   RPS   |    BPS     |  min  |  25%  |  50%  |  75%   |   99%   |   max   |
|:--------:|:---------:|:--------:|:---------------:| ---------:| -------:| ----------:| -----:| -----:| -----:| ------:| -------:| -------:|
|    c     |   epoll   |  micro   | raw - edge (PF) |   4611417 |  153305 |   29434576 | 0.034 | 0.248 | 0.308 |    0.4 |  12.033 |  67.768 |
|  dlang   |   epoll   |  micro   | raw - edge (PF) |   4610214 |  153163 |   29407345 | 0.034 | 0.249 | 0.315 |  0.406 |  11.359 |  60.494 |
|    c     |   epoll   |  micro   | raw - lvl (PF)  |   4562896 |  151591 |   29105516 | 0.035 | 0.241 | 0.299 |  0.406 |   12.46 |  44.813 |
|  dlang   |   epoll   |  micro   | raw - lvl (PF)  |   4548328 |  151308 |   29051196 | 0.033 | 0.247 | 0.308 |  0.403 |   12.14 |  66.484 |
|  dlang   |  during   |  micro   |    raw (PF)     |   4412018 |  146578 |   28143104 | 0.031 | 0.247 | 0.323 |  0.439 |  13.338 |  59.946 |
|  dlang   | eventcore |  micro   |   fibers (PF)   |   4386924 |  145841 |   28001642 | 0.035 | 0.248 | 0.326 |  0.436 |  19.652 |  99.716 |
|  dlang   | eventcore |  micro   |     cb (PF)     |   4387273 |  145756 |   27985262 | 0.035 | 0.247 | 0.327 |  0.448 |  12.517 |  81.026 |
|  dlang   |   mecca   |  micro   |     prefork     |   4354775 |  144676 |   27777966 | 0.038 | 0.275 | 0.354 |  0.438 |  12.299 | 202.992 |
|    c     | io_uring  |  micro   |    raw (PF)     |   4236523 |  140748 |   27023668 | 0.034 | 0.249 |  0.32 |  0.457 |  17.444 |  76.064 |
|  dlang   | vibe-core |  micro   |     prefork     |   4189722 |  139193 |   26725137 | 0.032 | 0.259 |  0.37 |  0.476 |  11.004 | 112.111 |
|   rust   | actix-raw |  micro   |                 |   4180781 |  138896 |   26668104 |  0.04 |  0.24 | 0.362 |  0.525 |   5.262 |  45.179 |
|  dlang   | adio-http | platform |   epoll (PF)    |   4078214 |  135488 |   26013856 | 0.038 | 0.259 | 0.362 |  0.502 |   15.33 | 110.521 |
|  dlang   | adio-http | platform |  io_uring (PF)  |   3822145 |  126981 |   24380459 | 0.026 | 0.234 | 0.336 |  0.587 |   9.031 |  50.017 |
|    c     |   nginx   | platform |                 |   3669448 |  121908 |   23406445 | 0.033 | 0.272 | 0.396 |   0.59 |   9.888 |  59.079 |
|  dlang   |   hunt    |  micro   |    hunt-pico    |   3303837 |  109762 |   21074309 | 0.034 | 0.272 | 0.353 |  0.691 |   13.99 |  49.033 |
|   rust   | actix-web | platform |                 |   3266842 |  108532 |   20838327 |  0.04 | 0.297 | 0.409 |   0.71 |   6.212 |  53.315 |
|  golang  | fasthttp  | platform |                 |   3048964 |  101294 |   19448541 | 0.029 | 0.304 | 0.483 |  0.721 |   7.971 |  31.411 |
|  dlang   |  photon   |  micro   |                 |   2662812 |   88465 |   16985378 | 0.028 | 0.193 | 0.275 |  0.348 |     1.6 |  23.149 |
|  dotnet  |  aspcore  | platform |                 |   2544305 |   84528 |   16229453 | 0.038 | 0.349 | 0.442 |   0.99 |   8.476 |  37.221 |
|  dlang   |   arsd    | platform |    processes    |   1668625 |   55472 |   10650797 |  0.04 | 0.086 |  0.11 |  0.148 |   0.626 |   13.35 |
|  dlang   |   arsd    | platform |     hybrid      |   1607219 |   53431 |   10258844 | 0.041 | 0.142 |  0.52 |  2.786 |  12.385 |  46.233 |
|  dlang   |  vibe-d   | platform |     gc (PF)     |   1518905 |   50512 |    9698362 | 0.053 | 0.676 | 0.934 |   1.28 |   16.74 |  64.229 |
|  dlang   |  vibe-d   | platform |   manual (PF)   |   1413129 |   46947 |    9013979 | 0.051 | 0.677 | 0.927 |   1.58 |  22.917 |  79.474 |
|  dlang   |  archttp  | platform |     archttp     |   1334548 |   44337 |    8246708 | 0.004 | 0.259 | 7.914 | 26.388 |   43.98 |   58.49 |
|  dlang   |  vibe-d   | platform |     manual      |   1251646 |   41638 |    7994545 | 0.049 | 0.701 | 0.929 |  2.053 |  13.403 |  57.959 |
|  dlang   |   arsd    | platform |     threads     |   1154682 |   38387 |    7370310 | 0.035 | 0.059 | 0.069 |  0.106 |   2.348 |  15.503 |
|  dlang   |  vibe-d   | platform |       gc        |   1101973 |   36622 |    7031532 | 0.048 | 0.691 |     1 |  2.175 |  11.004 |  62.349 |
|  dlang   |   hunt    | platform |    hunt-http    |    817674 |   27174 |    5217461 |  0.07 | 0.272 | 0.494 | 20.326 |  43.978 |  59.791 |
|  dlang   | serverino | platform |    serverino    |    748038 |   24909 |    4782660 |  0.05 | 0.067 | 0.073 |  0.085 | 3248.52 | 8525.24 |

##### 128 concurrent clients

| Language | Framework | Category |      Name       |    Req    |   RPS   |    BPS     |  min  |  25%  |   50%  |  75%   |   99%   |   max   |
|:--------:|:---------:|:--------:|:---------------:| ---------:| -------:| ----------:| -----:| -----:| ------:| ------:| -------:| -------:|
|  dlang   |   epoll   |  micro   | raw - edge (PF) |   5181932 |  172157 |   33054184 |  0.04 | 0.466 |   0.54 |  0.763 |  22.466 |  83.744 |
|    c     |   epoll   |  micro   | raw - lvl (PF)  |   5087026 |  169172 |   32481176 | 0.037 | 0.456 |  0.533 |   0.86 |  22.961 |  84.079 |
|  dlang   |   epoll   |  micro   | raw - lvl (PF)  |   5025548 |  167183 |   32099308 | 0.038 | 0.462 |  0.536 |    0.9 |  22.783 |   76.59 |
|    c     |   epoll   |  micro   | raw - edge (PF) |   5000030 |  166113 |   31893879 | 0.036 | 0.463 |   0.54 |  0.873 |  23.505 |  87.754 |
|  dlang   |  during   |  micro   |    raw (PF)     |   4630246 |  153828 |   29535123 | 0.039 | 0.482 |  0.577 |  1.145 |  26.209 |  98.119 |
|    c     | io_uring  |  micro   |    raw (PF)     |   4494922 |  149332 |   28671927 | 0.046 | 0.501 |  0.593 |  1.217 |  25.322 | 100.134 |
|  dlang   |   mecca   |  micro   |     prefork     |   4406112 |  146577 |   28142831 | 0.036 | 0.486 |  0.592 |  1.412 |  24.194 | 204.726 |
|  dlang   | eventcore |  micro   |   fibers (PF)   |   4325482 |  143894 |   27627829 | 0.029 | 0.501 |  0.581 |  1.657 |  26.138 |  92.108 |
|  dlang   | eventcore |  micro   |     cb (PF)     |   4262059 |  141596 |   27186555 | 0.035 | 0.493 |  0.584 |  1.769 |  27.091 |  92.737 |
|   rust   | actix-raw |  micro   |                 |   4174137 |  138860 |   26661154 | 0.058 | 0.514 |  0.603 |   1.73 |  26.564 |  72.259 |
|  dlang   | vibe-core |  micro   |     prefork     |   4050549 |  134569 |   25837388 | 0.032 | 0.519 |  0.612 |  1.899 |  28.349 | 106.099 |
|  dlang   | adio-http | platform |  io_uring (PF)  |   4017403 |  133468 |   25625959 | 0.047 | 0.526 |  0.682 |  1.549 |  21.752 |  54.814 |
|  dlang   | adio-http | platform |   epoll (PF)    |   3962503 |  131644 |   25275766 | 0.033 |  0.53 |  0.622 |  1.805 |  26.394 |   98.63 |
|    c     |   nginx   | platform |                 |   3631606 |  120651 |   23165061 | 0.064 | 0.586 |   0.74 |   1.52 |  23.449 |  81.123 |
|  golang  | fasthttp  | platform |                 |   3356420 |  111508 |   21409722 | 0.032 |  0.62 |  1.007 |   1.53 |  10.761 |   51.55 |
|  dlang   |  photon   |  micro   |                 |   3335577 |  110816 |   21276770 | 0.037 | 0.423 |  0.507 |  1.452 |  16.209 |  71.317 |
|   rust   | actix-web | platform |                 |   3237717 |  107565 |   20652546 | 0.049 | 0.632 |  0.737 |  2.205 |  24.903 |  92.319 |
|  dlang   |   hunt    |  micro   |    hunt-pico    |   2949294 |   97983 |   18812772 |  0.03 | 0.573 |  0.749 |  2.578 |  22.754 |  58.408 |
|  dlang   |  photon   |  micro   |                 |   2912797 |   96770 |   18579967 | 0.037 | 0.332 |  0.402 |  2.173 |  14.608 |   40.74 |
|  dotnet  |  aspcore  | platform |                 |   2788658 |   92646 |   17788117 | 0.044 | 0.696 |  0.933 |  2.161 |  11.087 |  37.631 |
|  dlang   |   arsd    | platform |     hybrid      |   1934891 |   64324 |   12350368 | 0.043 | 0.415 |  0.984 |  7.105 |  21.206 |  44.325 |
|  dlang   |   arsd    | platform |    processes    |   1767143 |   58748 |   11279636 | 0.037 | 0.081 |  0.107 |  0.142 |   0.636 |    9.81 |
|  dlang   |  vibe-d   | platform |   manual (PF)   |   1360672 |   45205 |    8679369 | 0.051 | 1.528 |  1.956 |  4.972 |  43.729 | 117.347 |
|  dlang   |  archttp  | platform |     archttp     |   1352722 |   44955 |    8361791 | 0.004 | 1.112 | 11.657 |  29.11 |  47.145 |  66.374 |
|  dlang   |  vibe-d   | platform |     gc (PF)     |   1270120 |   42238 |    8109845 | 0.052 | 1.562 |  1.955 |  5.727 |  44.415 | 122.373 |
|  dlang   |  vibe-d   | platform |     manual      |   1249865 |   41551 |    7977861 | 0.048 | 1.537 |  2.066 |  5.026 |  28.457 |  77.898 |
|  dlang   |   arsd    | platform |     threads     |   1160647 |   38585 |    7408385 | 0.036 | 0.057 |  0.066 |  0.102 |    2.32 |  12.338 |
|  dlang   |  vibe-d   | platform |       gc        |   1127517 |   37483 |    7196917 | 0.047 | 1.583 |  2.752 |  4.798 |      17 | 142.647 |
|  dlang   | serverino | platform |    serverino    |    708773 |   23547 |    4521076 | 0.052 | 0.071 |  0.078 |  0.092 | 663.388 | 8533.12 |
|  dlang   |   hunt    | platform |    hunt-http    |    521653 |   17330 |    3327487 |  0.07 | 0.495 |    4.2 | 26.121 |  47.853 |  58.167 |

##### 256 concurrent clients

| Language | Framework | Category |      Name       |    Req    |   RPS   |    BPS     |  min  |  25%  |   50%  |  75%   |  99%   |   max   |
|:--------:|:---------:|:--------:|:---------------:| ---------:| -------:| ----------:| -----:| -----:| ------:| ------:| ------:| -------:|
|    c     | io_uring  |  micro   |    raw (PF)     |   6020245 |  200008 |   38401562 | 0.038 | 0.825 |   0.98 |  1.482 |   25.3 |  91.814 |
|  dlang   |  during   |  micro   |    raw (PF)     |   5380938 |  178768 |   34323591 | 0.047 | 0.871 |  1.049 |   1.78 | 26.085 |  90.423 |
|  dlang   | adio-http | platform |  io_uring (PF)  |   4458464 |  148121 |   28439371 | 0.056 | 0.922 |  1.149 |  2.567 | 23.092 | 219.752 |
|  dlang   |   epoll   |  micro   | raw - lvl (PF)  |   4436549 |  147540 |   28327815 | 0.037 | 0.842 |  1.026 |  3.619 | 24.056 |  56.881 |
|    c     |   epoll   |  micro   | raw - lvl (PF)  |   4413511 |  146774 |   28180715 | 0.029 | 0.845 |  1.022 |  3.688 | 24.689 |  60.231 |
|    c     |   epoll   |  micro   | raw - edge (PF) |   4122884 |  137018 |   26307534 | 0.037 | 0.853 |  1.087 |  4.164 | 24.313 |  82.133 |
|  dlang   |   mecca   |  micro   |     prefork     |   3895712 |  129554 |   24874516 | 0.036 | 0.953 |   1.19 |  4.114 | 28.676 | 820.867 |
|  dlang   |   epoll   |  micro   | raw - edge (PF) |   3891160 |  129274 |   24820688 | 0.043 | 0.907 |  1.083 |  4.409 | 25.027 |  53.744 |
|  dlang   | eventcore |  micro   |     cb (PF)     |   3848983 |  127958 |   24567976 | 0.039 | 0.945 |  1.177 |  4.196 | 25.572 |  84.256 |
|  dlang   |  photon   |  micro   |                 |   3614571 |  120085 |   23056399 | 0.033 | 0.486 |  0.946 |  1.538 | 24.079 |  54.822 |
|    c     |   nginx   | platform |                 |   3582858 |  119071 |   22861706 | 0.049 | 1.087 |  1.372 |  3.993 | 28.644 |  89.373 |
|  dlang   | eventcore |  micro   |   fibers (PF)   |   3572997 |  118862 |   22821537 | 0.032 | 0.982 |  1.281 |  4.563 | 25.315 |   52.96 |
|   rust   | actix-raw |  micro   |                 |   3399182 |  113042 |   21704121 | 0.036 |  1.06 |  1.339 |  4.876 | 26.848 |  65.659 |
|  dlang   | adio-http | platform |   epoll (PF)    |   3395124 |  112907 |   21678211 | 0.035 | 1.076 |   1.36 |  4.662 | 26.731 | 227.302 |
|  dlang   | vibe-core |  micro   |     prefork     |   3234003 |  107584 |   20656306 | 0.031 | 1.067 |  1.317 |  5.303 |   26.6 |   49.97 |
|  golang  | fasthttp  | platform |                 |   3194451 |  106198 |   20390112 | 0.035 | 1.361 |  2.048 |  3.168 | 22.541 |  91.642 |
|  dlang   |   hunt    |  micro   |    hunt-pico    |   3111286 |  103468 |   19865876 | 0.046 | 1.134 |  1.484 |  4.717 | 31.603 |  59.587 |
|   rust   | actix-web | platform |                 |   3096216 |  102864 |   19749949 | 0.051 | 1.275 |  1.642 |  4.322 | 28.249 |  73.176 |
|  dotnet  |  aspcore  | platform |                 |   2933409 |   97455 |   18711446 | 0.045 | 1.377 |  1.813 |  3.816 | 12.411 |  37.636 |
|  dlang   |   arsd    | platform |     hybrid      |   1845958 |   61368 |   11782710 | 0.045 | 0.761 |  2.658 | 10.372 | 28.823 |  72.761 |
|  dlang   |   arsd    | platform |    processes    |   1732722 |   57642 |   11067286 | 0.039 | 0.084 |  0.108 |  0.147 |  0.555 |  17.043 |
|  dlang   |  archttp  | platform |     archttp     |   1429702 |   47514 |    8837639 | 0.005 | 3.256 | 14.885 | 32.402 | 53.014 |  89.064 |
|  dlang   |  vibe-d   | platform |   manual (PF)   |   1373219 |   45621 |    8759403 |  0.05 | 3.014 |  4.097 |  9.611 | 72.909 | 186.366 |
|  dlang   |  vibe-d   | platform |     gc (PF)     |   1365141 |   45398 |    8716563 |  0.05 | 3.096 |  4.138 |  9.389 |  67.28 | 162.477 |
|  dlang   |  vibe-d   | platform |     manual      |   1234108 |   41054 |    7882526 |  0.05 | 3.251 |  4.473 |   9.52 | 44.077 | 279.181 |
|  dlang   |   arsd    | platform |     threads     |   1178227 |   39156 |    7518098 | 0.039 | 0.061 |  0.072 |  0.103 |  2.217 |   15.68 |
|  dlang   |  vibe-d   | platform |       gc        |   1036246 |   34461 |    6616535 | 0.048 | 4.078 |  5.662 | 10.838 | 28.719 | 262.348 |
|  dlang   |   hunt    | platform |    hunt-http    |    701284 |   23313 |    4476280 | 0.072 | 1.409 |  6.698 | 30.095 | 51.581 |  58.629 |
|  dlang   | serverino | platform |    serverino    |    671544 |   22310 |    4283602 | 0.052 | 0.071 |   0.09 |  0.096 |  0.194 | 8369.77 |

#### Special note

As `arsd` (excluding `arsd/hybrid`) and `serverino` doesn't use async IO, requests can be blocked for some time when keep-alive connections are used (on by default). With `wrk` it's not visible much, as it just bursts requests from any client that communicates and some of the clients doesn't receive any response.

To make it stand out more, here are some results with `hey` with number of clients equal to available CPU cores (so they should be completed without waiting in queue) and a multiple of that.

**Command:** `for i in 2 16; do _suite/runner.d bench --type multiCore -r tomas@192.168.122.176 --host 192.168.122.175 --tool hey -b 2 -c $i arsd serverino actix-web; done`

##### 2 concurrent clients

| Language | Framework | Category |   Name    |  Req  |  RPS   |    BPS    | min | 25% | 50% | 75% | 99% | max |
|:--------:|:---------:|:--------:|:---------:| -----:| ------:| ---------:| ---:| ---:| ---:| ---:| ---:| ---:|
|   rust   | actix-web | platform |           |  2000 |  20725 |   3979274 | 0.1 | 0.1 | 0.1 | 0.1 | 0.2 |   1 |
|  dlang   |   arsd    | platform |  hybrid   |  2000 |  19230 |   3692307 | 0.1 | 0.1 | 0.1 | 0.1 | 0.2 |   1 |
|  dlang   |   arsd    | platform | processes |  2000 |  18450 |   3542435 | 0.1 | 0.1 | 0.1 | 0.1 | 0.2 | 1.6 |
|  dlang   |   arsd    | platform |  threads  |  2000 |  17064 |   3276450 | 0.1 | 0.1 | 0.1 | 0.1 | 1.2 | 2.3 |
|  dlang   | serverino | platform | serverino |  2000 |  17064 |   3276450 | 0.1 | 0.1 | 0.1 | 0.1 | 0.2 | 1.2 |

##### 64 concurrent clients

| Language | Framework | Category |   Name    |  Req   |  RPS   |    BPS    | min | 25% | 50% | 75% | 99% |  max   |
|:--------:|:---------:|:--------:|:---------:| ------:| ------:| ---------:| ---:| ---:| ---:| ---:| ---:| ------:|
|   rust   | actix-web | platform |           |  16000 |  50046 |   9609008 | 0.1 | 0.1 | 0.2 | 0.2 | 1.9 |   14.8 |
|  dlang   |   arsd    | platform |  hybrid   |  16000 |  39741 |   7630402 | 0.1 | 0.1 | 0.2 | 0.4 | 2.4 |   11.4 |
|  dlang   |   arsd    | platform | processes |  16000 |   4395 |    843956 | 0.1 | 0.1 | 0.2 | 0.2 | 0.9 | 3426.1 |
|  dlang   |   arsd    | platform |  threads  |  16000 |   4361 |    837445 | 0.1 | 0.1 | 0.1 | 0.2 | 2.2 | 3397.8 |
|  dlang   | serverino | platform | serverino |  16000 |   1769 |    339830 | 0.1 | 0.1 | 0.1 | 0.1 | 0.3 | 8897.6 |

#### Pipelining

For an idea of how HTTP pipelining is handled in the frameworks, here are some results.

**Command:** `_suite/runner.d bench --type multiCore -r tomas@192.168.122.176 --host 192.168.122.175 --tool wrk -d 30 -c 256 --pipeline 10`

| Language | Framework | Category |      Name       |    Req     |    RPS    |     BPS     |  min  |  25%   |  50%   |  75%   |   99%   |   max   |
|:--------:|:---------:|:--------:|:---------------:| ----------:| ---------:| -----------:| -----:| ------:| ------:| ------:| -------:| -------:|
|    c     | io_uring  |  micro   |    raw (PF)     |   42478890 |   1411258 |   270961690 | 0.058 |  0.601 |  1.038 |  2.098 |  18.655 |   59.75 |
|  dlang   |  during   |  micro   |    raw (PF)     |   39747230 |   1320505 |   253537148 | 0.067 |  0.642 |  1.129 |  3.114 |  24.014 |  68.632 |
|  dlang   |   epoll   |  micro   | raw - edge (PF) |   31876580 |   1059726 |   203467531 | 0.048 |  0.806 |  1.732 |  6.264 |  23.387 |   74.44 |
|  dlang   |   epoll   |  micro   | raw - lvl (PF)  |   31426130 |   1044751 |   200592319 | 0.059 |  0.818 |  1.701 |  5.922 |  22.098 |  46.574 |
|    c     |   epoll   |  micro   | raw - edge (PF) |   28838930 |    959059 |   184139493 | 0.048 |  0.894 |  2.289 |  6.724 |  23.825 |  47.789 |
|    c     |   epoll   |  micro   | raw - lvl (PF)  |   28658020 |    952410 |   182862739 | 0.075 |  0.896 |  2.425 |  6.891 |  24.134 |   43.23 |
|  dlang   |   mecca   |  micro   |     prefork     |   26977040 |    896843 |   172193872 | 0.041 |  0.952 |  2.209 |  6.622 |  25.138 |   410.6 |
|   rust   | actix-raw |  micro   |                 |   22776040 |    757182 |   145378978 | 0.063 |  1.126 |  2.422 |   6.99 |      27 |   58.56 |
|  dotnet  |  aspcore  | platform |                 |   21917960 |    728655 |   139901872 |  0.05 |  1.175 |   2.11 |  4.912 |  15.288 |  42.091 |
|  dlang   | adio-http | platform |  io_uring (PF)  |   17610451 |    585843 |   112481922 | 0.215 |  1.459 |  2.572 |  5.308 |  20.281 | 211.663 |
|  golang  | fasthttp  | platform |                 |   15935240 |    529409 |   101646713 |  0.05 |  1.664 |   3.02 |  4.868 |  15.724 | 140.235 |
|  dlang   | adio-http | platform |   epoll (PF)    |   15911183 |    528962 |   101560742 | 0.052 |  1.643 |  2.941 |  8.672 |  62.067 | 248.466 |
|   rust   | actix-web | platform |                 |   14984600 |    498323 |    95678190 |  0.32 |   1.68 |  2.888 |  4.673 |  16.714 |   50.58 |
|  dlang   |   hunt    |  micro   |    hunt-pico    |   13112192 |    435910 |    83694842 | 0.116 |  1.964 |   3.56 |  6.511 |  45.965 | 132.972 |
|  dlang   | vibe-core |  micro   |     prefork     |   11680983 |    388072 |    74509924 | 0.097 |  2.195 |  4.026 |  9.888 |  62.437 | 172.647 |
|  dlang   | eventcore |  micro   |     cb (PF)     |   11625312 |    386608 |    74228796 | 0.129 |  2.203 |  3.962 |  9.352 |  55.197 |  118.37 |
|  dlang   | eventcore |  micro   |   fibers (PF)   |   11230746 |    373362 |    71685612 | 0.159 |  2.297 |  4.125 | 10.026 |   61.39 |  156.31 |
|  dlang   |  photon   |  micro   |                 |    8370957 |    278289 |    53431640 |  0.08 |  3.285 | 13.496 | 32.919 | 107.108 | 230.898 |
|    c     |   nginx   | platform |                 |    6819182 |    226701 |    43526693 | 0.105 |  3.799 |  6.984 |   13.5 |  75.134 | 130.475 |
|  dlang   |  vibe-d   | platform |   manual (PF)   |    2770203 |     92033 |    17670397 | 0.132 |  9.536 | 17.101 | 47.864 | 166.154 | 252.396 |
|  dlang   |  vibe-d   | platform |     gc (PF)     |    2531734 |     84194 |    16165378 | 0.151 | 10.504 |  18.78 | 59.584 | 197.689 | 295.314 |
|  dlang   |  vibe-d   | platform |     manual      |    2272878 |     75561 |    14507731 | 0.164 | 11.722 | 20.976 | 58.485 | 196.827 | 598.729 |
|  dlang   |  vibe-d   | platform |       gc        |    1455146 |     48359 |     9285079 | 0.198 | 18.301 | 34.178 | 70.187 | 1547.63 | 4202.51 |
|  dlang   |   hunt    | platform |    hunt-http    |    1234219 |     41003 |     7872759 | 1.295 | 20.799 |  35.58 | 49.919 |  95.648 | 114.907 |

**Note:** `arsd` and `serverino` have problems with this and doesn't finish
