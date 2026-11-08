# VZ spike: Hermit on Apple Virtualization (M0). See REPORT.md.
#
# Upstream sources and release artifacts land in .work/ (git-ignored), build
# and run output in out/. Every upstream version is in the block below, the
# one place to bump (Decision 17).

HERMIT_TAG   := hermit-0.13.2
KERNEL_TAG   := v0.13.2
LOADER_TAG   := v0.5.7
TOOLCHAIN    := nightly-2026-02-01
# The loader (and host-side tools) need a newer nightly than hermit-rs pins;
# nightly-2026-11-01 builds a loader that hangs mid-boot, so this is pinned
# near the loader release (built with rustc 1.97.1).
LOADER_TOOLCHAIN := nightly-2026-08-15
# The loader release's aarch64 binary and its test app (a Git LFS object),
# pinned by hash.
LOADER_SHA   := 1b6faeb93cf1a0a240641e2286f0db5fecd19a6b7fb5625496e089a34fd3e5d8
FIXTURE_SHA  := 815814403c76f928d318e534ff4976c33af55476ebaf2a2bd6cde6e0b41e1654

# Probe inputs: the main repo's relay-vm arm64 kernel, its package (for the
# network modules) and its static busybox.
NATIVE       ?= $(HOME)/src/buildwarden-native
PROBE_KERNEL ?= $(NATIVE)/tools/relay-vm/output/Image
BUSYBOX      ?= $(NATIVE)/tools/relay-vm/.cache/busybox
KERNEL_APK   ?= $(NATIVE)/tools/relay-vm/.cache/linux-virt.apk
KMOD_DIR     := lib/modules/6.12.114-0-virt/kernel
KMODS        := $(KMOD_DIR)/net/core/failover.ko.gz \
                $(KMOD_DIR)/drivers/net/net_failover.ko.gz \
                $(KMOD_DIR)/drivers/net/virtio_net.ko.gz \
                $(KMOD_DIR)/net/packet/af_packet.ko.gz

WORK := .work
OUT  := out
export PATH := /opt/homebrew/opt/rustup/bin:$(HOME)/.cargo/bin:$(PATH)
LLVM  = $(firstword $(wildcard $(HOME)/.rustup/toolchains/$(TOOLCHAIN)-*/lib/rustlib/*/bin))

# Source builds, from the pinned tags plus patches/ (see REPORT.md).
LOADER_ELF := $(WORK)/loader/target/release/hermit-loader-aarch64-elf
LOADER_VZ  := $(WORK)/loader/target/release/hermit-loader-aarch64-vz
LOADER_IMG := $(OUT)/hermit-loader-vz.Image
HELLO      := $(WORK)/hermit-rs/target/aarch64-unknown-hermit/release/hello_world
HELLO_VZ   := apps/hello-vz/target/aarch64-unknown-hermit/release/hello-vz
ECHO_VZ    := apps/echo-vz/target/aarch64-unknown-hermit/release/echo-vz
ENTROPY_VZ := apps/entropy-vz/target/aarch64-unknown-hermit/release/entropy-vz
VSOCK_VZ   := apps/vsock-vz/target/aarch64-unknown-hermit/release/vsock-vz
RELAY_VZ   := apps/relay-vz/target/aarch64-unknown-hermit/release/relay-vz
BUILD_VZ   := apps/build-vz/target/aarch64-unknown-hermit/release/build-vz
# Stock release artifacts, for the unpatched attempts.
STOCK_LOADER := $(WORK)/release-$(LOADER_TAG)/hermit-loader-aarch64-elf
STOCK_HELLO  := $(WORK)/fixture-$(LOADER_TAG)/hello_world

VZRUN := $(OUT)/vzrun
VZPAIR := $(OUT)/vzpair
STUBS := control spin dtb pc uart ecam

# Hermit apps build against the patched kernel checkout, not the one
# hermit-rs would fetch (the hermit crate's HERMIT_MANIFEST_DIR).
HERMIT_BUILD := HERMIT_MANIFEST_DIR=$(abspath $(WORK)/kernel) cargo +$(TOOLCHAIN) build \
	-Zbuild-std=std,panic_abort -Zbuild-std-features=compiler-builtins-mem \
	--target aarch64-unknown-hermit --release

.PHONY: all sources patched loader apps qemu checks stock qemu-stock header vz-stock \
	stubs probe probe-sibling clean

all: checks

# --- Upstream sources ---------------------------------------------------------

$(WORK)/hermit-rs:
	git clone -q --depth 1 -b $(HERMIT_TAG) https://github.com/hermit-os/hermit-rs $@
$(WORK)/loader:
	git clone -q --depth 1 -b $(LOADER_TAG) https://github.com/hermit-os/loader $@
$(WORK)/kernel:
	git clone -q --depth 1 -b $(KERNEL_TAG) https://github.com/hermit-os/kernel $@

sources: $(WORK)/hermit-rs $(WORK)/loader $(WORK)/kernel

# The patches, applied once to fresh clones in this order: the VZ boot fixes
# (*-vz.patch), the virtio-rng driver (*-rng.patch), the vsock fixes
# (*-vsock.patch), virtio-net on VZ's file handle attachment
# (*-filehandle.patch) and packet sockets for the build link
# (*-packet.patch). The *-checkpoints and *-tracing patches are the
# boot-tracing tools; apply them by hand on top when debugging (see
# REPORT.md, "Boot tracing").
KERNEL_PATCHES := $(addprefix patches/kernel-v0.13.2-,vz.patch rng.patch vsock.patch \
	filehandle.patch packet.patch)
HERMIT_RS_PATCHES := $(addprefix patches/hermit-rs-0.13.2-,rng.patch packet.patch)
$(WORK)/.patched: patches/loader-v0.5.7-vz.patch $(KERNEL_PATCHES) $(HERMIT_RS_PATCHES) \
		| sources
	git -C $(WORK)/loader apply $(abspath patches/loader-v0.5.7-vz.patch)
	for p in $(abspath $(KERNEL_PATCHES)); do git -C $(WORK)/kernel apply $$p || exit 1; done
	for p in $(abspath $(HERMIT_RS_PATCHES)); do git -C $(WORK)/hermit-rs apply $$p || exit 1; done
	touch $@
patched: $(WORK)/.patched

# The loader for Qemu (aarch64-elf) and for VZ (aarch64-vz, an arm64 Image).
loader: $(WORK)/.patched
	cd $(WORK)/loader && cargo +$(LOADER_TOOLCHAIN) xtask build --target aarch64-elf --release
	cd $(WORK)/loader && cargo +$(LOADER_TOOLCHAIN) xtask build --target aarch64-vz --release
	mkdir -p $(OUT)
	$(LLVM)/llvm-objcopy -O binary $(LOADER_VZ) $(LOADER_IMG)

# Upstream hello_world, and the spike's apps (apps/). Every app has the
# virtio-rng driver: without an entropy source the kernel fails closed and
# Rust's std panics before main.
apps: $(WORK)/.patched
	cd $(WORK)/hermit-rs && $(HERMIT_BUILD) -p hello_world \
		--features hermit/virtio-console,hermit/virtio-rng
	for app in hello-vz echo-vz entropy-vz vsock-vz relay-vz build-vz; do \
		(cd apps/$$app && $(HERMIT_BUILD)) || exit 1; done

# Step 0.4: the Qemu/HVF baseline from source.
qemu: loader apps
	qemu-system-aarch64 -machine virt,gic-version=3 -accel hvf -cpu host \
		-smp 1 -m 512M -display none -serial stdio -semihosting \
		-kernel $(LOADER_ELF) -device virtio-rng-pci,disable-legacy=on \
		-device guest-loader,addr=0x48000000,initrd=$(HELLO)

# The acceptance checks, both exit criteria among them (checks.sh). vz-net
# needs macOS Local Network permission for the terminal running it; vz-vsock
# does not.
checks: loader apps $(VZRUN) $(VZPAIR)
	sh checks.sh $(OUT)/checks

# --- Stock artifacts ----------------------------------------------------------

$(STOCK_LOADER):
	mkdir -p $(@D)
	gh release download $(LOADER_TAG) -R hermit-os/loader -p $(@F) -D $(@D) --clobber
	echo "$(LOADER_SHA)  $@" | shasum -a 256 -c
$(STOCK_HELLO):
	mkdir -p $(@D)
	curl -sSfL -o $@ \
		https://media.githubusercontent.com/media/hermit-os/loader/$(LOADER_TAG)/data/aarch64/hello_world
	echo "$(FIXTURE_SHA)  $@" | shasum -a 256 -c

stock: $(STOCK_LOADER) $(STOCK_HELLO)

# Step 0.4 with the stock loader and app. The guest exits by itself.
qemu-stock: stock
	mkdir -p $(OUT)/qemu
	qemu-system-aarch64 -machine virt,gic-version=3 -accel hvf -cpu host \
		-smp 1 -m 512M -display none -serial file:$(OUT)/qemu/console.log -semihosting \
		-kernel $(STOCK_LOADER) \
		-device guest-loader,addr=0x48000000,initrd=$(STOCK_HELLO)
	grep -a -E 'Hermit Loader version|Welcome to Hermit|pure Rust application' $(OUT)/qemu/console.log

# --- Stage A ------------------------------------------------------------------

# The VZ harness (runbook Step 2, option 2): vfkit refuses any arm64 kernel
# without the Image magic ("kernel must be uncompressed"), so VZ's own verdict
# needs a runner that hands the file over unchecked.
$(VZRUN): vzrun/main.swift vzrun/vzrun.entitlements
	mkdir -p $(@D)
	swiftc -O -framework Virtualization -o $@ vzrun/main.swift
	codesign -s - -f --entitlements vzrun/vzrun.entitlements $@

$(VZPAIR): vzpair/main.swift vzpair/vzpair.entitlements
	mkdir -p $(@D)
	swiftc -O -framework Virtualization -o $@ vzpair/main.swift
	codesign -s - -f --entitlements vzpair/vzpair.entitlements $@

# Stage A.2: the loader as a flat binary, and its first 64 bytes. An arm64
# Image carries the magic "ARM\x64" at offset 56.
$(OUT)/hermit-loader.bin: $(STOCK_LOADER)
	mkdir -p $(@D)
	$(LLVM)/llvm-objcopy -O binary $< $@
header: $(OUT)/hermit-loader.bin
	xxd -l 64 $<

# Stage A.1 (ELF) and A.2 (flat binary) through VZ. Both fail to start.
vz-stock: $(VZRUN) $(OUT)/hermit-loader.bin stock
	mkdir -p $(OUT)/vz-stock
	-$(VZRUN) $(STOCK_LOADER) $(STOCK_HELLO) --console $(OUT)/vz-stock/a1-elf.log --seconds 15
	-$(VZRUN) $(OUT)/hermit-loader.bin $(STOCK_HELLO) --console $(OUT)/vz-stock/a2-bin.log --seconds 15

# The boot-handoff stubs (stub/mkstub.py): each answers one question about
# VZ's Linux boot protocol by stopping cleanly (yes) or timing out (no).
$(OUT)/stub/%.Image: stub/mkstub.py
	mkdir -p $(@D)
	python3 -I stub/mkstub.py $* $@
stubs: $(VZRUN) $(STOCK_HELLO) $(foreach s,$(STUBS),$(OUT)/stub/$(s).Image)
	@for s in $(STUBS); do \
		r=$$($(VZRUN) $(OUT)/stub/$$s.Image $(STOCK_HELLO) --seconds 10 2>&1 | tail -1); \
		echo "$$s: $$r"; \
	done

# --- Stage B: the VZ machine probe --------------------------------------------

# A stock arm64 Linux kernel plus probe/init reports what VZ presents to a
# guest (device tree, memory map, virtio transport) and tests the NAT network.
$(OUT)/probe.cpio.gz: probe/init $(BUSYBOX) $(KERNEL_APK)
	rm -rf $(OUT)/probe-root && mkdir -p $(OUT)/probe-root/bin $(OUT)/probe-root/lib/modules
	tar -xzf $(KERNEL_APK) -C $(OUT)/probe-root $(KMODS) 2>/dev/null
	for m in $(KMODS); do gunzip -c $(OUT)/probe-root/$$m \
		> $(OUT)/probe-root/lib/modules/$$(basename $$m .gz); done
	rm -rf $(OUT)/probe-root/lib/modules/6.12.114-0-virt
	cp $(BUSYBOX) $(OUT)/probe-root/bin/busybox
	cp probe/init $(OUT)/probe-root/init
	chmod +x $(OUT)/probe-root/init $(OUT)/probe-root/bin/busybox
	cd $(OUT)/probe-root && find . | cpio -o -H newc 2>/dev/null | gzip -9 > ../probe.cpio.gz

# Host to guest: the guest's echo server answers a connection from this host.
# Run it from a terminal that has macOS Local Network permission.
probe: $(OUT)/probe.cpio.gz
	rm -f $(OUT)/probe.log
	vfkit --cpus 1 --memory 512 \
		--bootloader linux,kernel=$(PROBE_KERNEL),initrd=$<,cmdline="console=hvc0" \
		--device virtio-serial,logFilePath=$(abspath $(OUT))/probe.log \
		--device virtio-rng --device virtio-net,nat \
		> $(OUT)/vfkit.log 2>&1 & \
	sh probe/echo-test.sh $(OUT)/probe.log | tee $(OUT)/echo-test.log; \
	wait
	sed -n '/=== PROBE fdt-base64/,/=== PROBE fdt-end/p' $(OUT)/probe.log \
		| sed '1d;$$d' | tr -d '\r' | base64 -d > $(OUT)/vz.dtb
	dtc -I dtb -O dts -o $(OUT)/vz.dts $(OUT)/vz.dtb 2>/dev/null

# Sibling VM to relay VM over the shared NAT network (Decision 1), plus the
# client's upstream egress.
probe-sibling: $(OUT)/probe.cpio.gz
	sh probe/sibling-test.sh $(PROBE_KERNEL) $(abspath $<) $(abspath $(OUT))

clean:
	rm -rf $(OUT)
