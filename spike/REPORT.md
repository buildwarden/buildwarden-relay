# VZ spike report: Hermit on Apple Virtualization (M0)

Run 2026-11-07 on the MacBook (Apple silicon, macOS 27.0.1), unattended, by
Claude against `VZ Spike Runbook — Hermit on Apple Virtualization.md`. Pins:
Hermit `hermit-0.13.2` / kernel `v0.13.2`, loader `v0.5.7`, toolchain
`nightly-2026-02-01` (Decision 17; all in the Makefile's top block).

## Verdict

**Stock Hermit does not boot on VZ, and the gap is larger than the runbook's
two items, but every piece of it is small, local and understood.** No exit
criterion is met yet: building patched Hermit was blocked in this session (see
[What could not run](#what-could-not-run)). Everything on the VZ side of the
boundary was measured directly instead, so the patch list below is the full
list against a known machine, not a guess.

- **Stage A:** five loader gaps and three kernel gaps, listed in
  [the patch list](#stage-a-patch-list). The runbook's app-handoff gap is
  already closed upstream. Estimate: a few days of loader and kernel work, with
  nothing that needs the EFI route. The VZ escape hatch (Decision 12) is
  **not** triggered on this evidence.
- **Stage B:** VZ presents virtio over **PCI, not MMIO**, which Hermit's
  default `pci` feature already matches. DHCP, DNS and TCP/ICMP egress work
  over VZ NAT. **Sibling VMs cannot reach each other over VZ NAT** (layer-2
  isolation, measured). That makes NAT alone insufficient for Decision 1;
  see [Is NAT enough?](#is-nat-enough).
- **Beyond VZ, for M3:** stock Hermit has **one network interface** and **no
  entropy source on aarch64**. Both bind the relay on every hypervisor, not
  just VZ.

## Attempts

| # | Attempt | Outcome |
|---|---|---|
| 0.1 | Toolchain | rustup (Homebrew) + `nightly-2026-02-01` with `rust-src`, `llvm-tools`; QEMU 11.1.1 present; vfkit 0.6.4 installed. |
| 0.2–0.3 | Build loader and `hello_world` from source | **Blocked**: the session's permission policy refused to run the upstream build (`cargo xtask` / `build.rs` count as executing external code). Not attempted further. |
| 0.4 | QEMU/HVF baseline, **stock** release loader v0.5.7 + the loader repo's `hello_world` test fixture (LFS, sha256-pinned) | **Pass.** Loader banner, `Welcome to Hermit 0.6.9`, "A pure Rust application is running on top of Hermit!", clean exit. `evidence/qemu-baseline.log`. Note the fixture's kernel is 0.6.9, not the 0.13.2 pin. |
| A.1 | Loader ELF as VZ kernel (vfkit) | vfkit refuses before VZ: `kernel must be uncompressed, … is a compressed file` (it treats any arm64 file without the Image magic as compressed). |
| A.1 | Loader ELF as VZ kernel (`vzrun`, the Swift harness) | `VZErrorDomain Code=1 "The virtual machine failed to start." (Internal Virtualization error)`. |
| A.2 | `objcopy -O binary` loader (vfkit / `vzrun`) | First 64 bytes are rodata; **no `ARM\x64` magic at offset 56**, and `_start` is at `0x40415e38`, not offset 0. vfkit: same refusal. `vzrun`: same `Internal Virtualization error`. |
| A.3 | Arm64 Image header | Not applied to the loader (needs a build). Verified on VZ with hand-built header stubs instead (next rows). |
| stub `control` | Minimal valid Image header + PSCI `SYSTEM_OFF` | **Guest stopped cleanly**: VZ accepts a 64-byte-header Image, runs it, and PSCI over `hvc` works. |
| stub `spin` | Header + WFE loop (negative control) | Timed out, as it should. |
| stub `dtb` | Power off iff `[x0]` holds the FDT magic | **Stopped**: VZ passes the DTB pointer in **x0** (Linux protocol). |
| stub `ecam` | Same test at `0x40000000`, where the stock loader reads the DTB | **Timed out**: no FDT there. On VZ that address is the PCI ECAM window. |
| stub `pc` | Power off iff the code runs at `0x7xxxxxxx` | **Stopped**: VZ loads the image in its RAM at `0x70000000+`. |
| stub `uart` | One 32-bit store to `0x09000000` (QEMU virt's PL011), then power off | **VM dies**: `Internal Virtualization error`, 3/3 runs. A store to an unbacked MMIO address is fatal on VZ. This also makes A.1/A.2's identical error ambiguous: VZ may have loaded those files and the garbage at offset 0 faulted. |
| A.4–A.5 | Console check, initrd handoff, Hello World on VZ | Not reached (needs the patched loader). |
| B (Linux probe) | Stock arm64 Linux (`relay-vm`'s Alpine `Image`) + `probe/init`, under vfkit NAT | Device tree, memory map and transport captured (`evidence/vz.dts`, `evidence/probe-host.log`). Lease `192.168.64.x/24` from `192.168.64.1`, lease 3600 s, DNS `192.168.64.1`. |
| B.3 host→guest | `nc` from the host to the guest's echo server | **Untested**: every LAN address, the home router included, is `No route to host` from this session. That's macOS Local Network privacy on the app running the session, not VZ. **Needs one run from your Terminal** (below). |
| B sibling | Second probe VM connects to the first over NAT | **Fails at layer 2**: ARP for the peer stays `INCOMPLETE`. Both `vmenet` ports sit on `bridge100` flagged **`PRIVATE`**, so the bridge does not forward between them (`evidence/sibling-bridge.txt`, `evidence/sibling-client.log`). |
| B egress | Guest → internet through NAT | **Works**: ICMP to 1.1.1.1, DNS via 192.168.64.1, HTTP fetch of example.com. |
| B Hermit | Hermit networking demo under VZ | Not reached (needs Stage A). |

## The VZ machine, as a guest sees it

From `evidence/vz.dts` (VZ's own device tree, read back through
`/sys/firmware/fdt`) and `/proc/iomem`, 1 vCPU, 512 MB:

| Thing | VZ | QEMU `virt` (what Hermit assumes) |
|---|---|---|
| RAM base | `0x7000_0000` | `0x4000_0000` |
| `0x4000_0000` | PCI ECAM (`pci-host-ecam-generic`, 256 MB) | RAM; QEMU puts the DTB here for ELF kernels |
| DTB location | passed in `x0`, near the top of RAM | `0x4000_0000` |
| Kernel load | RAM base + `text_offset` (`0x7000_0000` for Linux) | ELF segments at their link address |
| UART | **none** (no PL011 node, no `stdout-path`) | PL011 at `0x0900_0000` |
| Console | virtio-console over PCI (`hvc0`) | PL011 |
| Virtio transport | **PCI**: net `00:01.0`, console `00:05.0`, rng `00:06.0`; BARs in the 64-bit window at `0x1_0000_0000` | MMIO or PCI |
| GIC | GICv3, GICD `0x1000_0000`, GICR `0x1001_0000` | GICv3 |
| PSCI | 0.2 via `hvc` | same |
| `/chosen` | `bootargs`, `kaslr-seed`, `linux,initrd-start/end` | `module@` nodes from `guest-loader` |
| CPU `rng` (FEAT_RNG) | **absent** | host-dependent |
| Other | PL031 RTC, PL061 GPIO (power key) | |

## Stage A patch list

### Loader (`hermit-os/loader`, aarch64)

| # | Gap | Evidence | Patch |
|---|---|---|---|
| L1 | No arm64 Image header | A.2 `xxd`; stub `control` | Put the 64-byte header at the start of the flat image (`b` past it, `text_offset 0`, `image_size`, flags `0b1010`, magic at 56) and make `_start` follow it. About 20 lines of asm plus a linker-script section at the front. Upstreamable. |
| L2 | DTB read from a hardcoded `0x4000_0000` (`DEVICE_TREE`), and `entry.s` clobbers `x0` on its second instruction | stubs `dtb`, `ecam`; `src/arch/aarch64/{entry.s,mod.rs}` | Save `x0` in `_start` before anything else and use it for every `Fdt::from_ptr`. Keep `0x4000_0000` only as a QEMU fallback when `x0` is 0. Small; upstreamable (it's the Linux boot protocol). |
| L3 | Statically linked at `0x4040_0000` (`-Crelocation-model=static`, `--image-base`) | ELF headers; stub `pc` | Either build PIE and self-apply `R_AARCH64_RELATIVE` at entry (about 50 lines, any load address, upstreamable), or link at `0x7000_0000` for a VZ-only build (trivial, not upstreamable). Recommend PIE. |
| L4 | Console is PL011 or Xilinx only, falling back to `0x0900_0000` when the DT names none | stub `uart` (fatal on VZ); `src/arch/aarch64/console.rs` | When the DT has no `stdout-path` and no `arm,pl011`, use a null console instead of the fallback address. The loader is then silent on VZ, and `boot_info.serial_port_base` must be `None` for the kernel (K1). A virtio-console in the loader is not worth it. |
| L5 | App via `/chosen linux,initrd-*` | `src/fdt_ext.rs` `find_linux_initrd` | **Already upstream** (`find_kernel` falls back to it). The runbook's second gap is closed, provided L2 lets the loader find the DT. |

### Kernel (`hermit-os/kernel`, aarch64)

| # | Gap | Evidence | Patch |
|---|---|---|---|
| K1 | Early console is PL011 at `serial_port_base`, which the loader always sets (`0x1000` → UART) | `src/arch/aarch64/kernel/serial.rs`, `src/console.rs` | Make the UART device optional when `serial_port_base` is `None`: drop output until virtio-console attaches, or buffer and replay it. Small. |
| K2 | virtio-console is not a default feature | `Cargo.toml` | Build with `virtio-console` (it already supports PCI and replaces the UART once up). Config only. |
| K3 | `seed_entropy()` returns `None` on aarch64, so `getrandom` returns `ENOSYS`; no virtio-rng driver exists | `src/arch/aarch64/kernel/processor.rs`, `src/entropy.rs`, `src/drivers/` | A virtio-rng PCI driver modeled on the console driver (one queue, about 200–300 lines), seeding the ChaCha pool; optionally `RNDR` where FEAT_RNG exists (not on VZ). **Needed on every aarch64 target**, QEMU included. Without it, TLS keys and HashMap seeds have no entropy. Upstreamable. |

Already fine on VZ from the source: GICv3 and PSCI come from the DT; PCI ECAM
generic is supported and VZ's `ranges` supply the IO, mem32 and mem64 windows
its asserts need; virtio-net, virtio-console and virtio-vsock all have PCI
transports, and `pci` is a default feature. So the runbook's "set the
transport feature to MMIO" step is unnecessary: stock is already right.

## Is NAT enough?

**No, not for Decision 1 as written (host plus sibling build VMs). NAT is
enough for the relay's upstream egress, and probably for host→relay, but VZ
NAT isolates VMs from each other.**

- **Sibling → relay over NAT: impossible on this macOS.** Each VM's `vmenet`
  port on `bridge100` is `PRIVATE`; ARP between them never completes. A
  port forward does not help, because VZ NAT has no port-forward API and the
  block is layer 2.
- **Host → relay over NAT: very likely works, unverified.** Guests reach the
  host's bridge address (ping to `192.168.64.1` succeeds), and the isolation
  is between members only. The test couldn't run from this session because
  of Local Network privacy. That same privacy gate applies to `warden`: a
  claim over NAT needs Local Network permission for whatever launches warden.
  That's a risk for the nightly launchd agent, which can't answer the prompt.
- **Relay → internet over NAT: works** (DHCP, DNS, ICMP, TCP measured).
- **Bridged networking is not needed**, and no entitlement beyond
  `com.apple.security.virtualization` is.

### Recommended VZ path for `relay-hermit`

Keep each link where VZ already supports it, without NAT between VMs:

1. **Build link (build VM ↔ relay VM): a file-handle socketpair**, exactly as
   the vz driver does today for the host relay. Warden creates the pair and
   gives one end to each VM's `VZFileHandleNetworkDeviceAttachment`. No NAT,
   no entitlement, no Local Network permission. (Not tested VM-to-VM here.)
2. **Claim and collector (warden → relay): virtio-vsock**, not NAT. Hermit
   already ships a virtio-vsock PCI driver with a listener example
   (`VsockListener::bind`), the same shape as the claim (the relay listens,
   the host dials, the relay never dials out). VZ's `VZVirtioSocketDevice` is
   virtio-vsock over PCI. So the kickoff's Stage C ("new driver work, 1–2
   weeks") is probably "verify an existing driver on VZ": days. It also
   removes the Local Network permission problem. NAT host→guest stays the
   fallback if the vsock driver doesn't hold up.
3. **Upstream (relay → internet): VZ NAT.** Verified.

This needs the relay to have **two network interfaces**, the build link and
upstream, and stock Hermit has one (next section).

## Findings that reach past VZ (input to M3)

1. **Hermit drives a single NIC.** One global `NETWORK_DEVICE` is taken
   into one smoltcp `Interface` (`src/executor/{device,network}.rs`), and
   sockets bind to that NIC. Today's relay VM uses two (`relay-vm/init`:
   `eth0` build link, `eth1` upstream), and in host mode the Go relay reads
   raw Ethernet frames off the build link. Neither fits stock Hermit on any
   hypervisor (Firecracker and QEMU too). Options: a multi-NIC kernel patch
   (moderate; smoltcp itself supports several interfaces), giving the relay
   app raw-frame access to a second virtio-net device, or a different
   topology (for example upstream carried over vsock by a host-side dialer,
   which changes who opens upstream connections). **This is a design
   decision for you, not the spike** (Question 1).
2. **No entropy on aarch64 Hermit** (K3). This blocks TLS on any aarch64
   host.
3. **Hermit's MMIO probing walks `/virtio_mmio` nodes only** and its vsock
   driver is PCI-only. Neither matters on VZ (PCI everywhere), but both
   matter for Firecracker on aarch64 (MMIO).

## What could not run

- **Building Hermit (loader and app) from source.** The session's permission
  policy blocks running upstream build scripts. To get past this, allow it,
  or run `make loader hello qemu` yourself. The Makefile and the patch list
  are ready for it.
- **Host→guest TCP.** This session's app lacks macOS Local Network
  permission. From a Terminal that has it:

  ```bash
  cd ~/src/buildwarden-relay/spike && make probe && cat out/echo-test.log
  ```

  `echo-test: … got 'echo-test …'` matching what was sent means host→guest
  works over plain NAT.

## Judgement calls made unattended

1. **Spike location**: `spike/` on branch `spike/vz-hermit` in
   `buildwarden/buildwarden-relay` (the repo was empty apart from its
   template). Upstream checkouts and downloads go in `spike/.work/`
   (git-ignored), never committed.
2. **Build-std over `rust-std-hermit`**: the template now uses a stable
   toolchain plus a prebuilt Hermit std installed by a downloaded script. I
   kept the runbook's `-Zbuild-std` on hermit-rs's pinned nightly instead, so
   nothing downloaded runs on the host.
3. **Stock release artifacts where the build was blocked**: the loader
   v0.5.7 release binary (`gh release download`) and its `hello_world` test
   fixture (Git LFS), both sha256-pinned in the Makefile. They run only as
   guests inside QEMU/VZ.
4. **A Linux probe guest** to measure VZ's machine model, using the main
   repo's own `relay-vm` kernel, modules and busybox, plus a probe init
   written here. The runbook says "verify, do not assume"; this verifies the
   VZ side without needing Hermit.
5. **Hand-built Image stubs** (`stub/mkstub.py`, A64 hand-encoded and checked
   with `llvm-objdump`) to test the boot protocol where the patched loader
   would have.
6. **The Swift harness (`vzrun/`) was written** because vfkit refuses
   non-Image kernels (the runbook's Option 2 trigger). It is ad-hoc signed
   with the ordinary virtualization entitlement and kept as the future VZ
   test runner, per the runbook.
7. **Two sandbox escapes** for host-network tests only (ping/nc to the vmnet
   bridge and the VM runs that use it), to tell the session sandbox apart
   from Local Network privacy. They showed it was the latter.
8. **Stopped at the runbook's boundaries**: no vsock work, no relay code,
   no bridged networking, no entitlement requests. No upstream patches were
   written, because they couldn't be built or tested here.

## Questions for you

1. **Relay topology on Hermit** (from the single-NIC finding): multi-NIC
   kernel patch, raw-frame second NIC, or a different upstream path? This
   decides M3's scope on every hypervisor, so it's worth settling before M3.
2. **Decision 1 revisited**: sibling build VMs can't reach a relay over VZ
   NAT. Is the socketpair build link (as today) the intended sibling path?
   And is vsock acceptable as the claim and collector transport on VZ? It
   would be the one place the Rust relay's transport differs from the claim
   over TCP (GLOBAL-08's seam is the protocol, not the transport, but worth
   your call).
3. **Unblock the build**: allow upstream builds in an unattended session, or
   run `make loader hello qemu` and the Stage A patches by hand?

## Next steps to close the exit criteria

1. Build from source (`make loader hello qemu`); confirm the baseline on the
   0.13.2 kernel.
2. Loader branch with L1–L4; kernel branch with K1–K2 (and K3 if Stage B
   needs DHCP randomness). Then rerun `vz-stock` with the patched loader and
   `--cmdline` empty: exit criterion A.
3. `hermit-rs` networking demo (`examples/testtcp` or `httpd`), default `pci`
   feature, under `vzrun` with NAT; `make probe` from Terminal for host→guest:
   exit criterion B. Then the vsock example under VZ, recording only whether
   it works (no driver work, per the runbook).

## Files

| Path | What |
|---|---|
| `Makefile` | Every step above; `make all` reruns everything runnable here. |
| `vzrun/` | Swift VZ runner and its entitlements. |
| `stub/mkstub.py` | Boot-protocol stub images. |
| `probe/` | Linux probe init, host echo test, sibling test. |
| `evidence/` | Captured device tree, probe logs, bridge state, QEMU baseline. |
