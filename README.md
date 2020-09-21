# http bench

Simple framework to test HTTP servers, inspired by [Simple Web Benchmark](https://github.com/nuald/simple-web-benchmark) but focused on [dlang](https://dlang.org) frameworks and libraries.

It measures achievable RPS (requests per second) in a simple plaintext response test scenario.

Tests were gathered or modified from various places (including [TechEmpower](https://github.com/TechEmpower/FrameworkBenchmarks)).

It uses [docker](https://www.docker.com) container to build and host services on and can run locally or use load tester from remote host.

Tests can be run without docker too, one just needs to have installed tested language compilers and hey workload generator (but this has been tested on linux only).

[hey](https://github.com/rakyll/hey) is used as a load generator and requests statistics collector.

## Tests

Tests are divided to two types:

* **singleCore** - services are started in single core mode to measure performance without multiple threads / processes (default)
* **multiCore**  - services are started to use all hosts CPU cores

## Usage

### Build execution container

```
make build
```

### Enter container

```
make shell
```

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

#### dlang

##### [arsd-official](https://code.dlang.org/packages/arsd-official)

I've wanted to add this popular library in the mix just for comparison.

##### [during](https://code.dlang.org/packages/during)

**TBD** - Using new asynchronous I/O [io_uring](https://lwn.net/Articles/776703/) it would be interesting to compare against mostly used epoll on Linux systems.

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

**TBD** - this one should probably come out at the top.

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

* **Load generator:** AMD Ryzen 7 3700X 8-Core, kernel 5.7.15
* **Load generator params:** `hey -n 640000 -c 64 -t 10`
* **Test runner:** Intel(R) Core(TM) i5-5300U CPU @ 2.30GHz, kernel 5.8.9
* **Network:** 1Gbps through cheap gigabit switch

##### 8 concurrent workers

| Language | Framework | Category |   Name    | Res[B] |  Req   | Err |  RPS  |   BPS   | med | min | max  | 25% | 75% | 99%  |
|:--------:|:---------:|:--------:|:---------:| ------:| ------:| ---:| -----:| -------:| ---:| ---:| ----:| ---:| ---:| ----:|
|  dlang   |   hunt    |  micro   | hunt-pico |    162 | 640000 |   0 | 43417 | 7033682 | 0.2 | 0.1 |  2.5 | 0.2 | 0.2 |  0.3 |
|  dlang   | eventcore |  micro   |    cb     |    162 | 640000 |   0 | 43150 | 6990432 | 0.2 | 0.1 |  4.6 | 0.2 | 0.2 |  0.3 |
|  dlang   | eventcore |  micro   |  fibers   |    162 | 640000 |   0 | 42899 | 6949713 | 0.2 | 0.1 |  2.9 | 0.2 | 0.2 |  0.3 |
|  dlang   | vibe-core |  micro   |           |    162 | 640000 |   0 | 42794 | 6932659 | 0.2 | 0.1 |  3.6 | 0.2 | 0.2 |  0.3 |
|  golang  | fasthttp  | platform |           |    162 | 640000 |   0 | 42752 | 6925851 | 0.2 | 0.1 |  2.8 | 0.2 | 0.2 |  0.3 |
|   rust   | actix-raw | platform |           |    162 | 640000 |   0 | 42442 | 6875741 | 0.2 | 0.1 |  1.5 | 0.2 | 0.2 |  0.3 |
|   rust   | actix-web | platform |           |    162 | 640000 |   0 | 41624 | 6743107 | 0.2 | 0.1 |  5.9 | 0.2 | 0.2 |  0.3 |
|  dlang   |  photon   |  micro   |           |    162 | 640000 |   0 | 40126 | 6500558 | 0.2 | 0.1 | 15.8 | 0.2 | 0.2 |  0.3 |
|  dotnet  |  aspcore  | platform |           |    162 | 640000 |   0 | 39283 | 6363859 | 0.2 | 0.1 | 11.5 | 0.2 | 0.2 |  0.3 |
|  dlang   |  vibe-d   | platform |  manual   |    162 | 640000 |   0 | 29299 | 4746535 | 0.3 | 0.1 |  1.5 | 0.2 | 0.3 |  0.5 |
|  dlang   |   arsd    | platform | processes |    192 | 640000 |   0 | 29295 | 5624802 | 0.3 | 0.1 |  8.4 | 0.2 | 0.3 |  0.5 |
|  dlang   |   arsd    | platform |  threads  |    192 | 640000 |   0 | 28587 | 5488777 | 0.3 | 0.1 | 11.1 | 0.2 | 0.3 |  0.5 |
|  dlang   |  vibe-d   | platform |    gc     |    162 | 640000 |   0 | 27324 | 4426531 | 0.3 | 0.1 |  2.5 | 0.3 | 0.3 |  0.5 |
|  dlang   |  lighttp  | platform |           |    162 | 640000 |   0 | 14037 | 2274148 | 0.5 | 0.1 |  9.4 | 0.4 | 0.6 |  1.9 |
|  dlang   |   hunt    | platform | hunt-http |    162 | 640000 |   0 |  1471 |  238381 | 0.3 | 0.2 | 45.1 | 0.3 | 0.3 | 42.1 |

##### 64 concurrent workers

| Language | Framework | Category |   Name    | Res[B] |  Req   | Err |  RPS   |   BPS    | med | min |  max   | 25% | 75% | 99%  |
|:--------:|:---------:|:--------:|:---------:| ------:| ------:| ---:| ------:| --------:| ---:| ---:| ------:| ---:| ---:| ----:|
|  dlang   | eventcore |  micro   |    cb     |    162 | 640000 |   0 | 166359 | 26950170 | 0.4 | 0.1 |   11.4 | 0.3 | 0.4 |    1 |
|  dlang   |   hunt    |  micro   | hunt-pico |    162 | 640000 |   0 | 158474 | 25672898 | 0.3 | 0.1 |   16.9 | 0.3 | 0.4 |  1.4 |
|  dlang   |  photon   |  micro   |           |    162 | 640000 |   0 | 143933 | 23317215 | 0.3 | 0.1 |   17.8 | 0.2 | 0.3 |  3.8 |
|  dlang   | eventcore |  micro   |  fibers   |    162 | 640000 |   0 | 120793 | 19568540 | 0.5 | 0.1 |   18.5 | 0.5 | 0.5 |    1 |
|  dlang   | vibe-core |  micro   |           |    162 | 640000 |   0 | 100065 | 16210638 | 0.6 | 0.1 |   12.3 | 0.4 | 0.7 |  2.5 |
|   rust   | actix-raw | platform |           |    162 | 640000 |   0 |  95107 | 15407477 | 0.6 | 0.1 |   18.6 | 0.5 | 0.7 |  1.6 |
|  golang  | fasthttp  | platform |           |    162 | 640000 |   0 |  86754 | 14054303 | 0.7 | 0.1 |   14.4 | 0.4 |   1 |  1.5 |
|   rust   | actix-web | platform |           |    162 | 640000 |   0 |  84898 | 13753581 | 0.7 | 0.1 |   17.7 | 0.7 | 0.7 |  1.3 |
|  dotnet  |  aspcore  | platform |           |    162 | 640000 |   0 |  79620 | 12898570 | 0.6 | 0.1 |   34.6 | 0.5 | 1.1 |  1.6 |
|  dlang   |  vibe-d   | platform |    gc     |    162 | 640000 |   0 |  41535 |  6728753 | 1.4 | 0.2 |   20.1 | 1.4 | 1.6 |  2.4 |
|  dlang   |  vibe-d   | platform |  manual   |    162 | 640000 |   0 |  34603 |  5605809 | 1.8 | 0.2 |   38.4 | 1.4 |   2 |  4.8 |
|  dlang   |  lighttp  | platform |           |    162 | 640000 |   0 |  20699 |  3353288 | 2.8 | 0.2 |  208.8 | 2.2 | 3.6 |  7.9 |
|  dlang   |   arsd    | platform |  threads  |    192 | 639904 |   0 |  15634 |  3001821 | 0.3 | 0.1 | 8797.6 | 0.2 | 0.3 |  0.5 |
|  dlang   |   arsd    | platform | processes |    192 | 639903 |   0 |  15193 |  2917227 | 0.3 | 0.1 | 5865.8 | 0.2 | 0.3 |  0.5 |
|  dlang   |   hunt    | platform | hunt-http |    162 | 640000 |   0 |   7936 |  1285719 | 0.4 | 0.2 |   54.4 | 0.3 | 1.2 | 43.1 |

##### 256 concurrent workers

| Language | Framework | Category |   Name    | Res[B] |  Req   | Err |  RPS   |   BPS    | med | min |  max   | 25% | 75%  |  99%  |
|:--------:|:---------:|:--------:|:---------:| ------:| ------:| ---:| ------:| --------:| ---:| ---:| ------:| ---:| ----:| -----:|
|  dlang   |  photon   |  micro   |           |    162 | 640000 |   0 | 138588 | 22451277 | 1.2 | 0.1 |   45.4 |   1 |  1.8 |   9.9 |
|  dlang   | eventcore |  micro   |  fibers   |    162 | 640000 |   0 | 117595 | 19050418 | 2.2 | 0.1 |   32.7 | 1.7 |  2.3 |   5.3 |
|  dlang   | eventcore |  micro   |    cb     |    162 | 640000 |   0 | 111938 | 18134116 | 1.9 | 0.1 |   39.1 | 1.6 |  2.7 |   7.3 |
|  dlang   |   hunt    |  micro   | hunt-pico |    162 | 640000 |   0 | 105760 | 17133225 | 2.4 | 0.1 |   42.7 | 1.9 |  2.7 |   6.8 |
|  dlang   | vibe-core |  micro   |           |    162 | 640000 |   0 |  96075 | 15564295 | 2.6 | 0.1 |   41.9 | 2.5 |  2.7 |   4.3 |
|   rust   | actix-raw | platform |           |    162 | 640000 |   0 |  85098 | 13785950 | 2.7 | 0.1 |   38.6 | 2.4 |  3.1 |   7.8 |
|  golang  | fasthttp  | platform |           |    162 | 640000 |   0 |  82749 | 13405394 |   3 | 0.1 |   40.1 | 2.2 |  3.7 |   6.9 |
|   rust   | actix-web | platform |           |    162 | 640000 |   0 |  69662 | 11285266 | 3.1 | 0.1 |   50.2 | 2.9 |  3.6 |  10.5 |
|  dotnet  |  aspcore  | platform |           |    162 | 640000 |   0 |  43983 |  7125283 | 5.7 | 0.1 |   54.8 | 4.5 |  6.4 |  13.8 |
|  dlang   |  vibe-d   | platform |    gc     |    162 | 640000 |   0 |  36516 |  5915681 | 6.2 | 0.1 |  454.3 |   6 |  6.7 |    14 |
|  dlang   |  vibe-d   | platform |  manual   |    162 | 640000 |   0 |  32780 |  5310414 | 6.8 | 0.2 |  290.2 | 6.5 |  8.1 |  16.6 |
|  dlang   |  lighttp  | platform |           |    162 | 147206 |   0 |  14837 |  2403726 | 8.1 | 0.1 |  837.5 | 5.5 | 11.5 | 216.9 |
|  dlang   |   hunt    | platform | hunt-http |    162 | 640000 |   0 |  14614 |  2367620 | 5.3 | 0.2 |  104.5 | 1.6 | 41.9 |  61.6 |
|  dlang   |   arsd    | platform |  threads  |    192 |  58710 |   0 |   5017 |   963314 | 0.3 | 0.1 | 8066.6 | 0.3 |  0.6 |  15.7 |
|  dlang   |   arsd    | platform | processes |    192 |  87074 |   0 |   1435 |   275542 | 0.3 | 0.1 | 9969.6 | 0.2 |  0.3 |  12.5 |

### Language versions

| Language | Version               |
| -------- | --------------------- |
| go       | go1.15.1              |
| ldc2     | 1.23.0                |
| rust     | 1.48.0-nightly        |
| dotnet   | 5.0.100-rc.1.20452.10 |
