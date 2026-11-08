#[cfg(target_os = "hermit")]
use hermit as _;

use std::collections::HashMap;
use std::thread::sleep;
use std::time::Duration;

fn main() {
	let mut buf = [0u8; 32];
	let n = unsafe { hermit_abi::read_entropy(buf.as_mut_ptr(), buf.len(), 0) };
	if n == buf.len() as isize {
		let hex: String = buf.iter().map(|b| format!("{b:02x}")).collect();
		println!("entropy: {hex}");
	} else {
		println!("entropy: unavailable ({n})");
	}
	// Give VZ time to drain the console: the HashMap below panics when there
	// is no entropy, and the guest powers off at once.
	sleep(Duration::from_millis(500));

	let mut map = HashMap::new();
	map.insert("key", n);
	println!("hashmap: ok");
	sleep(Duration::from_millis(500));
}
