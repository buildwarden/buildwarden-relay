# VZ spike report: Hermit on Apple Virtualization (M0)

Run 2026-11-07 on the MacBook (Apple silicon, macOS 27.0.1) against
`VZ Spike Runbook — Hermit on Apple Virtualization.md`, unattended under
Jeff's standing authority. Pins (Decision 17, all in the Makefile's top
block): Hermit `hermit-0.13.2`, kernel `v0.13.2`, loader `v0.5.7`, toolchains
`nightly-2026-02-01` (Hermit apps) and `nightly-2026-08-15` (loader).

## Verdict

**Both exit criteria are met, with patches.** Hermit 0.13.2 boots on VZ
through `VZLinuxBootLoader`, prints Hello World over VZ's virtio console, takes
a DHCP lease on VZ NAT, and answers a TCP connection from the host. Upstream
Hermit does neither: the loader needs a VZ boot target, and the kernel needs
nine fixes, each found and proven on VZ.

| Check (`make checks`) | Result |
|---|---|
| A: Hello World on VZ's virtio console | **PASS**: `Hello World from Hermit on VZ!` (`evidence/vz-hello-console.log`) |
| B: DHCP on VZ NAT, then host → guest TCP | **PASS**: lease `192.168.64.x` from `192.168.64.1`, host echo round trip, **no port forward** (`evidence/vz-net-console.log`) |
| Regression: Qemu virt, PL011 console | PASS |
| Regression: Qemu virt, modern virtio-console | PASS |
| Regression: Qemu virt, modern virtio-net, TCP echo | PASS |

`evidence/checks-summary.txt` holds the full run; the same five checks also
pass from fresh clones (the patches apply cleanly to the pinned tags).

**Scope:** the VZ escape hatch (Decision 12) is not triggered. The VZ work is
a patch set of about 170 lines of kernel changes and one new loader target,
all upstreamable except the loader's fixed link address. Two findings bind the
relay on every hypervisor, not just VZ: **Hermit has one network interface**,
and **aarch64 Hermit has no real entropy**. Those, not VZ, set the size of M3.

## Answers the kickoff is waiting on

- **Is NAT enough?** For the relay's upstream and for host → relay, **yes**.
  The host reaches the guest's NAT address directly, with no port forward.
  For sibling build VM → relay, **no**: VZ NAT isolates VMs from each other at
  layer 2 (each VM's port on `bridge100` is `PRIVATE`; ARP between two VMs
  never completes; `evidence/sibling-*.txt`). Bridged networking is not
  needed. Recommended path below.
- **Is vsock needed?** Not for reachability: host → relay works over NAT.
  vsock would remove one constraint: warden's process needs macOS Local
  Network permission to reach the NAT address. Hermit already ships a
  virtio-vsock PCI driver (`drivers/vsock`, with a listener example), so if
  it is wanted it is "test the existing driver on VZ", not new driver work.
  It was not tested here (runbook: no vsock work).
- **Is an EFI wrapper needed?** No. The loader boots directly as an arm64
  Linux Image.
- **MMIO or PCI?** PCI. VZ puts every virtio device on a
  `pci-host-ecam-generic` bus, which Hermit's default `pci` feature already
  matches.

## Recommended VZ path for `relay-hermit`

1. **Boot:** the loader's `aarch64-vz` target (an arm64 Image), with the
   relay as the initrd, booted by `VZLinuxBootLoader`. `vzrun/` is the
   harness, kept for the VZ test runner.
2. **Upstream and claim:** one virtio-net device on `VZNATNetworkDeviceAttachment`
   (DHCP, egress and host → relay all verified). Warden claims the relay at
   its NAT address; warden's terminal or agent needs Local Network permission.
3. **Build link (sibling build VM ↔ relay):** a file-handle socketpair
   between the two VMs (`VZFileHandleNetworkDeviceAttachment`), as the main
   repo's vz driver does today for its host relay. Not tested VM-to-VM here.
   It needs a **second NIC in the relay**, which stock Hermit cannot drive
   (finding 1 below), so this item depends on Question 1.

## Patches

All four patches are in `patches/`. `make patched` applies the two fix
patches to fresh clones.

### Loader: `patches/loader-v0.5.7-vz.patch`, a new `aarch64-vz` target

| Gap | Fix |
|---|---|
| No arm64 Image header; VZ refuses the ELF and the flat binary | `head.s`: the 64-byte header (branch, `image_size` including `.bss`, flags, `ARM\x64`); `link-vz.ld` places it first at `0x7000_0000` |
| Linked at `0x4040_0000`, which on VZ is the PCI ECAM window | `link-vz.ld` links at VZ's RAM base; the page tables' identity map follows `RAM_START` (`0x7000_0000` under the `vz` feature) |
| DTB hardcoded at `0x4000_0000`, and `entry.s` clobbers `x0` | `entry.s` saves `x0` (the Linux protocol's DTB pointer) first thing |
| The kernel reads the DTB in place, and VZ's sits near the top of RAM, unmapped and unreserved | The loader copies the DTB to just below the kernel: mapped, and inside the region the kernel reserves |
| Console falls back to PL011 `0x0900_0000`; one store there kills a VZ VM | A null console when the DT names no UART and has no PL011; the kernel then gets no serial port |
| App via `/chosen linux,initrd-*` | Already upstream (`find_linux_initrd`) |

The generic parts (`x0`, DTB copy, null console) also run on Qemu, where they
pass the regression checks. The fixed link address is VZ-only; a PIE loader
that relocates itself would serve both targets and is the upstreamable form.

### Kernel: `patches/kernel-v0.13.2-vz.patch`

Each fix was needed on VZ. They are listed in the order the boot hit them:

| # | Symptom on VZ | Cause | Fix |
|---|---|---|---|
| 1 | Silent hang right after the loader | `processor::configure` writes PMU registers; VZ exposes no PMU, so the access is UNDEFINED | Skip when `ID_AA64DFR0_EL1.PMUVer` is 0 or 0xF |
| 2 | Panic in memory init | `env::is_uefi` calls `fdt.root().compatible()`, which unwraps; VZ's root node has no `compatible` | Read it fallibly |
| 3 | Panic in interrupt init | GIC found by Qemu's node name `/intc`; VZ names it `gic` | Find by `compatible` (`arm,gic-v3`/`v4`) |
| 4 | Any print faults (no UART) | The kernel always builds a PL011 from `serial_port_base` | No UART when the loader passes none; output goes to a 16 KiB early buffer |
| 5 | Early boot log lost | The console driver is unreachable (`PCI_DRIVERS` not finalized) while PCI init runs | Buffer until the virtio console can write, then replay |
| 6 | Panic on replay | A write of 8 KiB or more trips `send_packet`'s size assertion (an upstream bug on every platform) | Short writes of one packet; `write_all` loops |
| 7 | **Console and net queues configured, kicked, never used** | Hermit does not wait after resetting a virtio device. VZ resets asynchronously, so the late reset discards the queue setup | Wait for `device_status` to read 0, as the spec requires (v1.2 §4.1.4.3.2). Bisected: without it the console stays silent |
| 8 | virtio-net rejected (`NoDevCfg`) | VZ's net device config is 17 of 24 bytes (only offered features' fields); Hermit demands the full struct | Accept a short config when the BAR holds the struct |
| 9 | virtio-net `FEATURES_OK` refused | VZ refuses `CSUM` without `GUEST_CSUM` (Hermit can't do `GUEST_CSUM`), and requires `MTU` (Hermit asks for it) | Retry once without `CSUM`. Also stop requesting `RING_PACKED`: VZ never uses Hermit's packed queues (split queues work). The root cause is open, on Hermit's or VZ's side |

### Boot tracing (debugging only)

`patches/loader-vz-checkpoints.patch` and `patches/kernel-vz-tracing-wip.patch`
are the tools that found the kernel bugs, on a machine where the guest cannot
print. Applied on top of the fix patches, they turn bootargs into one-bit
questions answered by whether the guest powers off (PSCI `SYSTEM_OFF`) or
times out:
- `vzstop=N`: did boot reach checkpoint N?
- `vzhold`: turns a normal shutdown into a spin, so only an answer stops the VM.
- `vzpl=K` / `vzpf=SUB`: panic line bit K / panic file contains SUB.
- `vzbit=K`: device feature bit K.
- `vznetfeat=MASK`: override the requested net features.

`vz-trace.sh` drives them. The tracing patch is a work-in-progress snapshot
with dead ends in it; it is not meant to be merged.

## What VZ looks like to a guest

From VZ's own device tree (`evidence/vz.dts`), `/proc/iomem` and PCI config
dumps, captured with a Linux probe guest (`probe/`):

| Thing | VZ | Qemu `virt` (Hermit's assumptions) |
|---|---|---|
| RAM | `0x7000_0000` | `0x4000_0000` |
| `0x4000_0000` | PCI ECAM, 256 MB | RAM; DTB for ELF kernels |
| DTB | in `x0`, near the top of RAM, no `/memreserve/` | `0x4000_0000` |
| Root node | no `compatible`; `apple,virtualization-generic-platform` in a child | `linux,dummy-virt` |
| UART | none; a store to an unbacked address stops the VM | PL011 `0x0900_0000` |
| GIC | GICv3 node `gic`, GICD `0x1000_0000`, no ITS | node `intc` |
| PMU | none | present |
| Virtio | PCI; the regions in 64-bit BAR0 (common, ISR `+0x1000`, notify `+0x4000` with multiplier 4, device `+0x8000`); MSI-X table in BAR2; INTx | MMIO or PCI |
| virtio-console features | `INDIRECT_DESC EVENT_IDX VERSION_1 RING_PACKED`, no `MULTIPORT` | |
| virtio-net features | `CSUM GUEST_CSUM MTU MAC GUEST_TSO4/6 HOST_TSO4/6 STATUS INDIRECT_DESC EVENT_IDX VERSION_1 RING_PACKED` | |
| Reset | asynchronous | synchronous |
| CPU `rng` (FEAT_RNG) | absent | host-dependent |
| NAT | `192.168.64.0/24` via `bridge100`; `PRIVATE` member ports; DHCP and DNS on `.1` | |

## Findings for M3 and beyond (not VZ-specific)

1. **One NIC.** Hermit's network stack takes a single global
   `NETWORK_DEVICE` into one smoltcp `Interface`, and sockets bind to it
   implicitly. The relay needs two: the build link and upstream (the main
   repo's `relay-vm/init` uses `eth0` and `eth1`). In host mode the Go relay
   also reads raw Ethernet frames off the build link. Neither fits stock
   Hermit on any hypervisor. This is a design decision (Question 1).
2. **No real entropy on aarch64.** `seed_entropy()` is a stub returning
   `None` there, and the kernel has no virtio-rng driver. `sys_read_entropy`,
   which promises cryptographically secure bytes, then falls back silently to
   a 31-bit Park–Miller–Lehmer generator seeded from the boot timestamp. The
   only sign is the log line `Unable to read entropy! Fallback to a naive
   implementation!`. Any TLS key a relay generates on aarch64 Hermit is
   effectively guessable. Needed: a virtio-rng driver (VZ, Qemu and
   Firecracker all offer the device; VZ's is `00:06.0`), `RNDR` where the CPU
   has it, and a fallback that fails closed. Upstreamable.
3. **Packed virtqueues** do not work on VZ (patch row 9); split queues do.
   Unexplained; worth an upstream issue before relying on packed rings.
4. Upstream nightly `nightly-2026-11-01` builds a loader that hangs
   mid-print on Qemu; `nightly-2026-08-15` (near the loader release) works.

## Attempts, in order

| # | Attempt | Outcome |
|---|---|---|
| 0 | Qemu/HVF baseline, stock loader + stock app | Pass (`evidence/qemu-baseline.log`) |
| 0 | Qemu/HVF baseline from source | Pass with `nightly-2026-08-15` for the loader; hang with `nightly-2026-11-01` |
| A.1/A.2 | Stock loader ELF / flat binary on VZ | vfkit refuses both ("kernel must be uncompressed"); VZ via `vzrun`: `Internal Virtualization error` |
| A stubs | Hand-built Image stubs (`stub/`) | VZ accepts a minimal header; DTB in `x0`; code runs at `0x7xxxxxxx`; `0x4000_0000` holds no FDT; a PL011 store kills the VM |
| A.3–A.4 | Patched loader on VZ | Loader runs end to end (checkpoints 1–8); kernel then hits fixes 1–6 in turn |
| A.5 | Console silent with the kernel booting fully | Probed the device: status `0xF`, features, notify address, command register `0x6`: all correct. VZ never consumed a descriptor. Bisected to the missing reset wait (fix 7) |
| B | virtio-net on VZ | Fixes 8 and 9, then packed queues dead; on split queues, DHCP lease and host → guest echo |
| B (Linux) | Linux probe on VZ NAT | DHCP, DNS, ICMP and TCP egress work; sibling VMs isolated at layer 2 |

## Judgement calls made unattended

1. **Location:** `spike/` on branch `spike/vz-hermit` in
   `buildwarden/buildwarden-relay`, with a draft PR. Upstream clones and
   downloads go in `spike/.work/` (git-ignored); the changes to them are
   committed here as patches. Nothing has been sent upstream to hermit-os
   (Question 3).
2. **Toolchains:** hermit-rs's pinned nightly for apps; a second, older
   nightly for the loader (see finding 4). Both are pinned in the Makefile.
3. **Stock artifacts** (the loader release binary and its LFS test fixture,
   sha256-pinned) for the unpatched attempts; they run only as guests.
4. **Linux probe guest** built from the main repo's `relay-vm` kernel,
   modules and busybox, to measure VZ without Hermit.
5. **The kernel is consumed via `HERMIT_MANIFEST_DIR`** (the hermit crate's
   hook for an out-of-tree kernel), so hermit-rs itself is unmodified.
6. **Two own apps** (`apps/hello-vz`, `apps/echo-vz`) in place of upstream
   examples. `hello-vz` waits before exiting; `echo-vz` is the 20-line echo
   server from the runbook.
7. **Removed what did not help:** speculative changes (an explicit MSI-X
   vector, packed rings for the console, always writing `queue_size`,
   filling RX after `DRIVER_OK`) were tested, did not help, and are not in
   the fix patch. The two that are bisect-proven unnecessary are noted here
   so nobody re-adds them as the fix.
8. **Sandbox:** host-network tests (pings, `nc` to the NAT address, the VZ
   runs that use them) ran outside this session's sandbox, after you allowed
   Local Network access.
9. **Stopped at the runbook's boundaries:** no relay code, no vsock work, no
   bridged networking, no entitlement requests. The private VZ GDB stub was
   tried for debugging and refused (it needs a private entitlement); it is
   not used.

## Questions for you

1. **The relay's second NIC on Hermit.** Options: patch the kernel for
   several interfaces (moderate; smoltcp supports it, Hermit's socket layer
   assumes one); expose a second virtio-net device to the relay as raw
   frames; or change the topology, for example carrying upstream over vsock
   through a host-side dialer, which changes who opens upstream connections.
   This sets M3's scope on every hypervisor.
2. **Entropy.** Is a virtio-rng driver plus a fail-closed fallback in M3's
   scope, ahead of anything that does TLS on aarch64?
3. **Upstreaming.** May I open issues and PRs on `hermit-os/kernel`
   (fixes 1–9 and the entropy and packed-ring issues) and `hermit-os/loader`
   (`aarch64-vz`, ideally as a PIE loader)? Until they land, the patches stay
   here (see "Carrying the patches").
4. **Warden's Local Network permission** for claiming over NAT, versus vsock
   for the claim. The nightly launchd agent cannot answer the macOS prompt.

## Carrying the patches

No GitHub fork of Hermit is needed to use them. The kernel is built by the
`hermit` crate from any checkout named by `HERMIT_MANIFEST_DIR`. The loader
is a separate binary the relay image ships anyway. A pinned tag plus a patch
file per component (as here) keeps Decision 17's one-place version bump. If
upstream is slow, the next step up is a `buildwarden/hermit-kernel` branch
consumed through Cargo's `[patch]`. Still no long-lived fork.

## Files

| Path | What |
|---|---|
| `Makefile` | `make checks` builds everything from the pinned tags plus patches and runs the checks; `stock`, `vz-stock`, `stubs`, `probe`, `probe-sibling` rerun the earlier experiments |
| `checks.sh` | The five checks |
| `patches/` | Loader and kernel fixes; boot-tracing patches |
| `apps/` | `hello-vz` (Stage A), `echo-vz` (Stage B) |
| `vzrun/` | Swift VZ runner (Linux boot loader, virtio console to a file, NAT, optional fixed MAC) |
| `vz-trace.sh` | Boot tracing driver |
| `stub/mkstub.py` | Boot-protocol stub images |
| `probe/` | Linux probe guest: init, host echo test, sibling test |
| `evidence/` | VZ device tree, probe logs, bridge state, console logs, check results |
