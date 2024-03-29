#[global_allocator]
static ALLOC: snmalloc_rs::SnMalloc = snmalloc_rs::SnMalloc;

use std::env;
use std::future::Future;
use std::io;
use std::pin::Pin;
use std::task::{Context, Poll};

use actix_codec::{AsyncWrite};
use actix_http::{h1, Request};
use actix_rt::net::TcpStream;
use actix_server::Server;
use actix_service::fn_service;
use bytes::{Buf, BufMut, BytesMut};
use tokio::io::{AsyncBufRead, BufReader};
use tokio_util::codec::Decoder;

const HEAD_PLAIN: &[u8] = b"HTTP/1.1 200 OK\r\nServer: Actix RAW_012345678901234567890123456789012345678901234567890123456\r\nContent-Type: text/plain\r\nContent-Length: 13\r\n";
const HEAD_NOT_FOUND: &[u8] = b"HTTP/1.1 404 Not Found\r\n";
const HDR_END: &[u8] = b"\r\n";
const BODY: &[u8] = b"Hello, World!";

struct App {
    io: BufReader<TcpStream>,
    read_buf: BytesMut,
    write_buf: BytesMut,
    codec: h1::Codec,
}

impl App {
    fn handle_request(&mut self, req: Request) {
        match req.path() {
            "/" => {
                self.write_buf.put_slice(HEAD_PLAIN);
                self.codec
                    .config()
                    .write_date_header(&mut self.write_buf, false);
                self.write_buf.put_slice(HDR_END);
                self.write_buf.put_slice(BODY);
            }
            _ => {
                self.write_buf.put_slice(HEAD_NOT_FOUND);
                self.write_buf.put_slice(HDR_END);
            }
        }
    }
}

impl Future for App {
    type Output = Result<(), ()>;

    fn poll(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Self::Output> {
        let this = self.get_mut();

        loop {
            if this.read_buf.capacity() - this.read_buf.len() < 512 {
                this.read_buf.reserve(32_768);
            }

            let n = match Pin::new(&mut this.io).poll_fill_buf(cx) {
                Poll::Pending => break,
                Poll::Ready(Ok(filled)) => {
                    if filled.is_empty() {
                        return Poll::Ready(Ok(()));
                    }

                    this.read_buf.extend_from_slice(filled);
                    filled.len()
                }
                Poll::Ready(Err(_)) => return Poll::Ready(Err(())),
            };

            Pin::new(&mut this.io).consume(n);
        }

        if this.write_buf.capacity() - this.write_buf.len() <= 512 {
            this.write_buf.reserve(32_768);
        }

        loop {
            match this.codec.decode(&mut this.read_buf) {
                Ok(Some(h1::Message::Item(req))) => this.handle_request(req),
                Ok(None) => break,
                _ => return Poll::Ready(Err(())),
            }
        }

        if !this.write_buf.is_empty() {
            let len = this.write_buf.len();
            let mut written = 0;
            while written < len {
                match Pin::new(&mut this.io).poll_write(cx, &this.write_buf[written..]) {
                    Poll::Pending => {
                        break;
                    }
                    Poll::Ready(Ok(n)) => {
                        if n == 0 {
                            return Poll::Ready(Ok(()));
                        } else {
                            written += n;
                        }
                    }
                    Poll::Ready(Err(_)) => return Poll::Ready(Err(())),
                }
            }

            if written == len {
                unsafe { this.write_buf.set_len(0) }
            } else if written > 0 {
                this.write_buf.advance(written);
            }
        }
        Poll::Pending
    }
}

#[actix_web::main]
async fn main() -> io::Result<()> {
    let num = num_cpus::get();
    println!("Num CPUs: {}", num);
    println!("Started http server: 127.0.0.1:8080");

    // start http server
    Server::build()
        .backlog(1024)
        .workers(env::var("WORKERS").map_or(num, |v| v.parse().unwrap()))
        .bind("bench", "0.0.0.0:8080", || {
            fn_service(|io: TcpStream| App {
                io: BufReader::new(io),
                read_buf: BytesMut::with_capacity(32_768),
                write_buf: BytesMut::with_capacity(32_768),
                codec: h1::Codec::default(),
            })
        })?
        .run()
        .await
}
