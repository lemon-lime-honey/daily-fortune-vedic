mod handlers;
mod models;

use axum::{routing::post, Router};
use std::net::SocketAddr;

#[tokio::main]
async fn main() {
    let app = Router::new()
        .route("/calculate", post(handlers::calculate_chart));

    let addr_str = std::env::var("CALC_BIND_ADDR").unwrap_or_else(|_| "0.0.0.0:8080".to_string());
    let addr: SocketAddr = addr_str
        .parse()
        .expect("Invalid CALC_BIND_ADDR configuration");

    println!("Starting calc service on {}", addr);
    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
