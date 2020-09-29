# http bench

Simple framework to test HTTP servers, inspired by [Simple Web Benchmark](https://github.com/nuald/simple-web-benchmark) but focused on [dlang](https://dlang.org) frameworks and libraries.

It measures achievable RPS (requests per second) in a simple plaintext response test scenario.

Tests were gathered or modified from various places (including [TechEmpower](https://github.com/TechEmpower/FrameworkBenchmarks)).

It uses [docker](https://www.docker.com) container to build and host services on and can run locally or use load tester from remote host.

[wrk](https://github.com/wg/wrk) is used as a default load generator and requests statistics collector, but [hey](https://github.com/rakyll/hey) is supported too (just use `--tool` switch).

Tests can be run without docker too, one just needs to have installed tested language compilers and [wrk](https://github.com/wg/wrk)/[hey](https://github.com/rakyll/hey) workload generator (but this has been tested on linux only).

**Note for io_uring tests:** - At least Linux kernel 5.7 is needed for tests to work.
Problems with user limits on locked memory (`ulimit -l`) are possible too when run with regular user.

## Tests

Tests are divided to two types:

* **singleCore** - services are started in single core mode to measure performance without multiple threads / processes (default)
* **multiCore**  - services are started to use all hosts CPU cores

## Usage

### Build execution container

* `make build` - build execution container
* `make shell` - enter container

**Note:** Performance governor is set to `performance` with this command.

### Test runner

For a no brainer tests, just run one of (in the container shell):

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

Use `_suite/runner.d bench -h` to print out CLI interface help.

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

Host that generates load should be ideally more prefermant.

### Frameworks / libraries

Some of the top of the [Techempower](https://www.techempower.com/benchmarks/#section=data-r19&hw=ph&test=plaintext) frameworks were added as a reference point.

Many of the tests there are using various tweaks unusable in a real life scenarios.

* no router (ie only match on path length, etc.)
* no HTTP request parser
* prebuilt static text for response
* etc.

I've tried at least make response sizes to be of the same size for all the tests to be more fair and would like to make more adjustments in this regards.

#### C

These are added to determine the potential of the test environment configuration. They don't try to work as a generic HTTP servers, but just utilize the eventloop at the top speed.

Epoll and io_uring are added. Both named as `raw`.

#### dlang

##### [arsd-official](https://code.dlang.org/packages/arsd-official)

I've wanted to add this popular library in the mix just for comparison. Currently three configurations of internal http servers are used:

* process - forked process, each serving one request
* threads - threadpool to handle connected clients
* hybrid - an experimental Linux-only hybrid implementation of forked processes, worker threads, and fibers in an event loop

They are added to a `singeCore` type tests as they don't use (at the moment) some eventloop so we can compare this traditional way against the others in that category.

See Adam's [description](http://dpldocs.info/this-week-in-d/Blog.Posted_2020_09_21.html#on-cgi.d-performance) for more.

##### [during](https://code.dlang.org/packages/during)

* **raw** - test that tries to be as fast as possible to make a theoretical limit of the used system facility (so no parsers, routers, ... - just plain event loop)

**TBD** - Using new asynchronous I/O [io_uring](https://lwn.net/Articles/776703/) it would be interesting to compare against mostly used epoll on Linux systems.

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

##### [mecca](https://code.dlang.org/packages/mecca)

**TBD**

##### [photon](https://github.com/DmitryOlshansky/photon)

It's not on [code.dlang.org](https://code.dlang.org/) but is an interesting library that rewrites glibc syscalls and emulates them via epoll eventloop and fibers underneath.

Test uses nodejs [http-parser](https://github.com/nodejs/http-parser) (not that fast as pico) and doesn't use router.

##### [vibe-core](https://github.com/vibe-d/vibe-core)

Higher level library that uses [eventcore](https://github.com/vibe-d/eventcore) and adds fiber backed tasks framework to handle event callbacks.

Still a microbenchmark as it only uses `TCPConnection` and reads request line by line and then just writes static response text.

No router or http parser used.

##### [vibe-d](https://github.com/vibe-d/vibe.d)

Finally most popular [dlang](https://dlang.org) web framework that has it all.

#### dotnet

[ASP.Net Core](https://docs.microsoft.com/en-us/aspnet/core/?view=aspnetcore-3.1) is used as a reference.

It has multiple tweaks mentioned above (simplistic router, prepared plaintext responses, ...).

#### golang

[fasthttp](https://github.com/valyala/fasthttp) is used as a reference.

Test uses HTTP parser, but no router.

#### rust

[Actix](https://actix.rs/) is used for comparison in two variants:

* actix-web - simple generic usage of the library
* actix-raw - more tweaked version with less generically used features

### Results

Currently test runner outputs results in a Markdown formatted table.

Column description:

* Res[B] - size of the sample response in bytes - to check responses are of the same size ideally
* Req - total number of requests load generator generated
* Err - number of responses with other than 200 OK results
* RPS - requests per second
* BPS - bytes per second
* min - minimal request time in [ms]
* max - maximal request time in [ms]
* 25% - 25% of requests has been completed within this time in [ms]
* 50% - 50% of requests has been completed within this time in [ms] (median)
* 75% - 75% of requests has been completed within this time in [ms]
* 90% - 90% of requests has been completed within this time in [ms]
* 99% - 99% of requests has been completed within this time in [ms]

#### Single core results

* **Load generator:** AMD Ryzen 7 3700X 8-Core, kernel 5.8.10
* **Test runner:** Intel(R) Core(TM) i5-5300U CPU @ 2.30GHz, kernel 5.8.9
* **Network:** 1Gbps through cheap gigabit switch
* **Test command:** `for i in 8 64 128 256; do _suite/runner.d bench --type singleCore --tool wrk -b 2 -d 120 -c $i -r tomas@10.0.0.2; done`

##### 8 concurrent workers

| Language | Framework | Category |    Name    |   Req   |  RPS  |   BPS    |  max  |  50%  |  75%  |  90%  |  99%  |
|:--------:|:---------:|:--------:|:----------:| -------:| -----:| --------:| -----:| -----:| -----:| -----:| -----:|
|  dlang   | eventcore |  micro   |   fibers   | 6874277 | 57285 | 10998843 | 10.28 | 0.146 | 0.148 | 0.151 | 0.197 |
|  dlang   | vibe-core |  micro   |            | 6829518 | 56912 | 10927228 |  10.3 | 0.146 | 0.148 | 0.151 | 0.198 |
|  dlang   | eventcore |  micro   |     cb     | 6800094 | 56667 | 10880150 |  4.83 | 0.146 | 0.148 | 0.152 | 0.198 |
|    c     |   epoll   |  micro   | raw - lvl  | 6735851 | 56132 | 10777361 | 10.29 | 0.146 | 0.148 | 0.152 | 0.198 |
|  dlang   |   epoll   |  micro   | raw - lvl  | 6732239 | 56101 | 10771582 |  2.51 | 0.146 | 0.148 | 0.152 | 0.198 |
|    c     |   epoll   |  micro   | raw - edge | 6727160 | 56059 | 10763456 |  10.3 | 0.146 | 0.148 | 0.153 | 0.198 |
|  dlang   |   hunt    |  micro   | hunt-pico  | 6718195 | 55984 | 10749112 |  10.2 | 0.146 | 0.148 | 0.153 | 0.199 |
|  dlang   |   epoll   |  micro   | raw - edge | 6717905 | 55982 | 10748648 |  1.78 | 0.146 | 0.148 | 0.153 | 0.198 |
|   rust   | actix-raw | platform |            | 6712486 | 55937 | 10739977 | 10.27 | 0.146 | 0.148 | 0.187 | 0.201 |
|    c     |   nginx   | platform |            | 6600625 | 55005 | 10561000 | 10.39 | 0.146 |  0.15 | 0.191 | 0.203 |
|  golang  | fasthttp  | platform |            | 6505777 | 54214 | 10409243 | 10.37 | 0.146 | 0.152 | 0.194 | 0.237 |
|    c     | io_uring  |  micro   |    raw     | 6494674 | 54122 | 10391478 | 10.23 | 0.146 |  0.15 | 0.191 | 0.206 |
|  dlang   |  during   |  micro   |    raw     | 6396261 | 53302 | 10234017 |  10.3 | 0.147 | 0.151 | 0.194 | 0.211 |
|   rust   | actix-web | platform |            | 6337393 | 52811 | 10139828 |  1.05 | 0.147 | 0.153 | 0.194 | 0.232 |
|  dlang   |  photon   |  micro   |            | 6164186 | 51368 |  9862697 | 17.31 | 0.147 | 0.153 | 0.195 | 0.244 |
|  dlang   |   arsd    | platform | processes  | 5782460 | 48187 |  9251936 | 10.19 | 0.149 | 0.193 | 0.199 |  0.25 |
|  dotnet  |  aspcore  | platform |            | 5596922 | 46641 |  8955075 | 14.41 | 0.154 | 0.195 | 0.203 | 0.253 |
|  dlang   |  vibe-d   | platform |   manual   | 4370519 | 36420 |  6992830 |  10.4 | 0.203 | 0.245 | 0.283 | 0.338 |
|  dlang   |  vibe-d   | platform |     gc     | 4182554 | 34854 |  6692086 | 10.33 |  0.24 | 0.247 | 0.292 | 0.346 |
|  dlang   |   arsd    | platform |   hybrid   | 3872119 | 32267 |  6195390 | 13.29 | 0.191 | 0.345 |  1.13 |  2.45 |
|  dlang   |   arsd    | platform |  threads   | 3296390 | 27469 |  5274224 | 14.39 | 0.194 | 0.632 |  1.23 |  2.53 |
|  dlang   |  lighttp  | platform |            | 1917825 | 15981 |  3068520 | 10.36 | 0.336 | 0.395 |  0.49 |  1.68 |
|  dlang   |   hunt    | platform | hunt-http  |  176565 |  1471 |   282504 | 50.64 |  8.21 | 24.69 | 35.59 | 41.12 |

##### 64 concurrent workers

| Language | Framework | Category |    Name    |   Req    |  RPS   |   BPS    |  max  |  50%  |  75%  |  90%  |  99%  |
|:--------:|:---------:|:--------:|:----------:| --------:| ------:| --------:| -----:| -----:| -----:| -----:| -----:|
|    c     |   epoll   |  micro   | raw - lvl  | 28552752 | 237939 | 45684403 |  7.26 |  0.27 | 0.285 | 0.305 | 0.417 |
|  dlang   |   epoll   |  micro   | raw - edge | 25293053 | 210775 | 40468884 |   4.3 | 0.297 | 0.311 |  0.33 | 0.435 |
|    c     |   epoll   |  micro   | raw - edge | 25271750 | 210597 | 40434800 | 11.06 | 0.297 |  0.31 | 0.327 | 0.489 |
|  dlang   |   epoll   |  micro   | raw - lvl  | 24700045 | 205833 | 39520072 |  9.47 |  0.29 |  0.38 | 0.419 | 0.476 |
|    c     | io_uring  |  micro   |    raw     | 24567883 | 204732 | 39308612 |  5.41 | 0.313 | 0.347 | 0.388 | 0.471 |
|  dlang   |   hunt    |  micro   | hunt-pico  | 23967923 | 199732 | 38348676 | 10.08 | 0.306 | 0.328 | 0.392 | 0.441 |
|  dlang   | eventcore |  micro   |     cb     | 23374163 | 194784 | 37398660 | 11.08 | 0.329 |  0.34 | 0.348 | 0.385 |
|  dlang   |  during   |  micro   |    raw     | 22727826 | 189398 | 36364521 |  4.33 | 0.331 | 0.361 | 0.404 |  0.48 |
|  dlang   |  photon   |  micro   |            | 22596195 | 188301 | 36153912 | 25.22 | 0.261 | 0.338 |   2.2 |  6.72 |
|  dlang   | vibe-core |  micro   |            | 18862594 | 157188 | 30180150 | 10.33 | 0.386 |  0.45 | 0.494 | 0.541 |
|  dlang   | eventcore |  micro   |   fibers   | 18739975 | 156166 | 29983960 | 10.31 | 0.434 | 0.443 | 0.476 | 0.494 |
|   rust   | actix-raw | platform |            | 16476593 | 137304 | 26362548 |  1.86 | 0.459 | 0.485 | 0.491 | 0.538 |
|    c     |   nginx   | platform |            | 13883994 | 115699 | 22214390 |  5.12 | 0.504 | 0.636 | 0.652 | 0.692 |
|   rust   | actix-web | platform |            | 11971271 |  99760 | 19154033 |  8.14 | 0.634 | 0.638 | 0.676 |  0.93 |
|  golang  | fasthttp  | platform |            | 11711501 |  97595 | 18738401 | 11.42 | 0.639 |  0.88 |  1.12 |  1.32 |
|  dotnet  |  aspcore  | platform |            | 11157251 |  92977 | 17851601 | 18.73 | 0.492 |  1.04 |  1.09 |  1.23 |
|  dlang   |   arsd    | platform |   hybrid   | 10429963 |  86916 | 16687940 | 34.68 | 0.539 |  1.27 |   2.3 |  5.29 |
|  dlang   |   arsd    | platform | processes  |  5777772 |  48148 |  9244435 | 11.15 | 0.149 | 0.192 | 0.198 | 0.248 |
|  dlang   |  vibe-d   | platform |   manual   |  5731966 |  47766 |  9171145 | 19.27 |  1.33 |  1.37 |  1.38 |  1.47 |
|  dlang   |  vibe-d   | platform |     gc     |  5539901 |  46165 |  8863841 | 28.83 |  1.28 |  1.33 |  1.96 |  2.24 |
|  dlang   |   arsd    | platform |  threads   |  4553639 |  37946 |  7285822 | 19.94 | 0.193 | 0.243 |  1.25 |  3.33 |
|  dlang   |  lighttp  | platform |            |  3515501 |  29295 |  5624801 | 12.74 |  1.54 |  2.39 |  2.95 |  3.52 |
|  dlang   |   hunt    | platform | hunt-http  |  1199304 |   9994 |  1918886 | 50.56 |  8.83 | 27.99 | 34.83 | 41.73 |

##### 128 concurrent workers

| Language | Framework | Category |    Name    |   Req    |  RPS   |   BPS    |  max   |  50%  |  75%  |  90%  |  99%  |
|:--------:|:---------:|:--------:|:----------:| --------:| ------:| --------:| ------:| -----:| -----:| -----:| -----:|
|  dlang   |   epoll   |  micro   | raw - lvl  | 29392978 | 244941 | 47028764 |   9.32 | 0.429 | 0.715 | 0.824 |  0.87 |
|    c     |   epoll   |  micro   | raw - lvl  | 28633642 | 238613 | 45813827 |   9.74 | 0.433 | 0.695 | 0.828 |   1.1 |
|  dlang   |  during   |  micro   |    raw     | 25247862 | 210398 | 40396579 | 204.16 | 0.622 | 0.641 | 0.657 | 0.694 |
|  dlang   |   hunt    |  micro   | hunt-pico  | 24446578 | 203721 | 39114524 |  10.65 | 0.627 | 0.637 | 0.651 | 0.697 |
|    c     | io_uring  |  micro   |    raw     | 24347247 | 202893 | 38955595 | 209.29 | 0.628 | 0.645 |  0.66 | 0.694 |
|  dlang   |   epoll   |  micro   | raw - edge | 23650109 | 197084 | 37840174 |   10.7 | 0.606 | 0.742 | 0.784 |  0.83 |
|  dlang   |  photon   |  micro   |            | 22061613 | 183846 | 35298580 |  32.73 | 0.507 | 0.815 |  3.42 |  8.34 |
|    c     |   epoll   |  micro   | raw - edge | 21401578 | 178346 | 34242524 |  10.51 | 0.757 | 0.783 | 0.795 | 0.837 |
|  dlang   | eventcore |  micro   |   fibers   | 19044726 | 158706 | 30471561 |  12.56 |  0.88 |  0.92 |  0.93 |  0.98 |
|  dlang   | eventcore |  micro   |     cb     | 17899936 | 149166 | 28639897 |  10.89 |  0.86 |  0.88 |  0.88 |  0.93 |
|  dlang   | vibe-core |  micro   |            | 17602097 | 146684 | 28163355 |  23.91 | 0.795 |  1.02 |  1.03 |  1.09 |
|   rust   | actix-raw | platform |            | 15889481 | 132412 | 25423169 |   5.39 |  0.93 |  0.96 |  1.01 |  1.42 |
|    c     |   nginx   | platform |            | 15532312 | 129435 | 24851699 |  17.87 |  0.98 |  0.99 |  1.02 |  1.06 |
|  golang  | fasthttp  | platform |            | 10904059 |  90867 | 17446494 |   4.56 |  1.41 |  1.97 |  2.45 |  2.94 |
|   rust   | actix-web | platform |            | 10472685 |  87272 | 16756296 |   5.44 |  1.47 |  1.47 |  1.51 |  1.57 |
|  dlang   |   arsd    | platform |   hybrid   | 10197414 |  84978 | 16315862 |  40.04 |  1.23 |  2.47 |  4.12 |  8.62 |
|  dotnet  |  aspcore  | platform |            |  9876943 |  82307 | 15803108 |  26.61 |  1.08 |  2.26 |  2.31 |   2.6 |
|  dlang   |   arsd    | platform | processes  |  5816844 |  48473 |  9306950 |  11.18 | 0.148 |  0.19 | 0.198 | 0.247 |
|  dlang   |  vibe-d   | platform |   manual   |  5522666 |  46022 |  8836265 | 146.15 |   2.7 |  2.74 |  2.79 |  4.16 |
|  dlang   |  vibe-d   | platform |     gc     |  5142867 |  42857 |  8228587 | 166.29 |  2.65 |  3.38 |  4.01 |  4.45 |
|  dlang   |   arsd    | platform |  threads   |  4532841 |  37773 |  7252545 |  21.79 | 0.192 | 0.241 |  1.24 |  3.32 |
|  dlang   |  lighttp  | platform |            |  3321200 |  27676 |  5313920 |  14.38 |  4.09 |  5.02 |  5.19 |  6.69 |
|  dlang   |   hunt    | platform | hunt-http  |  1686055 |  14050 |  2697688 |  52.55 | 13.48 | 31.63 | 40.96 | 42.81 |

##### 256 concurrent workers

| Language | Framework | Category |    Name    |   Req    |  RPS   |   BPS    |  max   |  50%  |  75%  |  90%  |  99%   |
|:--------:|:---------:|:--------:|:----------:| --------:| ------:| --------:| ------:| -----:| -----:| -----:| ------:|
|  dlang   |  during   |  micro   |    raw     | 29220616 | 243505 | 46752985 |  13.07 |  0.91 |  1.26 |  1.29 |   1.55 |
|  dlang   |   epoll   |  micro   | raw - lvl  | 26436387 | 220303 | 42298219 |  18.84 |  1.01 |   1.3 |  1.43 |   2.61 |
|    c     | io_uring  |  micro   |    raw     | 25560613 | 213005 | 40896980 |  10.04 |  1.28 |  1.31 |  1.33 |   1.41 |
|    c     |   epoll   |  micro   | raw - edge | 24893177 | 207443 | 39829083 |  14.09 |  1.23 |  1.24 |  1.25 |   1.41 |
|  dlang   |   epoll   |  micro   | raw - edge | 24798315 | 206652 | 39677304 |  20.77 |  1.22 |  1.24 |  1.27 |    1.6 |
|    c     |   epoll   |  micro   | raw - lvl  | 23270156 | 193917 | 37232249 |  24.27 |   1.4 |  1.43 |  1.46 |   1.53 |
|  dlang   |  photon   |  micro   |            | 20870987 | 173924 | 33393579 |  32.24 |  1.08 |  1.64 |  4.51 |    9.8 |
|  dlang   | eventcore |  micro   |     cb     | 20587845 | 171565 | 32940552 |  23.82 |  1.37 |  1.76 |  1.77 |   1.87 |
|  dlang   |   hunt    |  micro   | hunt-pico  | 19588958 | 163241 | 31342332 |   5.03 |  1.71 |  1.73 |  1.76 |   1.92 |
|  dlang   | vibe-core |  micro   |            | 18201463 | 151678 | 29122340 |  92.51 |  1.67 |  1.71 |  1.72 |   1.81 |
|  dlang   | eventcore |  micro   |   fibers   | 15880395 | 132336 | 25408632 |  28.41 |  1.92 |  1.96 |  1.96 |   2.14 |
|   rust   | actix-raw | platform |            | 15257309 | 127144 | 24411694 |  11.03 |  1.96 |  2.01 |   2.2 |   2.84 |
|    c     |   nginx   | platform |            | 11680636 |  97338 | 18689017 | 329.27 |  2.65 |  2.69 |  2.73 |   2.97 |
|   rust   | actix-web | platform |            | 11294924 |  94124 | 18071878 |   7.31 |   2.7 |  2.74 |  2.76 |   2.89 |
|  dlang   |   arsd    | platform |   hybrid   | 10356685 |  86305 | 16570696 |  48.24 |  2.64 |  4.61 |  7.05 |     13 |
|  golang  | fasthttp  | platform |            | 10077741 |  83981 | 16124385 |   9.75 |  3.03 |  3.81 |  4.31 |   4.66 |
|  dotnet  |  aspcore  | platform |            |  9826255 |  81885 | 15722008 |  29.21 |  2.26 |   4.7 |  4.76 |   5.45 |
|  dlang   |   arsd    | platform | processes  |  5837555 |  48646 |  9340088 |   8.11 | 0.148 |  0.19 | 0.198 |  0.247 |
|  dlang   |  vibe-d   | platform |   manual   |  5532453 |  46103 |  8851924 | 479.36 |  5.54 |  5.59 |  5.63 |   5.87 |
|  dlang   |   arsd    | platform |  threads   |  4556301 |  37969 |  7290081 |   22.9 | 0.192 | 0.241 |  1.24 |   3.31 |
|  dlang   |  vibe-d   | platform |     gc     |  4146302 |  34552 |  6634083 | 583.48 |  6.92 |  8.23 |  9.45 |  10.24 |
|  dlang   |  lighttp  | platform |            |  3406074 |  28383 |  5449718 | 426.46 |   5.3 |  6.44 |  7.26 | 179.83 |
|  dlang   |   hunt    | platform | hunt-http  |  2513634 |  20946 |  4021814 |  54.35 | 16.56 | 30.21 | 42.03 |  44.04 |

### Language versions

| Language | Version               |
| -------- | --------------------- |
| go       | go1.15.1              |
| ldc2     | 1.23.0                |
| rust     | 1.48.0-nightly        |
| dotnet   | 5.0.100-rc.1.20452.10 |
