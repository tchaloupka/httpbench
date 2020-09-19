# http bench

Simple framework to test HTTP servers. Inspired by [Simple Web Benchmark](https://github.com/nuald/simple-web-benchmark) but focused on [dlang][https://dlang.org] frameworks and libraries.

It's measures achievable RPS (requests per second) in a simple plaintext response test scenario.

Tests were gathered or modified from various places (including [TechEmpower](https://github.com/TechEmpower/FrameworkBenchmarks)).

It uses docker container to build and host services on and can run locally or use load tester from remote host.

[hey](https://github.com/rakyll/hey) is used as load generator and requests statistics collector.

## Tests

Tests are divided to two types:

* **singleCore** - services are started in single core mode to measure performance without multiple threads / processes
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

I've wanted to add this popular library in the mix just for comparison, but test is currently disabled as it doesn't scale at all.
It doesn't use eventloop but just preforked processes or limited thread pool and is possible to use only with a limited number of concurrent clients with own server implementation.

Sorry @adamdruppe.

##### [eventcore](https://github.com/vibe-d/eventcore)

Library that is a basis for [vibe-d](https://github.com/vibe-d/vibe.d) framework. It generalizes event loop against epoll on linux (iocp and kqueue on windows and MacOS).

It's a microbenchmark as it has no proper http parser, router or response writer and currently only shows event loop potential of the library.

* callbacks - uses just callbacks to handle socket events
* fibers - uses fibers to emulate sync behavior on async events

##### [hunt](https://github.com/huntlabs/hunt-framework)

* hunt-http - idiomatic use of the framework (HTTP router, parser and all)
* hunt-pico - highly customized and optimized test that uses [picohttpparser](https://github.com/h2o/picohttpparser) and tweaked handlers for just the test purpose (prebuilt responses, no router, ...) - no wonder that it's relatively hight in [Techempower](https://www.techempower.com/benchmarks/#section=data-r19&hw=ph&test=plaintext)

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

Finally most popular [dlang][https://dlang.org] web framework that has it all.

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

