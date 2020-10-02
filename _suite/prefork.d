#!/usr/bin/env dub
/+ dub.sdl:
	name "prefork"
+/

import core.stdc.stdio;
import core.stdc.string;
import core.sys.linux.errno;
import core.sys.linux.sched;
import core.sys.posix.signal;
import core.thread;
import core.time;
import std.algorithm;
import std.file;
import std.getopt;
import std.parallelism : totalCPUs;
import std.path;
import std.process;
import std.stdio;

Pid[] workers;
bool terminate;

int main(string[] args)
{
    uint wrkNum;
    auto opts = args.getopt(
        "workers|w", "Number of workers to fork (default is host's cpu number).", &wrkNum
    );

    if (opts.helpWanted)
    {
        defaultGetoptPrinter(
            "Forks number of worker subprocesses.\n"
            ~ "Usage: prefork.d [opts] <program> -- [program args]\n",
            opts.options);
        return 0;
    }

    args = args[1..$];
    if (!args.length || args[0] == "--")
    {
        writeln("No program to run specified");
        return 1;
    }

    immutable sepIdx = args.countUntil("--");
    if (sepIdx > 1)
    {
        writeln("Only one argument worker path expected as an argument. Use '--' to separate workers arguments.");
        return 1;
    }

    if (sepIdx > 0) args = args.remove(sepIdx);
    if (args[0].startsWith('.'))
        args[0] = args[0].absolutePath.buildNormalizedPath;

    if (wrkNum == 0) wrkNum = totalCPUs;

    // set signal handler
    if (signal(SIGPIPE, SIG_IGN) == SIG_ERR || signal(SIGINT, &onSignal) == SIG_ERR || signal(SIGTERM, &onSignal) == SIG_ERR)
    {
        perror("signal()");
        return 1;
    }

    workers = new Pid[wrkNum];
    foreach(i; 0..wrkNum)
    {
        workers[i] = spawnProcess(args);
        writeln("Started subprocess, pid=", workers[i].osHandle);

        // bind process to CPU
        cpu_set_t mask;
        CPU_SET(i, &mask);
        if (sched_setaffinity(workers[i].osHandle, mask.sizeof, &mask) == -1) perror("sched_setaffinity()");
    }

    int termLoops = 10;
    while (true)
    {
        Thread.sleep(200.msecs);
        bool hasChild;
        if (terminate)
        {
            if (termLoops > 0)
            {
                if (termLoops == 10) foreach(w; workers.filter!(a => a !is null)) w.kill();
                --termLoops;
            }
            else foreach (w; workers.filter!(a => a !is null)) w.kill(SIGKILL);
        }

        foreach (i; 0..wrkNum)
        {
            if (workers[i] is null) continue;
            immutable pid = workers[i].osHandle;
            auto ret = workers[i].tryWait();
            if (ret.terminated)
            {
                writeln("Subprocess pid=", pid, " terminated with: ", ret.status);
                workers[i] = null;
                continue;
            }

            hasChild = true;
        }

        if (!hasChild) return 0;
    }
}

extern(C) char* strsignal(int sig) nothrow @nogc;

extern(C) void onSignal(int sig) nothrow @nogc
{
    printf("onSignal: %s\n", strsignal(sig));
    terminate = true;
}
