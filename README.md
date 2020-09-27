# http bench

Simple framework to test HTTP servers, inspired by [Simple Web Benchmark](https://github.com/nuald/simple-web-benchmark) but focused on [dlang](https://dlang.org) frameworks and libraries.

It measures achievable RPS (requests per second) in a simple plaintext response test scenario.

Tests were gathered or modified from various places (including [TechEmpower](https://github.com/TechEmpower/FrameworkBenchmarks)).

It uses [docker](https://www.docker.com) container to build and host services on and can run locally or use load tester from remote host.

[hey](https://github.com/rakyll/hey) is used as a load generator and requests statistics collector.

Tests can be run without docker too, one just needs to have installed tested language compilers and [hey](https://github.com/rakyll/hey) workload generator (but this has been tested on linux only).

For `io_uring` tests to work one currently has to run the tests on at least Linux kernel 5.7.
Problems with user limits on locked memory (`ulimit -l`) are the possible too when run with regular user.

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

* `_suite/runner.d versions` - prints out used language versions in Markdown table format
* `_suite/runner.d list` - list available benchmarks
* `_suite/runner.d bench` - runs benchmarks

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

I've wanted to add this popular library in the mix just for comparison. Currently two configurations of internal http servers are used:

* process - forked process, each serving one request
* threads - threadpool to handle connected clients

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
* med - median request time in [ms]
* min - minimal request time in [ms]
* max - maximal request time in [ms]
* 25% - 25% of requests has been completed within this time in [ms]
* 75% - 75% of requests has been completed within this time in [ms]
* 99% - 99% of requests has been completed within this time in [ms]

#### Single core results

* **Load generator:** AMD Ryzen 7 3700X 8-Core, kernel 5.8.10
* **Test runner:** Intel(R) Core(TM) i5-5300U CPU @ 2.30GHz, kernel 5.8.9
* **Network:** 1Gbps through cheap gigabit switch
* **Test command:** `for i in 8 64 128 256; do _suite/runner.d bench --type singleCore -b 10 -n 1000000 -c $i -r tomas@10.0.0.2; done`

##### 8 concurrent workers

| Language | Framework | Category |   Name    | Res[B] |   Req   | Err |  RPS  |   BPS   | med | min | max  | 25% | 75% | 99%  |
|:--------:|:---------:|:--------:|:---------:| ------:| -------:| ---:| -----:| -------:| ---:| ---:| ----:| ---:| ---:| ----:|
|  dlang   | eventcore |  micro   |    cb     |    162 | 1000000 |   0 | 45140 | 7312713 | 0.2 | 0.1 | 10.3 | 0.2 | 0.2 |  0.2 |
|    c     |   epoll   |  micro   |    raw    |    162 | 1000000 |   0 | 45089 | 7304536 | 0.2 | 0.1 |  1.2 | 0.2 | 0.2 |  0.2 |
|  dlang   |   epoll   |  micro   |    raw    |    162 | 1000000 |   0 | 44902 | 7274262 | 0.2 | 0.1 | 10.2 | 0.2 | 0.2 |  0.2 |
|  dlang   | eventcore |  micro   |  fibers   |    162 | 1000000 |   0 | 44746 | 7249003 | 0.2 | 0.1 | 10.3 | 0.2 | 0.2 |  0.2 |
|  dlang   |   hunt    |  micro   | hunt-pico |    162 | 1000000 |   0 | 44703 | 7241906 | 0.2 | 0.1 | 10.3 | 0.2 | 0.2 |  0.2 |
|  dlang   | vibe-core |  micro   |           |    162 | 1000000 |   0 | 44461 | 7202785 | 0.2 | 0.1 |  1.2 | 0.2 | 0.2 |  0.2 |
|    c     | io_uring  |  micro   |    raw    |    162 | 1000000 |   0 | 44311 | 7178528 | 0.2 | 0.1 | 10.2 | 0.2 | 0.2 |  0.3 |
|  dlang   |  during   |  micro   |    raw    |    162 | 1000000 |   0 | 44260 | 7170235 | 0.2 | 0.1 | 10.2 | 0.2 | 0.2 |  0.3 |
|   rust   | actix-raw | platform |           |    162 | 1000000 |   0 | 43772 | 7091143 | 0.2 | 0.1 | 10.4 | 0.2 | 0.2 |  0.3 |
|  golang  | fasthttp  | platform |           |    162 | 1000000 |   0 | 43396 | 7030243 | 0.2 | 0.1 | 10.4 | 0.2 | 0.2 |  0.3 |
|   rust   | actix-web | platform |           |    162 | 1000000 |   0 | 43172 | 6993882 | 0.2 | 0.1 | 10.4 | 0.2 | 0.2 |  0.3 |
|  dlang   |  photon   |  micro   |           |    162 | 1000000 |   0 | 41553 | 6731740 | 0.2 | 0.1 | 15.3 | 0.2 | 0.2 |  0.3 |
|  dotnet  |  aspcore  | platform |           |    162 | 1000000 |   0 | 40458 | 6554326 | 0.2 | 0.1 | 11.2 | 0.2 | 0.2 |  0.3 |
|  dlang   |  vibe-d   | platform |    gc     |    162 | 1000000 |   0 | 32706 | 5298394 | 0.2 | 0.1 |  4.4 | 0.2 | 0.3 |  0.4 |
|  dlang   |  vibe-d   | platform |  manual   |    162 | 1000000 |   0 | 32585 | 5278850 | 0.2 | 0.1 |  6.3 | 0.2 | 0.3 |  0.3 |
|  dlang   |   arsd    | platform | processes |    192 | 1000000 |   0 | 29525 | 5668900 | 0.3 | 0.1 |  8.8 | 0.2 | 0.3 |  0.4 |
|  dlang   |   arsd    | platform |  threads  |    192 | 1000000 |   0 | 18462 | 3544888 | 0.3 | 0.1 | 12.2 | 0.2 | 0.3 |  2.4 |
|  dlang   |  lighttp  | platform |           |    162 | 1000000 |   0 | 15922 | 2579506 | 0.5 | 0.1 | 10.8 | 0.3 | 0.6 |  1.9 |
|  dlang   |   hunt    | platform | hunt-http |    162 | 1000000 |   0 |  1493 |  241882 | 0.3 | 0.2 |   51 | 0.3 | 0.3 | 41.2 |

##### 64 concurrent workers

| Language | Framework | Category |   Name    | Res[B] |   Req   | Err |  RPS   |   BPS    | med | min | max  | 25% | 75% | 99%  |
|:--------:|:---------:|:--------:|:---------:| ------:| -------:| ---:| ------:| --------:| ---:| ---:| ----:| ---:| ---:| ----:|
|  dlang   |   epoll   |  micro   |    raw    |    162 | 1000000 |   0 | 201905 | 32708770 | 0.3 | 0.1 |   15 | 0.2 | 0.3 |  0.9 |
|  dlang   |  during   |  micro   |    raw    |    162 | 1000000 |   0 | 197448 | 31986731 | 0.2 | 0.1 | 13.7 | 0.2 | 0.4 |  1.1 |
|    c     |   epoll   |  micro   |    raw    |    162 | 1000000 |   0 | 195072 | 31601740 | 0.3 | 0.1 | 11.9 | 0.3 | 0.3 |  0.9 |
|  dlang   |   hunt    |  micro   | hunt-pico |    162 | 1000000 |   0 | 182142 | 29507121 | 0.3 | 0.1 | 14.3 | 0.3 | 0.4 |  0.9 |
|  dlang   | eventcore |  micro   |    cb     |    162 | 1000000 |   0 | 176850 | 28649747 | 0.3 | 0.1 | 11.7 | 0.3 | 0.4 |  0.6 |
|    c     | io_uring  |  micro   |    raw    |    162 | 1000000 |   0 | 172720 | 27980724 | 0.3 | 0.1 | 10.5 | 0.3 | 0.4 |  0.8 |
|  dlang   |  photon   |  micro   |           |    162 | 1000000 |   0 | 159583 | 25852576 | 0.3 | 0.1 | 20.7 | 0.2 | 0.3 |  3.4 |
|  dlang   | eventcore |  micro   |  fibers   |    162 | 1000000 |   0 | 159517 | 25841854 | 0.4 | 0.1 | 17.8 | 0.3 | 0.4 |  0.7 |
|  dlang   | vibe-core |  micro   |           |    162 | 1000000 |   0 | 155930 | 25260794 | 0.4 | 0.1 |   13 | 0.4 | 0.4 |  0.6 |
|   rust   | actix-raw | platform |           |    162 | 1000000 |   0 | 125786 | 20377358 | 0.5 | 0.1 | 15.2 | 0.5 | 0.5 |  0.6 |
|  golang  | fasthttp  | platform |           |    162 | 1000000 |   0 | 111566 | 18073700 | 0.6 | 0.1 |   14 | 0.4 | 0.8 |    1 |
|  dotnet  |  aspcore  | platform |           |    162 | 1000000 |   0 | 100321 | 16252006 | 0.5 | 0.1 | 17.7 | 0.5 | 0.6 |  1.3 |
|   rust   | actix-web | platform |           |    162 | 1000000 |   0 |  94467 | 15303808 | 0.7 | 0.1 | 12.6 | 0.7 | 0.7 |  0.8 |
|  dlang   |  vibe-d   | platform |  manual   |    162 | 1000000 |   0 |  46096 |  7467674 | 1.4 | 0.2 | 13.6 | 1.4 | 1.4 |  1.6 |
|  dlang   |  vibe-d   | platform |    gc     |    162 | 1000000 |   0 |  44191 |  7159018 | 1.4 | 0.2 | 14.1 | 1.3 | 1.4 |  2.3 |
|  dlang   |  lighttp  | platform |           |    162 | 1000000 |   0 |  24158 |  3913733 | 2.2 | 0.1 | 22.5 | 2.1 | 3.5 |  4.6 |
|  dlang   |   arsd    | platform |  threads  |    192 |  999862 |   0 |  20950 |  4022510 | 0.3 | 0.1 | 16.6 | 0.2 | 0.4 |  3.5 |
|  dlang   |   arsd    | platform | processes |    192 |  999865 |   0 |  18657 |  3582153 | 0.2 | 0.1 | 9668 | 0.2 | 0.3 |  0.4 |
|  dlang   |   hunt    | platform | hunt-http |    162 | 1000000 |   0 |  10033 |  1625487 | 0.3 | 0.2 | 51.3 | 0.3 | 0.4 | 41.9 |

##### 128 concurrent workers

| Language | Framework | Category |   Name    | Res[B] |  Req   | Err |  RPS   |   BPS    | med | min |  max   | 25% | 75% | 99%  |
|:--------:|:---------:|:--------:|:---------:| ------:| ------:| ---:| ------:| --------:| ---:| ---:| ------:| ---:| ---:| ----:|
|    c     |   epoll   |  micro   |    raw    |    162 | 999936 |   0 | 194862 | 31567695 | 0.3 | 0.1 |   23.3 | 0.2 | 0.9 |  3.2 |
|  dlang   |   hunt    |  micro   | hunt-pico |    162 | 999936 |   0 | 194782 | 31554782 | 0.6 | 0.1 |   30.9 | 0.5 | 0.7 |  2.1 |
|    c     | io_uring  |  micro   |    raw    |    162 | 999936 |   0 | 192247 | 31144066 | 0.2 | 0.1 |   22.1 | 0.2 |   1 |  3.4 |
|  dlang   |  during   |  micro   |    raw    |    162 | 999936 |   0 | 183471 | 29722322 | 0.7 | 0.1 |   22.1 | 0.6 | 0.7 |  1.7 |
|  dlang   | eventcore |  micro   |    cb     |    162 | 999936 |   0 | 179010 | 28999737 | 0.7 | 0.1 |   29.3 | 0.7 | 0.7 |  1.6 |
|  dlang   | eventcore |  micro   |  fibers   |    162 | 999936 |   0 | 170553 | 27629608 | 0.7 | 0.1 |   27.8 | 0.7 | 0.7 |  1.6 |
|  dlang   |   epoll   |  micro   |    raw    |    162 | 999936 |   0 | 161673 | 26191148 | 0.8 | 0.1 |   20.6 | 0.7 | 0.9 |  2.3 |
|  dlang   |  photon   |  micro   |           |    162 | 999936 |   0 | 160645 | 26024521 | 0.5 | 0.1 |   26.4 | 0.4 | 0.7 |  6.2 |
|  dlang   | vibe-core |  micro   |           |    162 | 999936 |   0 | 145297 | 23538162 | 0.8 | 0.1 |     42 | 0.8 | 0.9 |  1.6 |
|   rust   | actix-raw | platform |           |    162 | 999936 |   0 | 121392 | 19665618 |   1 | 0.1 |   24.2 |   1 | 1.1 |  1.6 |
|  golang  | fasthttp  | platform |           |    162 | 999936 |   0 | 106319 | 17223777 | 1.2 | 0.1 |     21 | 0.7 | 1.7 |  2.3 |
|  dotnet  |  aspcore  | platform |           |    162 | 999936 |   0 |  96540 | 15639536 | 1.1 | 0.1 |   28.8 | 1.1 | 1.1 |  2.7 |
|   rust   | actix-web | platform |           |    162 | 999936 |   0 |  92081 | 14917133 | 1.4 | 0.1 |   28.2 | 1.4 | 1.4 |  1.8 |
|  dlang   |  vibe-d   | platform |  manual   |    162 | 999936 |   0 |  46110 |  7469916 | 2.8 | 0.2 |   62.6 | 2.7 | 2.8 |  3.1 |
|  dlang   |  vibe-d   | platform |    gc     |    162 | 999936 |   0 |  37286 |  6040444 | 3.2 | 0.1 |   46.9 | 2.9 |   4 |  4.9 |
|  dlang   |  lighttp  | platform |           |    162 | 999936 |   0 |  23808 |  3856997 | 5.5 | 0.1 |  423.8 | 4.3 | 5.7 |    8 |
|  dlang   |   arsd    | platform |  threads  |    192 | 999612 |   0 |  16091 |  3089523 | 0.3 | 0.1 | 8075.8 | 0.2 | 0.4 |  3.5 |
|  dlang   |   hunt    | platform | hunt-http |    162 | 999936 |   0 |  14564 |  2359431 | 0.5 | 0.2 |   50.9 | 0.3 | 1.5 | 42.9 |
|  dlang   |   arsd    | platform | processes |    192 | 241308 |   0 |  11646 |  2236037 | 0.3 | 0.1 | 5131.7 | 0.2 | 0.3 |    3 |

##### 256 concurrent workers

| Language | Framework | Category |   Name    | Res[B] |  Req   | Err |  RPS   |   BPS    | med | min |  max   | 25% | 75%  | 99%  |
|:--------:|:---------:|:--------:|:---------:| ------:| ------:| ---:| ------:| --------:| ---:| ---:| ------:| ---:| ----:| ----:|
|  dlang   |  during   |  micro   |    raw    |    162 | 999936 |   0 | 166154 | 26917072 | 1.3 | 0.1 |   34.8 | 0.5 |  1.9 |  6.5 |
|    c     | io_uring  |  micro   |    raw    |    162 | 999936 |   0 | 165697 | 26843029 | 1.4 | 0.1 |     51 | 0.5 |  1.9 |  6.7 |
|  dlang   | eventcore |  micro   |    cb     |    162 | 999936 |   0 | 163463 | 26481009 | 1.4 | 0.1 |  208.1 | 0.3 |    2 |  7.1 |
|  dlang   |   epoll   |  micro   |    raw    |    162 | 999936 |   0 | 161189 | 26112619 | 0.3 | 0.1 |   42.4 | 0.2 |  2.2 |  7.9 |
|  dlang   |   hunt    |  micro   | hunt-pico |    162 | 999936 |   0 | 160282 | 25965702 | 0.5 | 0.1 |   36.4 | 0.2 |  2.2 |  7.7 |
|    c     |   epoll   |  micro   |    raw    |    162 | 999936 |   0 | 160112 | 25938261 | 0.3 | 0.1 |   42.7 | 0.2 |  2.2 |  7.9 |
|  dlang   | eventcore |  micro   |  fibers   |    162 | 999936 |   0 | 159103 | 25774826 | 1.6 | 0.1 |  209.5 | 1.5 |  1.6 |  5.3 |
|  dlang   |  photon   |  micro   |           |    162 | 999936 |   0 | 152832 | 24758835 | 1.2 | 0.1 |   40.2 | 0.9 |  1.7 |  8.9 |
|  dlang   | vibe-core |  micro   |           |    162 | 999936 |   0 | 140215 | 22714983 | 1.8 | 0.1 |   34.4 | 1.8 |  1.8 |  3.6 |
|   rust   | actix-raw | platform |           |    162 | 999936 |   0 | 111133 | 18003648 | 2.2 | 0.1 |   42.3 | 2.2 |  2.3 |  3.7 |
|  golang  | fasthttp  | platform |           |    162 | 999936 |   0 |  98285 | 15922234 | 2.6 | 0.1 |   34.8 | 1.9 |  3.2 |  4.1 |
|   rust   | actix-web | platform |           |    162 | 999936 |   0 |  90353 | 14637308 | 2.8 | 0.1 |   37.1 | 2.8 |  2.8 |  3.7 |
|  dotnet  |  aspcore  | platform |           |    162 | 999936 |   0 |  76466 | 12387653 | 2.4 | 0.1 |   36.7 | 2.3 |    5 |  5.8 |
|  dlang   |  vibe-d   | platform |    gc     |    162 | 999936 |   0 |  43275 |  7010565 | 5.8 | 0.2 |  320.9 | 5.8 |  5.9 |  7.5 |
|  dlang   |  vibe-d   | platform |  manual   |    162 | 999936 |   0 |  37755 |  6116393 | 6.2 | 0.2 |  381.5 | 6.1 |  7.7 |  8.2 |
|  dlang   |  lighttp  | platform |           |    162 | 300330 |   0 |  24345 |  3943926 | 5.6 | 0.1 | 1696.7 | 4.4 |  6.2 |  207 |
|  dlang   |   hunt    | platform | hunt-http |    162 | 999936 |   0 |  21088 |  3416277 | 1.3 | 0.2 |     81 | 0.6 | 40.9 | 43.9 |
|  dlang   |   arsd    | platform |  threads  |    192 | 134526 |   0 |  10543 |  2024390 | 0.3 | 0.1 | 5456.3 | 0.3 |  1.3 |  8.5 |
|  dlang   |   arsd    | platform | processes |    192 | 105172 |   0 |   9101 |  1747436 | 0.3 | 0.1 | 8244.7 | 0.2 |  0.4 |  5.6 |

### Language versions

| Language | Version               |
| -------- | --------------------- |
| go       | go1.15.1              |
| ldc2     | 1.23.0                |
| rust     | 1.48.0-nightly        |
| dotnet   | 5.0.100-rc.1.20452.10 |
