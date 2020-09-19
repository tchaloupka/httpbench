#!/usr/bin/env dub
/+ dub.sdl:
	name "runner"
+/

import std;
import core.thread;

// default values for benchmark parameters
enum NUMREQ     = 50_000;    // number of requests to test
enum NUMCLI     = 256;      // number of workers to test with concurrently
enum REQTIMEOUT = 10;       // number of seconds for request timeout
enum TESTURL    = "http://127.0.0.1:8080/"; // url to call

// General compiler flags used to build servers (appended to those defined in meta)
struct CompilerFlags { string envName; string defVal; }
immutable CompilerFlags[string] defaultBuildFlags;

immutable bool colorOutput;
shared static this()
{
    defaultBuildFlags = [
        "dlang": CompilerFlags(
            "DFLAGS",
            "--release -O3 --boundscheck=off --ffast-math --mcpu=native"// --defaultlib=phobos2-ldc-lto,druntime-ldc-lto --flto=full"
        )
    ];

    version (Posix)
    {
        import core.sys.posix.unistd : isatty;
        if (isatty(stderr.fileno)) colorOutput = true;
    }
}

LogLevel minLogLevel = LogLevel.info;

int main(string[] args)
{
    if (args.length < 2)
    {
        WARN("No command specified, please use one of - [bench, versions]");
        return 1;
    }
    if (args[1] == "bench") return runBench(args[1..$]);
    else if (args[1] == "versions") return runVersions(args[1..$]);
    else
    {
        WARN("Unknown command specified, please use one of - [bench, versions]");
        return 1;
    }
}

int runVersions(string[] args)
{
    struct VersionInfo
    {
        string compiler;
        string function() getter;
    }

    static writeRow(string lang, string ver, char pad = ' ')
    {
        writeln("| ", lang, pad.repeat(12-lang.length), " | ", ver, pad.repeat(20-ver.length), " |");
    }

    VersionInfo[] versions = [
        VersionInfo(
            "go",
            {
                `package main
                import (
                    "fmt"
                    "runtime"
                )
                func main() {
                    fmt.Printf(runtime.Version())
                }
                `.toFile("go.go");

                auto ret = executeShell("go run go.go");
                if (ret.status) return "err";
                return ret.output;
            }
        ),
        VersionInfo(
            "ldc2",
            {
                auto reg = regex(`version\s+(.*)\s+\(`);
                auto ret = executeShell("ldc2 -v");
                auto ln = ret.output.lineSplitter.drop(1).front;
                auto m = ln.matchFirst(reg);
                if (!m) return "err";
                return m[1];
            }
        ),
        VersionInfo(
            "rust",
            {
                auto ret = executeShell("rustc --version");
                if (ret.status) return "err";
                return ret.output.splitter(" ").drop(1).front.strip;
            }
        )
    ];

    writeRow("Language", "Version");
    writeRow(null, null, '-');
    foreach (ref v; versions) writeRow(v.compiler, v.getter());
    return 0;
}

struct BenchSettings
{
    string url;
}

int runBench(string[] args)
{
    BenchmarkType benchType;
    bool verbose, vverbose, quiet;
    auto opts = args.getopt(
        "type|t", "Type of benchmark to run - one of all, singleCore, multiCore (default: all)", &benchType,
        "verbose", "Verbose output", &verbose,
        "vverbose", "Most verbose output", &vverbose,
        "quiet|q", "Output just the results", &quiet
    );

    if (opts.helpWanted)
    {
        defaultGetoptPrinter(
            "Runs HTTP benchmarks.\n"
            ~ "Usage: runner.d [opts] [name1 name2 ...]\n"
            ~ "By default it runs all benchmarks of all types. Additional partial names can be added to filter benchmarks.\n",
            opts.options);
        return 0;
    }

    if (verbose) minLogLevel = LogLevel.diag;
    if (vverbose) minLogLevel = LogLevel.trace;
    if (quiet)
    {
        enforce(!verbose && !vverbose, "Quiet and verbose used at the same time");
        minLogLevel = LogLevel.none;
    }

    string rootDir = getcwd();
    // build benchmarks list
    auto benchmarks = rootDir.dirEntries("meta.json", SpanMode.depth).filter!(a => a.isFile)
        .map!((m)
        {
                auto j = m.name.readText.parseJSON();
                return j.array.map!((t)
                {
                    try
                    {
                        Benchmark res;
                        auto p = m.name[rootDir.length+1..$].pathSplitter;
                        res.language = p.front; p.popFront;
                        res.framework = p.front;
                        auto pname = "name" in t;
                        if (pname && !(*pname).isNull) res.name = (*pname).str;
                        res.benchType = t["type"].str.to!BenchmarkType;
                        auto pcat = "category" in t;
                        if (pcat && !(*pcat).isNull) res.category = (*pcat).str;
                        auto ppre = "preCmd" in t;
                        if (ppre && !(*ppre).isNull) res.preCmd = (*ppre).array.map!(a => a.str).array;
                        res.buildCmd = t["buildCmd"].array.map!(a => a.str).array;
                        res.runCmd = t["runCmd"].array.map!(a => a.str).array;
                        auto pbe = "buildEnv" in t;
                        if (pbe && !(*pbe).isNull) res.buildEnv = (*pbe).object.byKeyValue.map!(a => tuple(a.key, a.value.str)).assocArray;
                        auto pre = "runEnv" in t;
                        if (pre && !(*pre).isNull) res.runEnv = (*pre).object.byKeyValue.map!(a => tuple(a.key, a.value.str)).assocArray;
                        res.workDir = m.name.dirName;
                        res.runCmd[0] = buildPath(res.workDir, res.runCmd[0]);
                        res.applyDefaultBuildEnv();
                        return res;
                    }
                    catch (Exception ex) throw new Exception(format!"Failed to parse benchmark metadata from %s: %s"(m.name, ex.msg));
                });
        })
        .joiner
        .filter!(a => (a.benchType & benchType))
        .array;

    benchmarks.sort!((a,b)
    {
        if (a.benchType < b.benchType) return true;
        if (a.benchType == b.benchType) return a.name < b.name;
        return false;
    });

    if (args.length > 1)
    {
        benchmarks = benchmarks.filter!(a => args[1..$].canFind!((a,b) => b.canFind(a))(a.id)).array;
    }

    // run benchmarks
    foreach (ref b; benchmarks) b.run();

    INFO("Benchmarks has been completed");

    // sort results by median
    benchmarks.sort!((a,b)
    {
        if (a.benchType < b.benchType) return true;
        if (a.benchType == b.benchType)
        {
            if (a.err || b.err) return false;
            return a.times[$/2] < b.times[$/2];
        }
        return false;
    });

    benchmarks.genTable();

    return 0;
}

// generate output as Markdown table
void genTable(Benchmark[] benchmarks)
{
    foreach (ch; benchmarks.chunkBy!(a => a.benchType))
    {
        auto recs = ch[1].array;

        // determine column sizes for even spaces in output
        size_t maxLang, maxCat, maxFW, maxName, maxErr, maxRequests, maxErrors, maxRPS, maxBPS, maxMed, maxMin, maxMax,
            max25, max75, max99, maxVals;

        foreach (ref b; recs)
        {
            maxLang = max(maxLang, b.language.length, "Language".length);
            maxCat = max(maxCat, b.category.length, "Category".length);
            maxFW = max(maxFW, b.framework.length, "Framework".length);
            maxName = max(maxName, b.name.length, "Name".length);
            maxErr = max(maxErr, b.err.length);
            maxRequests = max(maxRequests, b.total.to!string.length, "Req".length);
            maxErrors = max(maxErrors, b.errors.to!string.length, "Err".length);
            maxRPS = max(maxRPS, b.rps.to!string.length, "RPS".length);
            maxBPS = max(maxBPS, b.bps.to!string.length, "BPS".length);
            maxMed = max(maxMed, b.med.to!string.length, "med".length);
            maxMin = max(maxMin, b.min.to!string.length, "min".length);
            maxMax = max(maxMax, b.max.to!string.length, "max".length);
            max25 = max(max25, b.under25.to!string.length, "25%".length);
            max75 = max(max75, b.under75.to!string.length, "75%".length);
            max99 = max(max99, b.under99.to!string.length, "99%".length);
        }

        if (maxErr)
        {
            auto vals = [maxRequests, maxErrors, maxRPS, maxBPS, maxMed, maxMin, maxMax, max25, max75, max99];
            maxVals = (vals.length - 1) * 3 + vals.sum();
            if (maxVals < maxErr)
            {
                auto add = maxErr - maxVals;
                maxRequests += add;
                maxVals += add;
            }
        }

        // language, category, framework, name, req, err, rps, bps, med, min, max, 25%, 75%, 99%

        writeln();
        writeln(ch[0]);
        writeln('='.repeat(ch[0].to!string.length));
        writeln("| ", [
            "Language".pad(maxLang), "Category".pad(maxCat), "Framework".pad(maxFW), "Name".pad(maxName),
            "Req".pad(maxRequests), "Err".pad(maxErrors), "RPS".pad(maxRPS), "BPS".pad(maxBPS),
            "med".pad(maxMed), "min".pad(maxMin), "max".pad(maxMax), "25%".pad(max25), "75%".pad(max75),
            "99%".pad(max99)].joiner(" | "), " |");
        writeln(
            "|:",
            [maxLang, maxCat, maxFW, maxName].map!(a => pad!'-'(a)).joiner(":|:"), ":| ",
            [maxRequests, maxErrors, maxRPS, maxBPS, maxMed, maxMin, maxMax, max25, max75, max99]
                .map!(a => pad!'-'(a))
                .joiner(":| "),
            ":|"
        );
        foreach (b; recs)
        {
            if (b.err)
            {
                writeln(
                    "| ",
                    [
                        b.language.pad(maxLang), b.category.pad(maxCat), b.framework.pad(maxFW), b.name.pad(maxName)
                    ].joiner(" | "),
                    " | ",
                    b.err.pad(maxVals),
                    " |"
                );
            }
            else
            {
                writeln(
                    "| ",
                    [
                        b.language.pad(maxLang), b.category.pad(maxCat), b.framework.pad(maxFW), b.name.pad(maxName),
                        b.total.to!string.padLeft(maxRequests),
                        b.errors.to!string.padLeft(maxErrors),
                        b.rps.to!string.padLeft(maxRPS),
                        b.bps.to!string.padLeft(maxBPS),
                        b.med.to!string.padLeft(maxMed),
                        b.min.to!string.padLeft(maxMin),
                        b.max.to!string.padLeft(maxMax),
                        b.under25.to!string.padLeft(max25),
                        b.under75.to!string.padLeft(max75),
                        b.under99.to!string.padLeft(max99),
                    ].joiner(" | "),
                    " |");
            }
        }
        writeln();
    }
}

string pad(char ch = ' ')(size_t total)
{
    return pad!ch(cast(string)null, total);
}

string pad(char ch = ' ')(string str, size_t total)
{
    assert(total >= str.length);
    immutable add = total - str.length;
    return format!"%s%s%s"(
        ch.repeat(add / 2),
        str,
        ch.repeat(add / 2 + add % 2)
    );
}

string padLeft(char ch = ' ')(string str, size_t total)
{
    assert(total >= str.length);
    return format!"%s%s"(ch.repeat(total - str.length), str);
}

// applies generic language build flags
void applyDefaultBuildEnv(ref Benchmark bench)
{
    auto pbe = bench.language in defaultBuildFlags;
    if (pbe)
    {
        auto pe = (*pbe).envName in bench.buildEnv;
        if (pe) (*pe) ~= " " ~ (*pbe).defVal; // append
        else bench.buildEnv[(*pbe).envName] = (*pbe).defVal; // use just the defaults
    }
}

void run(ref Benchmark bench)
{
    try
    {
        INFO(bench.id, "...");
        bench.build();
        auto pid = bench.start();
        scope (exit) bench.kill(pid);
        bench.warmup();
        bench.test();
    }
    catch (Exception ex)
    {
        ERROR("Failed to test ", bench.id, ": ", ex.msg);
        bench.err = ex.msg.lineSplitter.front;
    }
}

// Builds server binary
void build(in Benchmark bench)
{
    DIAG("Building ", bench.id);
    if (bench.preCmd)
    {
        auto ret = execute(bench.preCmd, bench.buildEnv, Config.none, size_t.max, bench.workDir);
        enforce(ret.status == 0, format!"%s Prebuild failed: %s"(bench.id, ret.output));
        TRACE(ret.output);
    }

    auto ret = execute(bench.buildCmd, bench.buildEnv, Config.none, size_t.max, bench.workDir);
    enforce(ret.status == 0, format!"%s Build failed: %s"(bench.id, ret.output));
    TRACE(ret.output);
}

// Starts server
Pid start(in Benchmark bench)
{
    DIAG("Starting up ", bench.id);
    File f = File("/dev/null", "rw");
    return spawnProcess(bench.runCmd, f, f, f, bench.runEnv, Config.none, bench.workDir);
    // return spawnProcess(bench.runCmd, stdin, stdout, stderr, bench.runEnv, Config.none, bench.workDir);
}

// Waits for server to be started and run measurement tool to warm it up
void warmup(ref Benchmark bench)
{
    DIAG("Warming up ", bench.id);

    // wait for service to start responding
    int retry = 5;
    while (true)
    {
        try
        {
            auto ret = std.net.curl.get("http://127.0.0.1:8080/");
            enforce(ret == "Hello, World!", "Invalid response: " ~ ret);
            break;
        }
        catch (Exception ex)
        {
            if (--retry)
            {
                Thread.sleep(100.msecs);
                continue;
            }
            throw ex;
        }
    }

    // determine size of the response
    Appender!string res;
    auto http = HTTP("http://127.0.0.1:8080/");
    http.onReceiveStatusLine = (ln) => res ~= format!"HTTP/%s.%s %s %s\r\n"(ln.majorVersion, ln.minorVersion, ln.code, ln.reason);
    http.onReceiveHeader = (in char[] key, in char[] value) {  res ~= key; res ~= ": "; res ~= value; res ~= "\r\n"; };
    http.onReceive = (ubyte[] data)
    {
        res ~= "\r\n";
        res ~= cast(char[])data;
        return data.length;
    };
    http.perform();
    bench.res = res.data;
    TRACE(bench.id, " - sample response (", res.data.length, "B):\n-----\n", res.data, "\n-----");

    // warmup with benchmark tool
    auto ret = execute([
        "hey",
        "-n", (NUMREQ/10).to!string,
        "-c", NUMCLI.to!string,
        "-t", REQTIMEOUT.to!string,
        TESTURL
    ]);
    enforce(ret.status == 0, "Warmup failed: " ~ ret.output);
}

// TODO: testy s disablovaným keepalive

// Collect benchmark request times
void test(ref Benchmark bench)
{
    DIAG("Testing ", bench.id);
    auto ret = execute([
        "hey",
        "-n", NUMREQ.to!string,
        "-c", NUMCLI.to!string,
        "-t", REQTIMEOUT.to!string,
        // "-disable-keepalive", // bad impact
        "-o", "csv", TESTURL
    ]);
    enforce(ret.status == 0, "Test failed: " ~ ret.output);

    bench.times = ret.output.lineSplitter.drop(1)
        .tee!(a => bench.total++)
        .map!((line)
        {
            auto cols = line.splitter(',');
            auto time = cols.front.to!double * 1_000;
            cols = cols.drop(6);
            auto status = cols.front.to!int;
            cols.popFront;
            bench.time = cols.front.to!double;
            return tuple(time, status);
        })
        .filter!(a => a[1] == 200)
        .map!(a => a[0]).array;
    bench.times.sort();
}

// Kill server
void kill(in Benchmark bench, Pid pid)
{
    static auto getChildPids()
    {
        auto res = execute(["lsof", "-Fp", "-i", ":8080", "-s", "TCP:LISTEN"]);
        if (res.status != 0) return null;
        return res.output.lineSplitter()
            .filter!(a => a.length > 1 && a[0] == 'p')
            .map!(a => a[1..$].to!int)
            .array;
    }

    DIAG("Cleaning up ", bench.id);
    killPid(pid.osHandle);

    // check for not terminated forks
    auto childPids = getChildPids();
    if (childPids.length)
    {
        foreach (ch; childPids) killPid(ch);
        childPids = getChildPids();
        assert(!childPids.length, "Failed to kill all childs of " ~ bench.id);
    }
}

void killPid(int pid)
{
    import core.sys.posix.signal : kill, SIGKILL, SIGTERM;
    import core.sys.posix.sys.wait : waitpid, WNOHANG;
    import core.sys.linux.errno : errno, ECHILD;

    static bool wait(int pid)
    {
        int retry = 50; // 5 seconds timeout
        while (retry--)
        {
            auto wres = waitpid(pid, null, WNOHANG);
            if (wres == pid) return true;
            if (wres == -1)
            {
                if (errno == ECHILD) return true;
                assert(0, "waitpid(): " ~ errno.to!string);
            }
            Thread.sleep(200.msecs);
        }
        return false;
    }

    TRACE("Terminating pid=", pid);
    enforce(kill(pid, SIGTERM) == 0, format!"Failed to send SIGTERM to %s: %s"(pid, errno));
    if (wait(pid)) return;

    TRACE("Killing pid=", pid);
    enforce(kill(pid, SIGKILL) == 0, format!"Failed to send SIGKILL to %s: %s"(pid, errno));
    if (wait(pid)) return;
    throw new Exception("Failed to kill process");
}

enum BenchmarkType
{
    singleCore = 1,
    multiCore = 2,
    all = 3
}

struct Benchmark
{
    // metadata
    string language;
    string framework;
    string name;
    BenchmarkType benchType;
    string category;
    string[] preCmd;
    string[] buildCmd;
    string[string] buildEnv;
    string[] runCmd;
    string[string] runEnv;
    string workDir;

    // results
    string err;     // set on error
    size_t total;   // total requests made
    double time;    // total time taken [s]
    double[] times; // request times [ms]
    string res;     // sample response

    string id() const
    {
        if (name) return format!"%s/%s/%s"(language, framework, name);
        return format!"%s/%s"(language, framework);
    }

    double med() const { return times[$/2]; }
    double min() const { return times[0]; }
    double max() const { return times[$-1]; }
    double rps() const { return total / time; }
    double under25() const { return times[$/4]; }
    double under75() const { return times[3*$/4]; }
    double under99() const { return times[cast(size_t)(ceil($ * 0.99))-1]; }
    size_t bps() const { return cast(size_t)(total * res.length / time); }
    size_t errors() const { return total - times.length; }
}

// simple logger
enum LogLevel { none, trace, diag, info, warn, err }

template log(LogLevel lvl)
{
    void log(ARGS...)(lazy ARGS args)
    {
        if (minLogLevel > lvl || minLogLevel == LogLevel.none) return;
        if (colorOutput) write("\x1b[", lvl.predSwitch(
            LogLevel.trace, "49;38;5;243",
            LogLevel.diag, "49;38;5;245",
            LogLevel.info, "49;38;5;29",
            LogLevel.warn, "49;38;5;220",
            LogLevel.err, "49;38;5;9"
        ), "m");
        auto tm = Clock.currTime;
        writef("%02d:%02d:%02d.%03d | ", tm.hour, tm.minute, tm.second, tm.fracSecs.total!"msecs");
        writeln(args);
        if (colorOutput) write("\x1b[0m");
    }
}

alias TRACE = log!(LogLevel.trace);
alias DIAG = log!(LogLevel.diag);
alias INFO = log!(LogLevel.info);
alias WARN = log!(LogLevel.warn);
alias ERROR = log!(LogLevel.err);
