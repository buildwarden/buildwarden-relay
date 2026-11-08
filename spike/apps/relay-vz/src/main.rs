#[cfg(target_os = "hermit")]
use hermit as _;

use std::collections::VecDeque;
use std::io::{ErrorKind, Read, Write};
use std::net::{SocketAddr, TcpStream};
use std::thread::sleep;
use std::time::{Duration, Instant as StdInstant};

use hermit_abi as abi;
use smoltcp::iface::{Config, Interface, SocketHandle, SocketSet};
use smoltcp::phy::{self, Device, DeviceCapabilities, Medium};
use smoltcp::socket::tcp;
use smoltcp::time::Instant;
use smoltcp::wire::{
	EthernetAddress, EthernetFrame, EthernetProtocol, IpCidr, IpListenEndpoint, IpProtocol,
	Ipv4Address, Ipv4Packet, TcpPacket,
};

/// Hermit's packet socket domain and type (net-packet).
const AF_PACKET: i32 = 5;
const SOCK_RAW: i32 = 3;
const SOCK_NONBLOCK: i32 = 0o4000;

/// The relay's address on the build link, which is also the build's gateway.
const LINK_IP: Ipv4Address = Ipv4Address::new(10, 0, 9, 1);
const LINK_MAC: EthernetAddress = EthernetAddress([0x02, 0x42, 0x0b, 0x00, 0x00, 0x01]);
const MTU: usize = 1514;

/// The build link: whole frames through the packet socket.
struct Link {
	fd: i32,
	rx: VecDeque<Vec<u8>>,
	frames_in: usize,
}

impl Link {
	/// Moves every frame waiting on the socket into `rx`.
	fn drain(&mut self) {
		loop {
			let mut frame = vec![0u8; MTU];
			let n = unsafe { abi::read(self.fd, frame.as_mut_ptr(), frame.len()) };
			if n <= 0 {
				return;
			}
			frame.truncate(n as usize);
			self.frames_in += 1;
			self.rx.push_back(frame);
		}
	}
}

struct RxToken(Vec<u8>);
struct TxToken(i32);

impl phy::RxToken for RxToken {
	fn consume<R, F: FnOnce(&[u8]) -> R>(self, f: F) -> R {
		f(&self.0)
	}
}

impl phy::TxToken for TxToken {
	fn consume<R, F: FnOnce(&mut [u8]) -> R>(self, len: usize, f: F) -> R {
		let mut frame = vec![0u8; len];
		let r = f(&mut frame);
		unsafe { abi::write(self.0, frame.as_ptr(), frame.len()) };
		r
	}
}

impl Device for Link {
	type RxToken<'a> = RxToken;
	type TxToken<'a> = TxToken;

	fn receive(&mut self, _: Instant) -> Option<(RxToken, TxToken)> {
		Some((RxToken(self.rx.pop_front()?), TxToken(self.fd)))
	}

	fn transmit(&mut self, _: Instant) -> Option<TxToken> {
		Some(TxToken(self.fd))
	}

	fn capabilities(&self) -> DeviceCapabilities {
		let mut caps = DeviceCapabilities::default();
		caps.medium = Medium::Ethernet;
		caps.max_transmission_unit = MTU;
		caps
	}
}

/// The TCP destination port of `frame` if it opens a connection.
fn syn_port(frame: &[u8]) -> Option<u16> {
	let eth = EthernetFrame::new_checked(frame).ok()?;
	if eth.ethertype() != EthernetProtocol::Ipv4 {
		return None;
	}
	let ip = Ipv4Packet::new_checked(eth.payload()).ok()?;
	if ip.next_header() != IpProtocol::Tcp {
		return None;
	}
	let tcp = TcpPacket::new_checked(ip.payload()).ok()?;
	(tcp.syn() && !tcp.ack()).then(|| tcp.dst_port())
}

/// One build connection and its upstream twin.
struct Conn {
	handle: SocketHandle,
	port: u16,
	upstream: Option<TcpStream>,
	route: String,
	up: usize,
	down: usize,
	upstream_eof: bool,
	closed_upstream: bool,
}

fn listening_socket(port: u16) -> tcp::Socket<'static> {
	let mut sock = tcp::Socket::new(
		tcp::SocketBuffer::new(vec![0; 65536]),
		tcp::SocketBuffer::new(vec![0; 65536]),
	);
	sock.listen(IpListenEndpoint { addr: None, port }).unwrap();
	sock
}

/// Dials `dst` through the kernel's stack, retrying while the NAT lease may
/// still be on its way.
fn connect_upstream(dst: SocketAddr) -> std::io::Result<TcpStream> {
	let mut tries = 0;
	loop {
		match TcpStream::connect_timeout(&dst, Duration::from_secs(5)) {
			Err(_) if tries < 10 => {
				tries += 1;
				sleep(Duration::from_millis(500));
			}
			result => return result,
		}
	}
}

fn main() {
	if std::env::args().nth(1).as_deref() == Some("closed") {
		// Holds the build link without reading it, to show that the kernel
		// itself never answers the build.
		println!("relay: closed, not opening the build link");
		sleep(Duration::from_secs(3600));
		return;
	}

	let fd = unsafe { abi::socket(AF_PACKET, SOCK_RAW | SOCK_NONBLOCK, 0) };
	assert!(fd >= 0, "packet socket: {fd}");
	println!("relay: build link open");

	let mut link = Link {
		fd,
		rx: VecDeque::new(),
		frames_in: 0,
	};
	let mut config = Config::new(LINK_MAC.into());
	let mut seed = [0u8; 8];
	unsafe { abi::read_entropy(seed.as_mut_ptr(), seed.len(), 0) };
	config.random_seed = u64::from_ne_bytes(seed);

	let start = StdInstant::now();
	let now = || Instant::from_micros(start.elapsed().as_micros() as i64);
	let mut iface = Interface::new(config, &mut link, now());
	iface.update_ip_addrs(|addrs| {
		addrs.push(IpCidr::new(LINK_IP.into(), 24)).unwrap();
	});
	// Answer for every destination: a route through our own address makes
	// smoltcp accept packets addressed anywhere.
	iface.set_any_ip(true);
	iface.routes_mut().add_default_ipv4_route(LINK_IP).unwrap();

	let mut sockets = SocketSet::new(vec![]);
	let mut conns: Vec<Conn> = Vec::new();

	loop {
		link.drain();
		// A listener per opened port, made as the SYN arrives.
		for port in link.rx.iter().filter_map(|frame| syn_port(frame)) {
			let listening = conns.iter().any(|c| {
				c.port == port && sockets.get::<tcp::Socket>(c.handle).state() == tcp::State::Listen
			});
			if !listening {
				let handle = sockets.add(listening_socket(port));
				conns.push(Conn {
					handle,
					port,
					upstream: None,
					route: String::new(),
					up: 0,
					down: 0,
					upstream_eof: false,
					closed_upstream: false,
				});
			}
		}

		iface.poll(now(), &mut link, &mut sockets);

		for conn in &mut conns {
			let sock = sockets.get_mut::<tcp::Socket>(conn.handle);
			if conn.upstream.is_none()
				&& !conn.closed_upstream
				&& sock.state() == tcp::State::Established
			{
				let (Some(local), Some(remote)) = (sock.local_endpoint(), sock.remote_endpoint())
				else {
					continue;
				};
				let dst = SocketAddr::new(local.addr.into(), local.port);
				conn.route = format!("{remote} -> {dst}");
				match connect_upstream(dst) {
					Ok(stream) => {
						stream.set_nonblocking(true).unwrap();
						println!(
							"relay: {} upstream from {:?}",
							conn.route,
							stream.local_addr()
						);
						conn.upstream = Some(stream);
					}
					Err(err) => {
						println!("relay: {} upstream failed: {err}", conn.route);
						sock.abort();
					}
				}
			}

			let Some(stream) = conn.upstream.as_mut() else {
				continue;
			};

			// build -> upstream
			while sock.can_recv() {
				let n = sock
					.recv(|buf| match stream.write(buf) {
						Ok(n) => (n, n),
						Err(_) => (0, 0),
					})
					.unwrap_or(0);
				if n == 0 {
					break;
				}
				conn.up += n;
			}
			// The build has finished sending. Hermit's shutdown() is a no-op,
			// so the upstream cannot be half-closed: close both directions.
			if !sock.may_recv() && sock.recv_queue() == 0 && !conn.upstream_eof {
				conn.upstream_eof = true;
				sock.close();
				conn.upstream = None;
				conn.closed_upstream = true;
				continue;
			}

			// upstream -> build
			let mut buf = [0u8; 4096];
			while !conn.upstream_eof && sock.can_send() {
				let room = sock.send_capacity() - sock.send_queue();
				let want = room.min(buf.len());
				match stream.read(&mut buf[..want]) {
					Ok(0) => {
						conn.upstream_eof = true;
						sock.close();
					}
					Ok(n) => {
						sock.send_slice(&buf[..n]).unwrap();
						conn.down += n;
					}
					Err(err) if err.kind() == ErrorKind::WouldBlock => break,
					Err(_) => {
						conn.upstream_eof = true;
						sock.close();
					}
				}
			}
		}

		// Drop finished connections.
		conns.retain(|conn| {
			let sock = sockets.get::<tcp::Socket>(conn.handle);
			let done = sock.state() == tcp::State::Closed;
			if done {
				if conn.upstream.is_some() || conn.closed_upstream {
					println!(
						"relay: {} closed, {} bytes up, {} bytes down, {} link frames in so far",
						conn.route, conn.up, conn.down, link.frames_in
					);
				}
				sockets.remove(conn.handle);
			}
			!done
		});

		sleep(Duration::from_millis(1));
	}
}
