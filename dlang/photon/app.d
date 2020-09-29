import std.algorithm;
import std.conv;
import std.datetime;
import std.format;
import std.range;
import std.stdio;
import std.string;
import std.socket;
import std.uni;
import core.thread;

import photon;
import utils.http_server;

final class HelloWorldProcessor : HttpProcessor {
    this(Socket sock){ super(sock); }

    override void onComplete(HttpRequest req) {
        respondWith(
            "Hello, World!", 200,
            [
                HttpHeader("Content-Type", "text/plain; charset=utf-8"),
                HttpHeader("X-Test: 012345678901234567890123456")
            ]
        );
    }
}

void server_worker(Socket client) {
    scope processor = new HelloWorldProcessor(client);
    processor.run();
}

void server() {
    Socket server = new TcpSocket();
    server.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
    server.bind(new InternetAddress("0.0.0.0", 8080));
    server.listen(1000);

    void processClient(Socket client) {
        spawn(() => server_worker(client));
    }

    while (true) {
        try {
            debug writeln("Waiting for server.accept()");
            Socket client = server.accept();
            debug writeln("New client accepted");
            processClient(client);
        }
        catch (Exception e) {
            writefln("Failure to accept %s", e);
        }
    }
}

void main(string[] args) {

    if (args.length > 1) startloop(args[1].to!uint);
    else startloop();
    spawn(() => server());
    runFibers();
}
