#!/bin/sh
# The spike's acceptance checks against the patched loader and kernel
# (patches/), each printing PASS or FAIL:
#
#   qemu-uart     upstream hello_world, Qemu virt, PL011 console
#   qemu-vcon     hello-vz, Qemu virt, modern virtio-console over PCI
#   qemu-net      echo-vz, Qemu virt, modern virtio-net, host port forward
#   vz-hello      exit criterion A: hello-vz on VZ, virtio console
#   vz-net        exit criterion B: echo-vz on VZ NAT, DHCP lease, host->guest
#
# vz-net connects to the guest's NAT address, so run it from a terminal with
# macOS Local Network permission. Exit status: the number of failures.
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
fails=0

result() { # name ok detail
	if [ "$2" = 0 ]; then echo "PASS $1  $3"; else echo "FAIL $1  $3"; fails=$((fails + 1)); fi
}

# Runs Qemu virt in the background with the patched loader; $1 names the logs.
qemu() {
	name=$1
	shift
	qemu-system-aarch64 -machine virt,gic-version=3 -accel hvf -cpu host -smp 1 -m 512M \
		-display none -semihosting -serial "file:$out/$name-uart.log" -kernel "$elf" "$@" \
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

exit "$fails"
