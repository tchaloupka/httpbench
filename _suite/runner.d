#!/usr/bin/env dub
/+ dub.sdl:
	name "runner"
+/

import core.thread;
import std.algorithm;
import std.conv;
import std.datetime.systime;
import std.exception;
import std.file;
import std.getopt;
import std.json;
import std.math;
import std.net.curl;
import std.path;
import std.process;
import std.range;
import std.regex;
import std.stdio;
import std.string;
import std.typecons;

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

    import core.sys.posix.unistd : isatty;
    if (isatty(stderr.fileno)) colorOutput = true;
}

LogLevel minLogLevel = LogLevel.info;

struct Cmd
{
    string name;
    string desc;
    int function(string[] args) handler;
}

immutable Cmd[] commands = [
    Cmd("bench", "Evaluetes performance of the selected tests", &runBench),
    Cmd("list", "List available tests", &runList),
    Cmd("responses", "Run tests binary to sample their HTTP response", &runResponses),
    Cmd("versions", "Prints used compilers versions", &runVersions)
];

void printGlobalDescription()
{
    writeln("runner.d is an entry point to control this benchmark suite.");
    writeln("Use one of it's subcommands:");
    immutable maxLen = commands.map!(a => a.name.length).maxElement + 2;
    foreach (c; commands) writeln(c.name.pad(maxLen), " - ", c.desc);
    writeln();
    writeln("Use 'runner.d <cmd> -h/--help' to print individual command help");
}

int main(string[] args)
{
    if (args.length < 2)
    {
        WARN("No command specified");
        printGlobalDescription();
        return 1;
    }

    if (args.length == 2 && args[1].among("-h", "--help"))
    {
        printGlobalDescription();
        return 0;
    }

    immutable cmd = commands.countUntil!((a,b) => a.name == b)(args[1]);
    if (cmd < 0)
    {
        WARN("Unknown command specified");
        printGlobalDescription();
        return 1;
    }

    try return commands[cmd].handler(args[1..$]);
    catch (Exception ex)
    {
        ERROR("Error executing command ", commands[cmd].name, ": ", ex.msg);
        return 1;
    }
}

int runVersions(string[] args)
{
    auto opts = args.getopt();
    if (opts.helpWanted)
    {
        defaultGetoptPrinter(
            "Prints used compilers versions.\n"
            ~ "Usage: runner.d versions\n",
            opts.options);
        return 0;
    }

    struct VersionInfo
    {
        string compiler;
        string function() getter;
        string ver;
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

                auto ret = executeShell("go run go.go && rm go.go");
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
        ),
        VersionInfo(
            "dotnet",
            {
                auto ret = executeShell("dotnet --version");
                if (ret.status) return "err";
                return ret.output.strip;
            }
        )
    ];

    size_t maxCmp, maxVer;
    foreach (ref v; versions)
    {
        v.ver = v.getter();
        maxCmp = max(maxCmp, v.compiler.length, "Language".length);
        maxVer = max(maxVer, v.ver.length, "Version".length);
    }

    writeln("| ", "Language".padRight(maxCmp), " | ", "Version".padRight(maxVer), " |");
    writeln("| ", pad!'-'(maxCmp), " | ", pad!'-'(maxVer), " |");
    foreach (ref v; versions)
        writeln("| ", v.compiler.padRight(maxCmp), " | ", v.ver.padRight(maxVer), " |");
    return 0;
}

int runList(string[] args)
{
    BenchmarkType benchType = BenchmarkType.all;
    auto opts = args.getopt(
        "type|t", "Type of benchmarks to list - one of all, singleCore, multiCore (default: all)", &benchType,
    );

    if (opts.helpWanted)
    {
        defaultGetoptPrinter(
            "Lists available HTTP benchmarks.\n"
            ~ "Usage: runner.d list [opts]\n",
            opts.options);
        return 0;
    }

    auto benchmarks = loadBenchmarks().filter!(a => (a.benchType & benchType)).array;

    bool first;
    foreach (grp; benchmarks.chunkBy!(a => a.benchType))
    {
        auto gbs = grp[1].array;

        if (first) first = false;
        else writeln();

        writeln("# ", grp[0], "\n");
        size_t maxLang, maxFW, maxName;
        foreach (b; gbs)
        {
            maxLang = max(b.language.length, maxLang, "Language".length);
            maxFW = max(b.framework.length, maxFW, "Framework".length);
            maxName = max(b.name.length, maxName, "Name".length);
        }
        writeln(
            "| ",
            ["Language".padRight(maxLang), "Framework".padRight(maxFW), "Name".padRight(maxName)].joiner(" | "),
            " |");
        writeln("| ", [pad!'-'(maxLang), pad!'-'(maxFW), pad!'-'(maxName)].joiner(" | "), " |");

        foreach(b; gbs) writeln(
            "| ",
            [b.language.padRight(maxLang), b.framework.padRight(maxFW), b.name.padRight(maxName)].joiner(" | "),
            " |");
    }

    return 0;
}

enum IGNORE_DESC =
    "Comma separated list of tests to ignore. This can be combined with the provided tests to refine tests selection."
    ~ "(Partial text can be used as tests are being ignored where their identifier contains it)."
    ~ "Sample usage: 'runner.d bench dlang -i hunt' - runs all dlang tests but not hunt ones.";

int runResponses(string[] args)
{
    bool verbose, vverbose, quiet;
    string ignore;
    auto opts = args.getopt(
        "verbose|v", "Verbose output", &verbose,
        "vverbose", "Most verbose output", &vverbose,
        "quiet|q", "Output just the results", &quiet,
        "ignore|i", IGNORE_DESC, &ignore
    );

    if (opts.helpWanted)
    {
        defaultGetoptPrinter(
            "Prints out sampled response from tests.\n"
            ~ "Usage: runner.d responses [opts] [name1 name2 ...]\n"
            ~ "By default it checks response of all tests. Additional partial names can be added to filter them.\n",
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

    auto benchmarks = loadBenchmarks(args[1..$], ignore).array;

    // get responses
    foreach (ref b; benchmarks)
    {
        try
        {
            b.build();
            auto pid = b.start();
            scope (exit) b.kill(pid);
            b.waitResponse();
        }
        catch (Exception ex)
        {
            ERROR("Failed to determine response of ", b.id, ": ", ex.msg);
            b.err = ex.msg.lineSplitter.front;
        }
    }

    foreach (i, grp; benchmarks.chunkBy!(a => a.benchType).enumerate)
    {
        if (i > 0) writeln();
        writeln("# ", grp[0]);
        writeln();

        foreach (j, b; grp[1].enumerate)
        {
            if (j > 0) writeln();
            writeln("## ", b.id, " (", b.res.length, "B)");
            writeln();
            writeln("```");
            writeln(b.err ? b.err : b.res);
            writeln("```");
        }
    }

    return 0;
}

// benchmark params
enum Tool { hey, wrk }
enum Format { csv, markdown }
string testURL;
string remoteHost;
int numReq;                 // number of requests to test
int numClients = 64;        // number of workers to test with concurrently
int reqTimeout = 60;        // number of seconds for request timeout
string testPath;
int bestOfNum = 1;
bool keepalive = true;
Tool tool = Tool.wrk;
uint duration = 10;
uint threads;
uint pipeline = 1;
Format fmt = Format.markdown;

int runBench(string[] args)
{
    BenchmarkType benchType = BenchmarkType.all;
    bool verbose, vverbose, quiet;
    string host, ignore;

    auto opts = args.getopt(
        "type", "Type of benchmark to run - one of all, singleCore, multiCore (default: all)", &benchType,
        "verbose|v", "Verbose output", &verbose,
        "vverbose", "Most verbose output", &vverbose,
        "quiet|q", "Output just the results", &quiet,
        "remote|r",
            "Use remote host to generate load. Format: [<user>@]<remote_host>.\n"
            ~ "Test tool (hey/wrk) must be installed on the remote host.\n"
            ~ "Use with --host argument to specify remote addres and port to be called\n"
            ~ "(if not provided too, it'll be determined from default route).", &remoteHost,
        "host",
            "Use specified host instead of default 'localhost'.\n"
            ~ "Can be used with combination with --remote. Format <host>[:<port>]", &host,
        // experimental - see #3
        "path|p", "URL path to call tests on. Default is '/' and currently tests implements just this one.", &testPath,
        // hey params
        "n", "Number of requests to run with hey tool. Default is 1 000 per client.", &numReq,
        "c",
            "Number of workers to run concurrently for hey tool."
            ~ "Number of connections for wrk tool. Default is 64.",
            &numClients,
        "t", "Timeout for each request in seconds. Default is 10, use 0 for infinite.", &reqTimeout,
        "bestof|b", "Runs each test multiple times and outputs just the best one. Default is 1.", &bestOfNum,
        "keepalive|k", "Should workload generator use same connection for multiple requests? Default true.", &keepalive,
        "tool", "Tool to use as a load generator. One of hey, wrk. Default is wrk.", &tool,
        "duration|d", "Duration of the individual test in seconds to use with wrk tool. Default is 10s.", &duration,
        "threads", "Total number of threads to use with wrk tool. Default is host number of CPUs.", &threads,
        "ignore|i", IGNORE_DESC, &ignore,
        "format|f", "Output format (one of csv, markdown - default).", &fmt,
        "pipeline", "How many requests should be HTTP pipelined (wrk tool only, default is 1 - no HTTP pipelining).", &pipeline
    );

    if (opts.helpWanted)
    {
        defaultGetoptPrinter(
            "Runs HTTP benchmarks.\n"
            ~ "Usage: runner.d bench [opts] [name1 name2 ...]\n"
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

    if (!numReq) numReq = 1000 * numClients;

    if (host)
    {
        immutable idx = host.lastIndexOf(':');
        if (idx > 0) testURL = format!"http://%s/"(host);
        else testURL = format!"http://%s:8080/"(host);
    }
    else if (remoteHost)
    {
        // determine box IP from default route
        auto ret = execute(["ip", "route", "get", "8.8.8.8"]);
        enforce(ret.status == 0, "Error determining default route: " ~ ret.output);

        static immutable string ipPrefix = "8.8.8.8 via ";
        auto ips = ret.output.lineSplitter.filter!(a => a.startsWith(ipPrefix)).map!((a)
        {
            immutable sidx = a.countUntil(" src ");
            immutable uidx = a.countUntil(" uid ");
            enforce(sidx > 0 && uidx > 0 && uidx > sidx, "Unexpected ip output format in line: " ~ a);
            return a[sidx+5 .. uidx];
        });
        enforce(!ips.empty, "Unable to parse default route from: " ~ ret.output);
        testURL = format!"http://%s:8080/"(ips.front);
    }
    else testURL = "http://127.0.0.1:8080/";

    testPath = testPath.stripLeft('/');
    if (testPath.length) testURL ~= testPath;

    if (tool == Tool.wrk && !threads)
    {
        // determine host threads
        typeof(execute("")) ret;
        if (remoteHost) ret = execute(["ssh", remoteHost, "nproc", "--all"]);
        else ret = execute(["nproc", "--all"]);
        enforce(ret.status == 0, "Error determinig host number of CPUs: " ~ ret.output);
        threads = ret.output.stripRight.to!uint;
        if ((benchType & BenchmarkType.singleCore) && !remoteHost) threads--; // leave some for singleCore test process
        if (numClients < threads) threads = numClients;
    }

    static bool copyScript(string name)
    {
        // prep wrk script on the host
        DIAG("Copying ", name, " to host ", remoteHost);
        auto pip = buildPath(getSuiteDir(), name);
        auto ret = execute(["scp", pip, remoteHost ~ ":/tmp/"]);
        if (ret.status != 0)
        {
            ERROR("Failed to copy ", pip, " to ", remoteHost, ": ", ret.output);
            return false;
        }
        return true;
    }

    pipeline = max(1, pipeline);
    if (remoteHost) {
        if (!(pipeline > 1 ? copyScript("pipeline.lua") : copyScript("report.lua"))) return 1;
    }

    DIAG("Test url: ", testURL);

    auto benchmarks = loadBenchmarks(args[1..$], ignore)
        .filter!(a => (a.benchType & benchType)).array;

    // run benchmarks
    foreach (ref b; benchmarks) b.run();

    INFO("Benchmarks has been completed");

    // sort results
    benchmarks.sort!((a,b)
    {
        if (a.benchType < b.benchType) return true;
        if (a.benchType == b.benchType)
        {
            if (!a.err && !b.err) return a.stats.rps > b.stats.rps;
            if (a.err && !b.err) return false;
            if (!a.err && b.err) return true;
            return a.err < b.err;
        }
        return false;
    });

    final switch (fmt)
    {
        case Format.markdown: benchmarks.genMarkdownTable(); break;
        case Format.csv: benchmarks.genCsvTable(); break;
    }


    return 0;
}

auto loadBenchmarks(string[] tests = null, string ignore = null)
{
    string rootDir = getcwd();

    // build benchmarks list
    auto benchmarks = rootDir.dirEntries("meta.json", SpanMode.depth).filter!(a => a.isFile)
        .map!((m)
        {
            try
            {
                auto j = m.name.readText.parseJSON();
                return j.array.map!((t)
                {
                    Benchmark res;
                    auto p = m.name[rootDir.length+1..$].pathSplitter;
                    res.language = p.front; p.popFront;
                    res.framework = p.front;
                    auto pname = "name" in t;
                    if (pname && !(*pname).isNull) res.name = (*pname).str;
                    res.benchType = t["type"].str.to!BenchmarkType;
                    auto pcat = "category" in t;
                    if (pcat && !(*pcat).isNull) res.category = (*pcat).str.to!Category;
                    auto ppre = "preCmd" in t;
                    if (ppre && !(*ppre).isNull) res.preCmd = (*ppre).array.map!(a => a.str).array;
                    auto pbld = "buildCmd" in t;
                    if (pbld && !(*pbld).isNull) res.buildCmd = (*pbld).array.map!(a => a.str).array;
                    res.runCmd = t["runCmd"].array.map!(a => a.str).array;
                    auto pbe = "buildEnv" in t;
                    if (pbe && !(*pbe).isNull) res.buildEnv = (*pbe).object.byKeyValue.map!(a => tuple(a.key, a.value.str)).assocArray;
                    auto pre = "runEnv" in t;
                    if (pre && !(*pre).isNull) res.runEnv = (*pre).object.byKeyValue.map!(a => tuple(a.key, a.value.str)).assocArray;
                    res.workDir = m.name.dirName;

                    res.runCmd[0] = res.runCmd[0].fixLocal(res.workDir);
                    if (res.preCmd.length) res.preCmd[0] = res.preCmd[0].fixLocal(res.workDir);
                    if (res.buildCmd.length) res.buildCmd[0] = res.buildCmd[0].fixLocal(res.workDir);
                    res.applyDefaultBuildEnv();
                    return res;
                });
            }
            catch (Exception ex) throw new Exception(format!"Failed to parse benchmark metadata from %s: %s"(m.name, ex.msg));
        })
        .joiner
        .array;

    benchmarks.sort!((a,b)
    {
        if (a.benchType < b.benchType) return true;
        if (a.benchType > b.benchType) return false;
        if (a.language < b.language) return true;
        if (a.language > b.language) return false;
        if (a.framework < b.framework) return true;
        if (a.framework > b.framework) return false;
        return a.name < b.name;
    });

    if (tests.length)
        benchmarks = benchmarks.filter!(a => tests.canFind!((a,b) => b.canFind(a))(a.id)).array;
    if (ignore)
    {
        auto ig = ignore.splitter(',').map!(a => a.strip).filter!(a => a.length).array;
        if (ig.length)
            benchmarks = benchmarks.filter!(a => !ig.canFind!((a,b) => b.canFind(a))(a.id)).array;
    }

    return benchmarks;
}

// workaround for #20765 (fixed in dmd-2.094.0)
string fixLocal(string cmd, string workDir)
{
    if (cmd.startsWith('.')) return cmd.absolutePath(workDir).buildNormalizedPath;
    return cmd;
}

// generate output as Markdown table
void genMarkdownTable(Benchmark[] benchmarks)
{
    foreach (ch; benchmarks.chunkBy!(a => a.benchType))
    {
        auto recs = ch[1].array;

        // determine column sizes for even spaces in output
        size_t maxLang, maxCat, maxFW, maxName, maxErr, maxRes, maxRequests, maxErrors, maxRPS, maxBPS, maxMed, maxMin, maxMax,
            max25, max75, max99, maxVals;
        bool hasErrors, hasDiffRes;
        foreach (ref b; recs)
        {
            maxLang = max(maxLang, b.language.length, "Language".length);
            maxCat = max(maxCat, b.category.to!string.length, "Category".length);
            maxFW = max(maxFW, b.framework.length, "Framework".length);
            maxName = max(maxName, b.name.length, "Name".length);
            maxErr = max(maxErr, b.err.length);
            maxRes = max(maxRes, b.res.length.to!string.length, "Res[B]".length);
            maxRequests = max(maxRequests, b.stats.total.toSepStr.length, "Req".length);
            maxErrors = max(maxErrors, b.stats.errors.to!string.length, "Err".length);
            hasErrors |= b.stats.errors > 0;
            maxRPS = max(maxRPS, b.stats.rps.format!"%.2f".length, "RPS".length);
            maxBPS = max(maxBPS, b.bps.toSepStr.length, "BPS".length);
            maxMed = max(maxMed, b.stats.med.to!string.length, "med".length);
            maxMin = max(maxMin, b.stats.min.to!string.length, "min".length);
            maxMax = max(maxMax, b.stats.max.to!string.length, "max".length);
            max25 = max(max25, b.stats.perc25.to!string.length, "25%".length);
            max75 = max(max75, b.stats.perc75.to!string.length, "75%".length);
            max99 = max(max99, b.stats.perc99.to!string.length, "99%".length);
        }

        hasDiffRes = recs.map!(a => a.res.length).array.sort().uniq.walkLength > 1;

        if (maxErr)
        {
            auto vals = [maxRes, maxRequests, maxErrors, maxRPS, maxBPS, maxMin, max25, maxMed, max75, max99, maxMax];
            if (!hasErrors) vals = vals.remove(2);
            maxVals = (vals.length - 1) * 3 + vals.sum();
            if (maxVals < maxErr)
            {
                auto add = maxErr - maxVals;
                maxRes += add;
                maxVals += add;
            }
        }

        writeln();
        writeln(ch[0]);
        writeln('='.repeat(ch[0].to!string.length));
        writeln();
        string[] cols = [
            "Language".pad(maxLang), "Framework".pad(maxFW), "Category".pad(maxCat), "Name".pad(maxName),
            "Res[B]".pad(maxRes), "Req".pad(maxRequests)];
        if (!hasDiffRes) cols = cols.remove(4);
        if (hasErrors) cols ~= "Err".pad(maxErrors);
        cols ~= ["RPS".pad(maxRPS), "BPS".pad(maxBPS)];
        cols ~= [
            "min".pad(maxMin), "25%".pad(max25), "50%".pad(maxMed),
            "75%".pad(max75), "99%".pad(max99), "max".pad(maxMax)
        ];
        writeln("| ", cols.joiner(" | "), " |");
        auto pads = [maxRes, maxRequests, maxErrors, maxRPS, maxBPS];
        if (!hasErrors) pads = pads.remove(2);
        if (!hasDiffRes) pads = pads.remove(0);
        writeln(
            "|:",
            [maxLang, maxFW, maxCat, maxName].map!(a => pad!'-'(a)).joiner(":|:"), ":| ",
            pads.map!(a => pad!'-'(a)).joiner(":| "), ":| ",
            [maxMin, max25, maxMed, max75, max99, maxMax]
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
                        b.language.pad(maxLang),
                        b.framework.pad(maxFW),
                        b.category.to!string.pad(maxCat),
                        b.name.pad(maxName)
                    ].joiner(" | "),
                    " | ",
                    b.err.pad(maxVals),
                    " |"
                );
            }
            else
            {
                cols = [
                    b.language.pad(maxLang),
                    b.framework.pad(maxFW),
                    b.category.to!string.pad(maxCat),
                    b.name.pad(maxName),
                    b.res.length.to!string.padLeft(maxRes),
                    b.stats.total.toSepStr.padLeft(maxRequests),
                    b.stats.errors.to!string.padLeft(maxErrors),
                    b.stats.rps.format!"%.2f".padLeft(maxRPS),
                    b.bps.toSepStr.padLeft(maxBPS)
                ];
                if (!hasErrors) cols = cols.remove(6);
                if (!hasDiffRes) cols = cols.remove(4);
                writeln(
                    "| ", cols.joiner(" | "),
                    " | ",
                    [
                        b.stats.min.to!string.padLeft(maxMin),
                        b.stats.perc25.to!string.padLeft(max25),
                        b.stats.med.to!string.padLeft(maxMed),
                        b.stats.perc75.to!string.padLeft(max75),
                        b.stats.perc99.to!string.padLeft(max99),
                        b.stats.max.to!string.padLeft(maxMax)
                    ].joiner(" | "),
                    " |");
            }
        }
        writeln();
    }
}

void genCsvTable(Benchmark[] benchmarks)
{
    enum string SEP = ";";

    string[] cols = [
        "Type", "Language", "Framework", "Category", "Name", "Res[B]", "Req", "Err", "RPS", "BPS",
        "min", "25%", "50%", "75%", "99%", "max"];

    writeln(cols.joiner(SEP));
    foreach (ref b; benchmarks)
    {
        if (b.err) continue; // don't output them in csv

        cols = [
            b.benchType.to!string,
            b.language,
            b.framework,
            b.category.to!string,
            b.name,
            b.res.length.to!string,
            b.stats.total.to!string,
            b.stats.errors.to!string,
            b.stats.rps.to!string,
            b.bps.to!string,
            b.stats.min.to!string,
            b.stats.perc25.to!string,
            b.stats.med.to!string,
            b.stats.perc75.to!string,
            b.stats.perc99.to!string,
            b.stats.max.to!string
        ];

        writeln(cols.joiner(SEP));
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

string padRight(char ch = ' ')(string str, size_t total)
{
    assert(total >= str.length);
    return format!"%s%s"(str, ch.repeat(total - str.length));
}

// applies generic language build flags
void applyDefaultBuildEnv(ref Benchmark bench)
{
    auto pbe = bench.language in defaultBuildFlags;
    if (pbe)
    {
        auto pe = (*pbe).envName in bench.buildEnv;
        if (pe) {
            if ((*pe).length) (*pe) ~= " " ~ (*pbe).defVal; // append only when it's not disabled by empty value
        }
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
        bench.waitResponse();
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

    if (bench.buildCmd)
    {
        auto ret = execute(bench.buildCmd, bench.buildEnv, Config.none, size_t.max, bench.workDir);
        enforce(ret.status == 0, format!"%s Build failed: %s"(bench.id, ret.output));
        TRACE(ret.output);
    }
}

// Starts server
Pid start(in Benchmark bench)
{
    DIAG("Starting up ", bench.id);
    File fi = File("/dev/null", "r");
    File fo = File("/dev/null", "w");
    File fe = File("/dev/null", "w");
    return spawnProcess(bench.runCmd, fi, fo, fe, bench.runEnv, Config.none, bench.workDir);
    // return spawnProcess(bench.runCmd, stdin, stdout, stderr, bench.runEnv, Config.none, bench.workDir);
}

void waitResponse(ref Benchmark bench)
{
    DIAG("Awaiting response from ", bench.id);

    // wait for service to start responding
    int retry = 50;
    string localUri = "http://127.0.0.1:8080/" ~ testPath;
    while (true)
    {
        try
        {
            auto ret = std.net.curl.get(localUri);
            if (ret != "Hello, World!") WARN("Unexpected response: " ~ ret);
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
    auto http = HTTP(localUri);
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
}

// Waits for server to be started and run measurement tool to warm it up
void warmup(ref Benchmark bench)
{
    DIAG("Warming up ", bench.id);

    // warmup with benchmark tool
    auto ret = tool == Tool.hey
        ? runHey(max(numReq / 10, numClients), numClients, 5)
        : runWrk(numClients, threads, reqTimeout, max(1, duration / 10));
    enforce(ret.status == 0, "Warmup failed: " ~ ret.output);
    TRACE(ret.output);
}

// Collect benchmark request times
void test(ref Benchmark bench)
{
    Results res;
    foreach (i; 0..bestOfNum)
    {
        DIAG("Testing ", bench.id, " - run ", i+1, " of ", bestOfNum);
        try
        {
            auto ret = tool == Tool.hey
                ? runHey(numReq, numClients, reqTimeout, "csv")
                : runWrk(numClients, threads, reqTimeout, duration, pipeline);
            enforce(ret.status == 0, "Test failed: " ~ ret.output);

            Results tmp = tool == Tool.hey ? ret.output.parseHeyResults() : ret.output.parseWrkResults();
            // DIAG("RPS: ", tmp.total / tmp.time);
            if (!res.total || (res.total <= tmp.total && (res.total / res.time) < (tmp.total / tmp.time)))
                res = tmp;
        }
        catch (Exception ex)
        {
            if (!res.total && i+1 == bestOfNum) throw ex;
        }
    }
    bench.stats = res;
}

Results parseHeyResults(string output)
{
    TRACE(output);
    Results res;
    res.time = 0;
    auto times = output.lineSplitter.drop(1)
        .tee!(a => res.total++)
        .map!((line)
        {
            auto cols = line.splitter(',');
            auto time = cols.front.to!double; // in seconds
            cols = cols.drop(6);
            auto status = cols.front.to!int;
            cols.popFront;
            res.time = max(res.time, cols.front.to!double + time); // offset + time
            return tuple(time*1_000, status); // to msecs
        })
        .filter!(a => a[1] == 200)
        .map!(a => a[0]).array;
    times.sort();

    res.min     = times.length ? times[0] : 0;
    res.max     = times.length ? times[$-1] : 0;
    res.rps     = times.length ? (res.total / res.time) : 0;
    res.med     = times.length ? times.percentile(0.5) : 0;
    res.perc25 = times.length ? times.percentile(0.25) : 0;
    res.perc75 = times.length ? times.percentile(0.75) : 0;
    res.perc99 = times.length ? times.percentile(0.99) : 0;
    res.errors  = res.total - times.length;
    return res;
}

double percentile(double[] data, double frac)
in (frac >= 0 && frac <= 1.0, "Invalid percentile")
in (data.length, "No data")
{
    double rank = frac*(data.length-1);
    auto idx = cast(size_t)trunc(rank);
    return data[idx] + (data[idx+1]-data[idx])*(rank-idx);
}

Results parseWrkResults(string output)
{
    static auto maxReg = regex(`^\s+Latency\s+[0-9.]+\w+\s+[0-9.]+\w+\s+([0-9.]+)(\w+)`);
    static auto latReg = regex(`^Custom stats: (\d+) (\d+) (\d+) (\d+) (\d+) (\d+)$`);
    static auto totalReg = regex(`^\s+(\d+) requests in ([0-9.]+)(\w+)`);
    static auto errReg = regex(`^\s+Non-.*responses: (\d+)`);

    TRACE(output);
    Results res;
    foreach (ln; output.lineSplitter)
    {
        auto m = ln.matchFirst(maxReg);
        if (m)
        {
            res.max = m[1].to!double.toMsecs(m[2]);
            continue;
        }

        m = ln.matchFirst(latReg);
        if (m)
        {
            // all values are in usecs
            res.min = m[1].to!size_t.toMsecs;
            res.perc25 = m[2].to!size_t.toMsecs;
            res.med = m[3].to!size_t.toMsecs;
            res.perc75 = m[4].to!size_t.toMsecs;
            res.perc99 = m[5].to!size_t.toMsecs;
            res.max = m[6].to!size_t.toMsecs;
            continue;
        }

        m = ln.matchFirst(totalReg);
        if (m)
        {
            res.total = m[1].to!uint;
            res.time = m[2].to!double.toMsecs(m[3]) / 1_000;
            continue;
        }

        m = ln.matchFirst(errReg);
        if (m)
        {
            res.errors = m[1].to!uint;
            continue;
        }
    }

    res.rps = res.total ? (res.total / res.time) : 0;
    return res;
}

double toMsecs(double time, string tm = "us")
{
    switch (tm)
    {
        case "us": return time / 1_000;
        case "ms": return time;
        case "s": return time * 1_000;
        case "m": return time * 60_000;
        default:
            WARN("Unhandled time spec: ", tm);
            return 0;
    }
}

auto runHey(int requests, int clients, int timeout, string fmt = null)
{
    string[] args = [
        "hey",
        "-n", requests.to!string,
        "-c", clients.to!string,
        "-t", timeout.to!string,
    ];
    if (!keepalive) args ~= "-disable-keepalive";
    if (fmt) args ~= ["-o", fmt];
    args ~= testURL;

    if (remoteHost) args = ["ssh", remoteHost, args.joiner(" ").text];
    return execute(args);
}

auto runWrk(uint clients, uint threads, int timeout, uint duration, uint pipeline = 0)
{
    string[] args = [
        "wrk",
        "-c", clients.to!string,
        "-t", threads.to!string,
        "--timeout", timeout.to!string,
        "-d", duration.to!string,
        "--latency",
        testURL
    ];

    auto getScriptArgs(string name)
    {
        string[] ret = ["-s"];
        if (remoteHost)
            ret ~= ("/tmp/" ~ name);
        else
            ret ~= buildPath(getSuiteDir(), name);

        if (pipeline) ret ~= ["--", pipeline.to!string];
        return ret;
    }

    if (pipeline > 1) args ~= getScriptArgs("pipeline.lua");
    else args ~= getScriptArgs("report.lua");
    if (remoteHost) args = ["ssh", remoteHost, args.joiner(" ").text];
    return execute(args);
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
        if (childPids.length) WARN(format!"Failed to kill all childs of %s: %s"(bench.id, childPids));
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

string toSepStr(N)(N num)
{
    return format!"%,?d"(' ', num);
}

string getSuiteDir()
{
    string cwd = getcwd;
    immutable sidx = cwd.countUntil("_suite");
    if (sidx > 0) return cwd[0..sidx+"_suite".length];
    return buildPath(cwd, "_suite");
}

enum BenchmarkType
{
    singleCore = 1,
    multiCore = 2,
    all = 3
}

enum Category
{
    micro,
    platform,
    fullStack
}

struct Results
{
    size_t total;   // total requests made
    double time;    // total time taken [s]
    double rps;
    size_t errors;

    double min;
    double perc25;
    double med;
    double perc75;
    double perc99;
    double max;
}

struct Benchmark
{
    // metadata
    string language;
    string framework;
    string name;
    BenchmarkType benchType;
    Category category;
    string[] preCmd;
    string[] buildCmd;
    string[string] buildEnv;
    string[] runCmd;
    string[string] runEnv;
    string workDir;

    // results
    string err;     // set on error
    string res;     // sample response
    Results stats;  // result statistics

    string id() const
    {
        if (name) return format!"%s/%s/%s"(language, framework, name);
        return format!"%s/%s"(language, framework);
    }

    size_t bps() const { return stats.total ? cast(size_t)(stats.total * res.length / stats.time) : 0; }
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
