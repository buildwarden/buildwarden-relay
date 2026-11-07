#[cfg(target_os = "hermit")]
use hermit as _;

use std::io::{Read, Write};
use std::net::TcpListener;

fn main() {
	let listener = TcpListener::bind("0.0.0.0:7000").expect("bind :7000");
	println!("echo-vz listening on :7000");
	for stream in listener.incoming() {
		let Ok(mut stream) = stream else { continue };
		println!("connection from {:?}", stream.peer_addr().ok());
		let mut buf = [0u8; 1024];
		loop {
			match stream.read(&mut buf) {
				Ok(0) | Err(_) => break,
				Ok(n) => {
					if stream.write_all(&buf[..n]).is_err() {
						break;
					}
				}
			}
		}
	}
}
