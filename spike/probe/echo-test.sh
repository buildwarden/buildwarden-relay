#!/bin/sh
# Host side of the probe's reachability check: wait for the guest's echo
# server (probe/init, section "listen"), connect to its leased address from
# the host, and report whether the line came back. Exit 0 on a round trip.
#
# usage: echo-test.sh <console log> [port]
set -u
log=$1
port=${2:-7000}

n=0
until grep -q '=== PROBE listen' "$log" 2>/dev/null; do
	n=$((n + 1))
	[ "$n" -gt 120 ] && { echo "echo-test: guest never listened"; exit 1; }
	sleep 1
done

ip=$(grep -E '^ip=' "$log" | head -1 | cut -d= -f2 | tr -d '\r')
[ -n "$ip" ] || { echo "echo-test: no DHCP lease in $log"; exit 1; }

want="echo-test $(date +%s)"
got=$(printf "%s\n" "$want" | nc -v -w 3 "$ip" "$port")
echo "echo-test: guest $ip:$port sent '$want' got '$got'"
[ "$got" = "$want" ]
