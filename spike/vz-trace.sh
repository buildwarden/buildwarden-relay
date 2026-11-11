#!/bin/sh
# Boot tracing on VZ for a guest that cannot print: each boot asks the
# patched loader and kernel one yes/no question through the bootargs, and
# the answer is whether the guest powers itself off (yes) or spins until the
# timeout (no). `vzhold` turns the kernel's normal shutdown into a spin so
# only an answer stops the guest.
#
# usage: vz-trace.sh <loader Image> <app> panic          panic file and line
#        vz-trace.sh <loader Image> <app> stop N...      which checkpoints run
set -u
img=$1 app=$2 mode=$3
shift 3
here=$(cd "$(dirname "$0")" && pwd)

ask() {
	"$here/out/vzrun" "$img" "$app" --cmdline "vzhold $1" --seconds "${SECS:-4}" 2>&1 \
		| tail -1 | grep -q 'guest stopped'
}

case $mode in
panic)
	ask "vzstop=40" || { echo "no panic"; exit 0; }
	line=0
	for k in 0 1 2 3 4 5 6 7 8 9 10 11; do
		ask "vzpl=$k" && line=$((line | (1 << k)))
	done
	files=""
	for f in kernel/src fdt-0 hermit-entry virtio smoltcp core/src alloc/src \
		drivers/console drivers/pci drivers/net drivers/virtio mm/ arch/aarch64 \
		env.rs executor scheduler syscalls; do
		ask "vzpf=$f" && files="$files $f"
	done
	echo "panic at line $line, file matches:$files"
	;;
stop)
	for n in "$@"; do
		ask "vzstop=$n" && echo "checkpoint $n: reached" || echo "checkpoint $n: not reached"
	done
	;;
esac
