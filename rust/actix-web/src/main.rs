use actix_web::{web, App, HttpResponse, HttpServer};
use std::env;
use num_cpus;

#[actix_rt::main]
async fn main() -> std::io::Result<()> {
    let num = num_cpus::get();
    println!("Num CPUs: {}", num);
    HttpServer::new(|| {
        App::new()
            .service(web::resource("/").to(|| {
                HttpResponse::Ok()
                    .content_type("text/plain")
                    .header("Server", "rust/actix-web")
                    .header("X-Test", "0123456789012345678901234567890123456789012")
                    .body("Hello, World!")
            }))
    })
    .workers(env::var("WORKERS").map_or(num, |v| v.parse().unwrap()))
    .bind("0.0.0.0:8080")?
    .run()
    .await
}
