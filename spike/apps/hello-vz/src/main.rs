#[cfg(target_os = "hermit")]
use hermit as _;

use std::thread::sleep;
use std::time::Duration;

fn main() {
	println!("Hello World from Hermit on VZ!");
	for i in 1..=3 {
		sleep(Duration::from_millis(500));
		println!("tick {i}");
	}
	// A build with HELLO_HOLD set keeps the guest running, so boot tracing
	// (the loader and kernel's power-off checkpoints) can tell its own stop
	// from the app's.
	if option_env!("HELLO_HOLD").is_some() {
		loop {
			sleep(Duration::from_secs(60));
		}
	}
}
