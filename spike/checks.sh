#!/bin/sh
# The spike's acceptance checks against the patched loader and kernel
# (patches/), each printing PASS or FAIL:
#
#   qemu-uart     upstream hello_world, Qemu virt, PL011 console
#   qemu-vcon     hello-vz, Qemu virt, modern virtio-console over PCI
#   qemu-net      echo-vz, Qemu virt, modern virtio-net, host port forward
#   vz-hello      exit criterion A: hello-vz on VZ, virtio console
#   vz-net        exit criterion B: echo-vz on VZ NAT, DHCP lease, host->guest
#   qemu-rng      entropy-vz, Qemu virt, seeded from virtio-rng
#   vz-rng        entropy-vz on VZ twice, seeded from virtio-rng, values differ
#   vz-norng      entropy-vz on VZ without an entropy device: fails closed
#   vz-vsock      vsock-vz on VZ: guest->host and host->guest over virtio-vsock
#   vz-pair       relay-vz and build-vz on VZ (vzpair): the build's TCP
#                 connection crosses the build link to the relay's own
#                 stack and leaves through the relay's NAT NIC
#   vz-pair-closed  the same, with the relay not reading the build link:
#                 the build reaches nothing
#
# Every Qemu run has a virtio-rng device: the patched kernel fails closed
# without an entropy source, and std then panics before main.
#
# vz-net connects to the guest's NAT address, so run it from a terminal with
# macOS Local Network permission; vz-vsock needs none. The vz-pair checks
# serve the build's destination from the host, on the NAT network. Exit
# status: the number of failures.
#
# usage: checks.sh <out dir>
set -u
here=$(cd "$(dirname "$0")" && pwd)
out=$1
mkdir -p "$out"
elf=$here/.work/loader/target/release/hermit-loader-aarch64-elf
img=$here/out/hermit-loader-vz.Image
hello=$here/.work/hermit-rs/target/aarch64-unknown-hermit/release/hello_world
hellovz=$here/apps/hello-vz/target/aarch64-unknown-hermit/release/hello-vz
echovz=$here/apps/echo-vz/target/aarch64-unknown-hermit/release/echo-vz
entropyvz=$here/apps/entropy-vz/target/aarch64-unknown-hermit/release/entropy-vz
vsockvz=$here/apps/vsock-vz/target/aarch64-unknown-hermit/release/vsock-vz
relayvz=$here/apps/relay-vz/target/aarch64-unknown-hermit/release/relay-vz
buildvz=$here/apps/build-vz/target/aarch64-unknown-hermit/release/build-vz
fails=0

result() { # name ok detail
	if [ "$2" = 0 ]; then echo "PASS $1  $3"; else echo "FAIL $1  $3"; fails=$((fails + 1)); fi
}

# Runs Qemu virt in the background with the patched loader; $1 names the logs.
qemu() {
	name=$1
	shift
	qemu-system-aarch64 -machine virt,gic-version=3 -accel hvf -cpu host -smp 1 -m 512M \
		-display none -semihosting -serial "file:$out/$name-uart.log" -kernel "$elf" \
		-device virtio-rng-pci,disable-legacy=on "$@" \
		2> "$out/$name-qemu.log" &
	qpid=$!
}

# Waits up to $2 seconds for pid $1 to exit, then stops it.
reap() {
	n=0
	while kill -0 "$1" 2>/dev/null && [ "$n" -lt "$2" ]; do sleep 1; n=$((n + 1)); done
	kill "$1" 2>/dev/null
	wait "$1" 2>/dev/null
}

# Waits up to $3 seconds for file $1 to contain $2.
await() {
	n=0
	until grep -a -q "$2" "$1" 2>/dev/null; do
		n=$((n + 1))
		[ "$n" -gt "$3" ] && return 1
		sleep 1
	done
}

qemu qemu-uart -nic none -device "guest-loader,addr=0x48000000,initrd=$hello"
reap "$qpid" 15
grep -a -q "Hello, world!" "$out/qemu-uart-uart.log"
result qemu-uart $? "upstream hello_world on the PL011"

qemu qemu-vcon -nic none -device virtio-serial-pci,disable-legacy=on \
	-chardev "file,id=c0,path=$out/qemu-vcon-console.log" -device virtconsole,chardev=c0 \
	-device "guest-loader,addr=0x48000000,initrd=$hellovz"
reap "$qpid" 15
grep -a -q "tick 3" "$out/qemu-vcon-console.log"
result qemu-vcon $? "hello-vz on the virtio console"

qemu qemu-net -netdev user,id=n0,hostfwd=tcp:127.0.0.1:17000-:7000 \
	-device virtio-net-pci,netdev=n0,disable-legacy=on \
	-device "guest-loader,addr=0x48000000,initrd=$echovz"
await "$out/qemu-net-uart.log" "listening on" 20 && sleep 2
want="qemu echo $$"
got=$( (echo "$want"; sleep 2) | nc -w 3 127.0.0.1 17000)
kill "$qpid" 2>/dev/null
wait "$qpid" 2>/dev/null
[ "$got" = "$want" ]
result qemu-net $? "echo through a port forward: '$got'"

"$here/out/vzrun" "$img" "$hellovz" --console "$out/vz-hello-console.log" --seconds 20 \
	> "$out/vz-hello-vzrun.log" 2>&1
grep -a -q "Hello World from Hermit on VZ!" "$out/vz-hello-console.log" &&
	grep -a -q "tick 3" "$out/vz-hello-console.log"
result vz-hello $? "Hello World over VZ's virtio console"

mac=02:42:ac:11:$(printf '%02x:%02x' $(($$ % 256)) $(($$ / 256 % 256)))
lease_mac=$(echo "$mac" | sed -E 's/(^|:)0([0-9a-f])/\1\2/g')
"$here/out/vzrun" "$img" "$echovz" --mac "$mac" --console "$out/vz-net-console.log" \
	--seconds 60 > "$out/vz-net-vzrun.log" 2>&1 &
vpid=$!
await /var/db/dhcpd_leases "hw_address=1,$lease_mac" 30
ip=$(grep -B2 "hw_address=1,$lease_mac" /var/db/dhcpd_leases | grep ip_address | tail -1 | cut -d= -f2)
await "$out/vz-net-console.log" "listening on" 20 && sleep 1
want="vz echo $$"
got=$( (echo "$want"; sleep 2) | nc -w 3 "${ip:-0.0.0.0}" 7000 2>/dev/null)
kill "$vpid" 2>/dev/null
wait "$vpid" 2>/dev/null
[ -n "$ip" ] && [ "$got" = "$want" ]
result vz-net $? "lease ${ip:-none} for $mac, host->guest echo: '$got'"

# The 32 random bytes entropy-vz printed to log $1, if std then ran.
entropy() {
	grep -a -q "hashmap: ok" "$1" && grep -a "^entropy: [0-9a-f]\{64\}" "$1" | cut -d' ' -f2
}

qemu qemu-rng -nic none -device "guest-loader,addr=0x48000000,initrd=$entropyvz"
reap "$qpid" 15
e=$(entropy "$out/qemu-rng-uart.log")
grep -a -q "Virtio entropy device" "$out/qemu-rng-uart.log" && [ -n "$e" ]
result qemu-rng $? "seeded from virtio-rng: ${e:-none}"

for n in 1 2; do
	"$here/out/vzrun" "$img" "$entropyvz" --console "$out/vz-rng$n-console.log" --seconds 15 \
		> "$out/vz-rng$n-vzrun.log" 2>&1
done
e1=$(entropy "$out/vz-rng1-console.log")
e2=$(entropy "$out/vz-rng2-console.log")
grep -a -q "Virtio entropy device" "$out/vz-rng1-console.log" && [ -n "$e1" ] && [ -n "$e2" ] &&
	[ "$e1" != "$e2" ]
result vz-rng $? "two boots: ${e1:-none} ${e2:-none}"

"$here/out/vzrun" "$img" "$entropyvz" --no-rng --console "$out/vz-norng-console.log" \
	--seconds 15 > "$out/vz-norng-vzrun.log" 2>&1
grep -a -q "No entropy source" "$out/vz-norng-console.log" &&
	! grep -a -q -E "^entropy: |hashmap: ok" "$out/vz-norng-console.log"
result vz-norng $? "no entropy device: the kernel refuses and the app does not run"

"$here/out/vzrun" "$img" "$vsockvz" --vsock --console "$out/vz-vsock-console.log" --seconds 20 \
	> "$out/vz-vsock-vzrun.log" 2>&1
grep -q "said: guest says hi" "$out/vz-vsock-vzrun.log" &&
	grep -a -q "host replied: host says hi" "$out/vz-vsock-console.log" &&
	grep -q "vsock: echo ok" "$out/vz-vsock-vzrun.log" &&
	grep -a -q "vsock: echo done" "$out/vz-vsock-console.log"
result vz-vsock $? "guest->host port 5001 and host->guest port 5000 echo"

# Boots the relay and the build over a build link; $1 names the logs, $2 is
# the relay app's argument, $3 the seconds to allow. The host's echo server
# is on an uncommon port, so another experiment's listener does not collide.
pair() {
	"$here/out/vzpair" "$img" "$relayvz" "$buildvz" \
		--relay-cmdline "env=HERMIT_RAW_MAC=02:42:0b:00:00:01 -- $2" \
		--build-cmdline "-ip 10.0.9.2 -gateway 10.0.9.1 -mask 255.255.255.0 -- 192.168.64.1:47100" \
		--relay-console "$out/$1-relay.log" --build-console "$out/$1-build.log" --seconds "$3" --port 47100 \
		> "$out/$1-vzpair.log" 2>&1
}

pair vz-pair "" 60
from=$(grep "echo server: connection from" "$out/vz-pair-vzpair.log" | head -1 | sed 's/.*from //')
grep -a -q "Network device 02-42-0b-00-00-01 serves packet sockets" "$out/vz-pair-relay.log" &&
	grep -a -q "closed, 14 bytes up, 14 bytes down" "$out/vz-pair-relay.log" &&
	grep -a -q "build: echo: build says hi" "$out/vz-pair-build.log" &&
	case $from in 192.168.64.*) true ;; *) false ;; esac
result vz-pair $? "build 10.0.9.2 -> relay -> host, which saw ${from:-nothing}"

pair vz-pair-closed closed 30
! grep -q "echo server: connection" "$out/vz-pair-closed-vzpair.log" &&
	! grep -a -q "build: echo" "$out/vz-pair-closed-build.log" &&
	grep -a -q "relay: closed" "$out/vz-pair-closed-relay.log"
result vz-pair-closed $? "relay not reading the link: the build reached nothing"

exit "$fails"
