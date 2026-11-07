#!/bin/sh
# Sibling reachability: boot one probe VM as the echo server, then a second
# probe VM on the same VZ NAT network as the client (probe.peer=<server ip>),
# the path a sibling build VM takes to a relay VM. Exit 0 if the client's
# line came back.
#
# usage: sibling-test.sh <kernel> <initrd> <out dir>
set -u
kernel=$1 initrd=$2 out=$3
devs="--device virtio-rng --device virtio-net,nat"

rm -f "$out/sibling-server.log" "$out/sibling-client.log"
vfkit --cpus 1 --memory 512 \
	--bootloader "linux,kernel=$kernel,initrd=$initrd,cmdline=console=hvc0" \
	--device "virtio-serial,logFilePath=$out/sibling-server.log" $devs \
	> "$out/vfkit-server.log" 2>&1 &
server=$!

n=0
until grep -q '=== PROBE listen' "$out/sibling-server.log" 2>/dev/null; do
	n=$((n + 1))
	[ "$n" -gt 120 ] && { echo "sibling-test: server never listened"; kill "$server"; exit 1; }
	sleep 1
done
ip=$(grep -E '^ip=' "$out/sibling-server.log" | head -1 | cut -d= -f2 | tr -d '\r')

# Record the host bridge's members while both VMs are up: a PRIVATE member
# is isolated from the bridge's other members at layer 2.
(sleep 10; for b in $(ifconfig -l); do
	case $b in bridge*) ifconfig "$b" ;; esac
done > "$out/sibling-bridge.txt" 2>&1) &

vfkit --cpus 1 --memory 512 \
	--bootloader "linux,kernel=$kernel,initrd=$initrd,cmdline=console=hvc0 probe.peer=$ip" \
	--device "virtio-serial,logFilePath=$out/sibling-client.log" $devs \
	> "$out/vfkit-client.log" 2>&1
wait "$server"

client=$(grep -E '^ip=' "$out/sibling-client.log" | head -1 | cut -d= -f2 | tr -d '\r')
echo "sibling-test: client $client -> server $ip:7000"
sed -n '/=== PROBE sibling/,/=== PROBE end/p' "$out/sibling-client.log" | tr -d '\r'
grep -q 'SIBLING OK' "$out/sibling-client.log"
