module http.DemoProcessor;



// import stdx.data.json;
import std.json;

import hunt.io;
import http.Common;
import http.Processor;
import http.HttpURI;
import http.UrlEncoded;
import hunt.logging.ConsoleLogger : trace, warning, tracef;

import std.algorithm;
import std.array;
import std.exception;
import std.random;
import std.string;

version (POSTGRESQL) {
   // __gshared Database dbConnection;
}

enum HttpHeader textHeader = HttpHeader("Content-Type", "text/plain; charset=UTF-8");
enum HttpHeader htmlHeader = HttpHeader("Content-Type", "text/html; charset=UTF-8");
enum HttpHeader jsonHeader = HttpHeader("Content-Type", "application/json; charset=UTF-8");


enum plaintextLength = "/".length;
enum jsonLength = "/json".length;
enum dbLength = "/db".length;
enum fortunesLength = "/fortunes".length;

class DemoProcessor : HttpProcessor {
    version (POSTGRESQL) HttpURI uri;

    this(TcpStream client) {
        version (POSTGRESQL) uri = new HttpURI();
        super(client);
    }

    override void onComplete(ref HttpRequest req) {

        string path = req.uri;
        if(path.length == plaintextLength) { // plaintext
            respondWith(RET.TEXT, 200, textHeader);
        } else if(path.length == jsonLength) { // json
            //JSONValue js = JSONValue(["message" : JSONValue("Hello, World!")]);
            respondWith(RET.JSON, 200, jsonHeader);
        } else {
            respondWith404();
        }
    }


    private void respondWith404() {
        //version (POSTGRESQL) {
        //    respondWith("The available paths are: /plaintext, /json, /db, /fortunes," ~
        //     " /queries?queries=number, /updates?queries=number", 404);
        //} else {
        //    respondWith("The available paths are: /plaintext, /json", 404);
        //}
    }
}
