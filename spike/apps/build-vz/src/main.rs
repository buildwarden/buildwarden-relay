#[cfg(target_os = "hermit")]
use hermit as _;

use std::io::{Read, Write};
use std::net::{SocketAddr, TcpStream};
use std::thread::sleep;
use std::time::Duration;

fn main() {
	let target: SocketAddr = std::env::args()
		.nth(1)
		.unwrap_or_else(|| "192.168.64.1:7100".into())
		.parse()
		.expect("target address");
	println!("build: connecting to {target}");

	// The relay may still be booting; give it 30 seconds.
	let mut stream = None;
	for _ in 0..30 {
		match TcpStream::connect_timeout(&target, Duration::from_secs(1)) {
			Ok(s) => {
				stream = Some(s);
				break;
			}
			Err(_) => sleep(Duration::from_secs(1)),
		}
	}
	let Some(mut stream) = stream else {
		println!("build: no connection to {target}");
		return;
	};

	stream.write_all(b"build says hi\n").unwrap();
	let mut buf = [0u8; 256];
	let mut got = Vec::new();
	while !got.ends_with(b"\n") {
		match stream.read(&mut buf) {
			Ok(0) | Err(_) => break,
			Ok(n) => got.extend_from_slice(&buf[..n]),
		}
	}
	println!("build: echo: {}", String::from_utf8_lossy(&got).trim_end());
	drop(stream);
	sleep(Duration::from_secs(1));
}
