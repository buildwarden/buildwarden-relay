#!/bin/sh
# Signs vmnetprobe three ways (no entitlements, virtualization only,
# virtualization + com.apple.vm.networking, all ad hoc) and runs each,
# recording the exit status and what amfid / the kernel logged at launch.
#
# usage: run-probes.sh   (from spike/vznet; writes evidence/probe-*.log)
set -u
for e in none virt virt+vmnetworking; do
	b=bin/vmnetprobe-$e
	cp bin/vmnetprobe "$b"
	out=evidence/probe-$e.log
	{
		echo "## codesign -s - -f --entitlements ents/$e.plist $b"
		codesign -s - -f --entitlements "ents/$e.plist" "$b" 2>&1; echo "codesign exit $?"
		codesign -d --entitlements - "$b" 2>&1 | grep -E 'key|Executable' 
		start=$(date '+%Y-%m-%d %H:%M:%S')
		echo "## run"
		"./$b" 2>&1; echo "exit $?"
		sleep 2
		echo "## log show (amfid, kernel AMFI, vmnet, taskgated) since $start"
		log show --style compact --start "$start" --predicate \
			'process == "amfid" OR process == "taskgated-helper" OR (process == "kernel" AND (eventMessage CONTAINS[c] "amfi" OR eventMessage CONTAINS[c] "vmnetprobe")) OR subsystem CONTAINS[c] "vmnet" OR eventMessage CONTAINS[c] "vmnetprobe"' 2>&1 | tail -40
	} > "$out" 2>&1
	echo "== $out"; cat "$out"
done
