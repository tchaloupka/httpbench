# http bench

Simple framework to test HTTP servers, inspired by [Simple Web Benchmark](https://github.com/nuald/simple-web-benchmark) but focused on [dlang](https://dlang.org) frameworks and libraries.

It measures achievable RPS (requests per second) in a simple plaintext response test scenario.

Tests were gathered or modified from various places (including [TechEmpower](https://github.com/TechEmpower/FrameworkBenchmarks)).

It uses [docker](https://www.docker.com) container to build and host services on and can run locally or use load tester from remote host.

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
_suite/runner.d bench -t singleCore dlang rust # runs all dlang and rust tests
```

#### Remote host testing

As localhost only benchmarking is discouraged (see ie https://www.mnot.net/blog/2011/05/18/http_benchmark_rules), CLI supports executing of load tester from the remote host.

Steps:

* on a host that would run servers, enter the container shell
* from that run something like `_suite/runner.d bench -t singleCore -r foo@192.168.0.3 --host 192.168.0.2 dlang`

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

* **Load generator:** AMD Ryzen 7 3700X 8-Core
* **Test runner:** Intel(R) Core(TM) i5-5300U CPU @ 2.30GHz
* **Network:** 1Gbps through cheap gigabit switch

| Language | Framework | Category |   Name    | Res[B] |  Req   | Err |  RPS   |   BPS    | med | min |  max   | 25% | 75%  |  99%  |
|:--------:|:---------:|:--------:|:---------:| ------:| ------:| ---:| ------:| --------:| ---:| ---:| ------:| ---:| ----:| -----:|
|  dlang   |  photon   |  micro   |           |    162 | 499968 |   0 | 150719 | 24416621 | 1.2 | 0.1 |   56.9 | 0.8 |  1.8 |     9 |
|  dlang   |   hunt    |  micro   | hunt-pico |    162 | 499968 |   0 | 136379 | 22093512 | 1.8 | 0.1 |   40.2 | 1.8 |  1.9 |   4.2 |
|  dlang   | eventcore |  micro   |    cb     |    162 | 499968 |   0 | 126737 | 20531525 | 1.9 | 0.1 |   52.6 | 1.5 |    2 |   8.2 |
|  dlang   | eventcore |  micro   |  fibers   |    162 | 499968 |   0 | 115996 | 18791428 | 2.1 | 0.1 |   42.5 | 2.1 |  2.2 |   5.9 |
|  dlang   | vibe-core |  micro   |           |    162 | 499968 |   0 | 104898 | 16993583 | 2.4 | 0.1 |   37.1 | 2.4 |  2.5 |   3.9 |
|  golang  | fasthttp  | platform |           |    162 | 499968 |   0 |  95183 | 15419653 | 2.6 | 0.1 |   55.7 |   2 |  3.3 |   5.1 |
|  dotnet  |  aspcore  | platform |           |    162 | 499968 |   0 |  92139 | 14926618 | 2.3 | 0.1 |   55.7 | 2.2 |  2.7 |   6.8 |
|   rust   | actix-web | platform |           |    162 | 499968 |   0 |  86932 | 14083115 | 2.9 | 0.1 |   55.2 | 2.9 |  2.9 |   4.3 |
|   rust   | actix-raw | platform |           |    162 | 499968 |   0 |  84858 | 13747040 | 2.9 | 0.1 |   58.7 | 2.9 |    3 |   5.3 |
|  dlang   |  vibe-d   | platform |    gc     |    162 | 499968 |   0 |  42917 |  6952643 | 5.8 | 0.2 |  478.3 | 5.8 |  5.9 |     8 |
|  dlang   |  vibe-d   | platform |  manual   |    162 | 499968 |   0 |  34374 |  5568720 | 7.4 | 0.2 |  592.2 | 7.4 |  7.5 |   8.4 |
|  dlang   |  lighttp  | platform |           |    162 | 219664 |   0 |  21876 |  3544061 | 6.1 | 0.1 | 1678.6 | 4.8 |  7.4 | 211.2 |
|  dlang   |   hunt    | platform | hunt-http |    162 | 499968 |   0 |  18226 |  2952749 | 2.5 | 0.2 |   60.9 | 0.9 | 41.1 |  48.2 |


### Language versions

| Language | Version               |
| -------- | --------------------- |
| go       | go1.15.1              |
| ldc2     | 1.23.0                |
| rust     | 1.48.0-nightly        |
| dotnet   | 5.0.100-rc.1.20452.10 |
