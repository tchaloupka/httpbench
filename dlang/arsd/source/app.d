import arsd.cgi;

void hello(Cgi cgi) {
    cgi.setResponseContentType("text/plain");
    cgi.write("Hello, World!", true);
}

mixin GenericMain!hello;
