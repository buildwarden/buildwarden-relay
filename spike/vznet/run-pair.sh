#!/bin/sh
# Runs one vmnetpair case into evidence/<case>/ and prints the verdict
# lines. The build VM's result is "build: echo: ..." (reached the target)
# or "build: no connection" / a timeout (did not).
#
# usage: run-pair.sh <case> <vmnetpair options...>
set -u
case=$1; shift
out=evidence/$case
rm -rf "$out"; mkdir -p "$out"
G=guests
echo "## vmnetpair $*" > "$out/runner.log"
./bin/vmnetpair $G/hermit-loader-vz.Image $G/echo-vz $G/build-vz --out "$out" "$@" >> "$out/runner.log" 2>&1
echo "exit $?" >> "$out/runner.log"
echo "=== $case"
cat "$out/runner.log"
grep -h -a -E "IP address|build:|connection from|DHCP" "$out"/*.console.log | sed 's/\x1b\[[0-9;]*m//g'
grep -E "^bridge|inet |member" "$out/host-side.txt" 2>/dev/null
