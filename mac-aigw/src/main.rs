use std::env;

use anyhow::Context;
use tokio::io;
use tokio::net::{TcpListener, TcpStream};

const DEFAULT_LISTEN: &str = "127.0.0.1:1234";

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let listen_addr =
        env::var("LISTEN_ADDR").unwrap_or_else(|_| DEFAULT_LISTEN.to_string());
    let upstream_addr = env::var("UPSTREAM_ADDR")
        .context("set UPSTREAM_ADDR to the aigw gateway host:port (HOST:PORT from the gateway .env)")?;

    let listener = TcpListener::bind(&listen_addr).await?;
    eprintln!("[aigw] listening on {listen_addr} -> {upstream_addr}");

    loop {
        let (inbound, peer_addr) = listener.accept().await?;
        let upstream = upstream_addr.clone();
        tokio::spawn(async move {
            match proxy(inbound, &upstream).await {
                Ok((up, down)) => {
                    eprintln!("[aigw] {peer_addr} closed ({up}↑ {down}↓ bytes)")
                }
                Err(e) => eprintln!("[aigw] {peer_addr} error: {e}"),
            }
        });
    }
}

async fn proxy(inbound: TcpStream, upstream: &str) -> anyhow::Result<(u64, u64)> {
    inbound.set_nodelay(true)?;
    let outbound = TcpStream::connect(upstream).await?;
    outbound.set_nodelay(true)?;

    let (mut ri, mut wi) = io::split(inbound);
    let (mut ro, mut wo) = io::split(outbound);

    let (up, down) = tokio::try_join!(
        io::copy(&mut ri, &mut wo),
        io::copy(&mut ro, &mut wi),
    )?;

    Ok((up, down))
}
