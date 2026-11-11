#[cfg(target_os = "hermit")]
use hermit as _;

use std::mem;
use std::thread::sleep;
use std::time::Duration;

use hermit_abi as abi;

const HOST_PORT: u32 = 5001;
const GUEST_PORT: u32 = 5000;

fn addr(cid: u32, port: u32) -> abi::sockaddr_vm {
	abi::sockaddr_vm {
		svm_len: mem::size_of::<abi::sockaddr_vm>() as u8,
		svm_family: abi::AF_VSOCK as u8,
		svm_port: port,
		svm_cid: cid,
		..Default::default()
	}
}

fn check(what: &str, ret: i32) -> i32 {
	if ret < 0 {
		println!("vsock: {what} failed ({ret})");
		sleep(Duration::from_millis(500));
		std::process::exit(1);
	}
	ret
}

fn read_some(fd: i32) -> Vec<u8> {
	let mut buf = [0u8; 256];
	let n = unsafe { abi::read(fd, buf.as_mut_ptr(), buf.len()) };
	buf[..n.max(0) as usize].to_vec()
}

fn write_all(fd: i32, data: &[u8]) {
	let mut off = 0;
	while off < data.len() {
		let n = unsafe { abi::write(fd, data[off..].as_ptr(), data.len() - off) };
		check("write", n as i32);
		off += n as usize;
	}
}

fn main() {
	unsafe {
		// Guest to host.
		let fd = check("socket", abi::socket(abi::AF_VSOCK, abi::SOCK_STREAM, 0));
		let host = addr(abi::VMADDR_CID_HOST, HOST_PORT);
		check(
			"connect",
			abi::connect(fd, (&raw const host).cast(), mem::size_of_val(&host) as u32),
		);
		write_all(fd, b"guest says hi\n");
		let reply = read_some(fd);
		println!("vsock: host replied: {}", String::from_utf8_lossy(&reply).trim_end());
		abi::close(fd);

		// Host to guest.
		let listener = check("socket", abi::socket(abi::AF_VSOCK, abi::SOCK_STREAM, 0));
		let any = addr(abi::VMADDR_CID_ANY, GUEST_PORT);
		check(
			"bind",
			abi::bind(listener, (&raw const any).cast(), mem::size_of_val(&any) as u32),
		);
		check("listen", abi::listen(listener, 1));
		println!("vsock: listening on port {GUEST_PORT}");
		let mut peer = abi::sockaddr_vm::default();
		let mut len = mem::size_of_val(&peer) as u32;
		let conn = check(
			"accept",
			abi::accept(listener, (&raw mut peer).cast(), &mut len),
		);
		println!("vsock: accepted cid {} port {}", peer.svm_cid, peer.svm_port);
		loop {
			let data = read_some(conn);
			if data.is_empty() {
				break;
			}
			write_all(conn, &data);
		}
		println!("vsock: echo done");
		abi::close(conn);
	}
	sleep(Duration::from_millis(500));
}
