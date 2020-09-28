package main

import (
    "github.com/valyala/fasthttp"
    "fmt"
    "runtime"
    "os"
)

func main() {
    fmt.Printf("ENV says GOMAXPROCS=%s\n", os.Getenv("GOMAXPROCS"))
    fmt.Printf("GOMAXPROCS says GOMAXPROCS=%d\n", runtime.GOMAXPROCS(0))
    fmt.Printf("runtime says MAXPROCS=%d\n", runtime.NumCPU())

    server := &fasthttp.Server{
        Name:                          "Go",
        Handler:                       Plaintext,
        DisableHeaderNamesNormalizing: true,
    }

    if err := server.ListenAndServe(":8080"); err != nil {
        panic(err)
    }
}

func Plaintext(ctx *fasthttp.RequestCtx) {
    ctx.Response.Header.Set("X-Test", "0123456789012345678901234567890123456789")
    ctx.Response.SetBodyString("Hello, World!")
}
