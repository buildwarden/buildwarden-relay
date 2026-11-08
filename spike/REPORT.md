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
| Follow-up: entropy from virtio-rng on Qemu | PASS |
| Follow-up: entropy from virtio-rng on VZ, two boots differ | PASS |
| Follow-up: no entropy device on VZ, the kernel fails closed | PASS |
| Follow-up: vsock on VZ, guest → host and host → guest | PASS, inside this session's sandbox (no Local Network access) |

`evidence/checks-summary.txt` holds the full run; all nine checks also pass
from fresh clones (the patches apply cleanly to the pinned tags).

**Scope:** the VZ escape hatch (Decision 12) is not triggered. The VZ work is
a patch set of about 170 lines of kernel changes and one new loader target,
all upstreamable except the loader's fixed link address. Two findings bind the
relay on every hypervisor, not just VZ: **Hermit has one network interface**,
and **aarch64 Hermit had no real entropy**. The follow-up fixed the second (a
virtio-rng driver, failing closed without one) and made vsock work on VZ; the
first is open ("The second NIC" below) and sets the size of M3.

## Answers the kickoff is waiting on

- **Is NAT enough?** For the relay's upstream and for host → relay, **yes**.
  The host reaches the guest's NAT address directly, with no port forward.
  For sibling build VM → relay, **no**: VZ NAT isolates VMs from each other at
  layer 2 (each VM's port on `bridge100` is `PRIVATE`; ARP between two VMs
  never completes; `evidence/sibling-*.txt`). Bridged networking is not
  needed. Recommended path below.
- **Is vsock needed?** Not for reachability: host → relay works over NAT.
  But vsock removes a constraint and narrows the interface, so the follow-up
  tested it: Hermit's virtio-vsock driver works on VZ once four bugs in its
  connection handling are fixed (`patches/kernel-v0.13.2-vsock.patch`), in
  both directions. It needs no Local Network permission: the host end is a
  file descriptor VZ hands to the process that owns the VM, not a socket on
  the host's network stack, and the check passes inside this session's
  sandbox, which blocks the NAT address. Nothing else on the host can reach
  it, and VZ offers no guest-to-guest vsock, so it is exactly a warden ↔
  relay channel.
- **Is an EFI wrapper needed?** No. The loader boots directly as an arm64
  Linux Image.
- **MMIO or PCI?** PCI. VZ puts every virtio device on a
  `pci-host-ecam-generic` bus, which Hermit's default `pci` feature already
  matches.

## Recommended VZ path for `relay-hermit`

1. **Boot:** the loader's `aarch64-vz` target (an arm64 Image), with the
   relay as the initrd, booted by `VZLinuxBootLoader`. `vzrun/` is the
   harness, kept for the VZ test runner.
2. **Claim and collector:** virtio-vsock between warden and the relay (both
   directions verified), so warden needs no Local Network permission.
3. **Entropy:** a virtio entropy device on every relay VM; the kernel refuses
   to produce random data without one.
4. **Upstream:** one virtio-net device on `VZNATNetworkDeviceAttachment`
   (DHCP, egress and host → relay all verified), unless upstream moves to
   vsock too ("The second NIC" below).
5. **Build link (sibling build VM ↔ relay):** a file-handle socketpair
   between the two VMs (`VZFileHandleNetworkDeviceAttachment`), as the main
   repo's vz driver does today for its host relay. Not tested VM-to-VM here.
   It needs a **second NIC in the relay**, which stock Hermit cannot drive
   (finding 1 below), so this item depends on Question 1.

## Patches

All patches are in `patches/`. `make patched` applies the fix patches to
fresh clones: the loader's, the kernel's three (VZ boot, entropy, vsock, in
that order) and a one-line hermit-rs patch that forwards the new
`virtio-rng` feature.

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

### Kernel: `patches/kernel-v0.13.2-rng.patch`, entropy

| Change | Why |
|---|---|
| A virtio entropy (virtio-rng) PCI driver, `drivers/rng`, behind a `virtio-rng` feature | aarch64 `seed_entropy()` returns `None`, and Hermit had no other source |
| The ChaCha pool seeds from the processor, then from the device | x86-64 keeps `RDSEED` first; VZ exposes no `FEAT_RNG` (`RNDR`) on an M5 Max, so the device is the only source there |
| `sys_read_entropy` returns its error when there is no source | It used to return Park–Miller–Lehmer bytes seeded from the boot timer, silently |
| smoltcp's `random_seed` comes from the pool, with the wall clock as a logged last resort | It was the boot time in seconds, so TCP initial sequence numbers and ephemeral ports were guessable |

Failing closed has a sharp edge: Rust's std reads entropy before `main` on
Hermit, so a std app without a source now panics at start-up. The message is
misleading (a slice index out of range), because std's `fill_bytes` treats
only `-1` as failure while the kernel returns `-ENOSYS`; that is a small
upstream fix in std. The kernel logs `No entropy source` first. Every spike
app now has the driver, and every Qemu check has a `virtio-rng-pci` device.

### Kernel: `patches/kernel-v0.13.2-vsock.patch`, vsock connections

Hermit's vsock worked for a guest that listens; a guest that connects, or a
peer that closes, hung. On VZ, in the order the test hit them:

| # | Bug | Effect |
|---|---|---|
| 1 | `connect()` stores the peer's CID in `self.port` | The socket loses its own port |
| 2 | A `Response` marks the socket connected but neither wakes `connect()` nor records the peer's `buf_alloc` | `connect()` never returns; writes would see zero credit and block |
| 3 | `Shutdown` and `Rst` do not wake readers, and an `Rst` is answered with another | `read()` never returns 0 after the peer closes |
| 4 | A `Request` for a port nobody listens on is dropped | The peer's connect hangs instead of failing, so it cannot retry |

None is VZ-specific. Throughput was not measured: the test moves a few lines.

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
2. **No real entropy on aarch64 (fixed in the follow-up).** `seed_entropy()`
   is a stub returning `None` there, and the kernel had no virtio-rng driver.
   `sys_read_entropy`, which promises cryptographically secure bytes, then
   fell back silently to a 31-bit Park–Miller–Lehmer generator seeded from the
   boot timestamp. Any TLS key a relay generated on aarch64 Hermit was
   effectively guessable. Now: a virtio-rng driver (VZ, Qemu and Firecracker
   all offer the device; VZ's is `00:06.0`) and failing closed
   (`patches/kernel-v0.13.2-rng.patch`). `RNDR` where the CPU has it is still
   to do; no Mac guest has it today.
3. **Packed virtqueues** do not work on VZ (patch row 9); split queues do.
   Unexplained; worth an upstream issue before relying on packed rings.
4. **vsock connections** from the guest, and peers closing, hung (four bugs,
   fixed in `patches/kernel-v0.13.2-vsock.patch`). Its throughput is unknown;
   the driver busy-polls and moves 8 KiB packets.
5. Upstream nightly `nightly-2026-11-01` builds a loader that hangs
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
9. **Stopped at the runbook's boundaries:** no relay code, no bridged
   networking, no entitlement requests. The private VZ GDB stub was tried for
   debugging and refused (it needs a private entitlement); it is not used.
   vsock was out of scope for the spike and tested afterwards at your request.
10. **Entropy fails closed unconditionally**, not behind a feature. That is
    right for the relay. Upstream may want the weak fallback kept as an
    opt-in, since aarch64 users without a virtio-rng device now get a panic.
11. **The rng driver polls** its queue and only acknowledges interrupts, since
    seeding is rare and synchronous. It sits outside `PCI_DRIVERS`, whose
    interrupt dispatch has a `todo!()` for unknown drivers.

## Questions for you

1. **The relay's second NIC on Hermit.** See "The second NIC" for the
   options, weighed against the rule that the build environment reaches
   nothing but the relay. This sets M3's scope on every hypervisor.
2. ~~Entropy.~~ Answered 2026-11-07: in scope; done here.
3. **Upstreaming.** May I open issues and PRs on `hermit-os/kernel`
   (fixes 1–9, the entropy driver, the vsock fixes and the packed-ring issue)
   and `hermit-os/loader`
   (`aarch64-vz`, ideally as a PIE loader)? Until they land, the patches stay
   here (see "Carrying the patches").
4. ~~Warden's Local Network permission versus vsock.~~ Answered 2026-11-07:
   vsock for the host ↔ relay interface, now working.

## The second NIC

The requirement: the build VM reaches nothing but the relay, and every byte
it receives passes through the relay. Two facts narrow the options:

- **Hermit's network stack cannot forward.** smoltcp terminates traffic and
  never routes between interfaces, so a two-NIC relay cannot leak build
  traffic onto the upstream path by misconfiguration. Only the relay app can
  carry bytes across.
- **The build side may need raw frames, not sockets.** The Go relay reads raw
  Ethernet frames off the build link, so it can answer for any destination
  address. Hermit's in-kernel sockets only accept connections to the relay's
  own address. Unless the build VM is pointed at the relay explicitly (proxy
  settings, DNS), the relay needs raw frames on the build NIC whatever it
  does upstream.

| Option | Build VM's reach | Relay's reach | Hermit work | Main cost |
|---|---|---|---|---|
| **A. Two NICs:** build socketpair + VZ NAT | relay only | the whole internet via NAT | Several devices, and raw frames on one (moderate–large: `NETWORK_DEVICE` and the socket layer assume one) | A compromised relay, which parses untrusted build traffic, has unrestricted egress |
| **B. One NIC + vsock upstream:** build socketpair; the relay asks a host dialer in warden to open each upstream connection | relay only | the build VM and warden's dialer, nothing else | Raw frames on the one NIC; vsock is done | A new host-side dialer; vsock throughput unproven; upstream connections come from the host, not the VM |
| C. Host-side switch: one NIC to warden, which also plays gateway | relay, enforced by warden's frame filter | via warden's gateway | none | The build VM shares an L2 segment with an internet gateway: one filter bug is a leak. Rejected |
| D. Build traffic over vsock | — | — | — | VZ has no guest-to-guest vsock, so the host would carry build frames. Rejected |

**Recommendation: B.** It is the only option where a compromised relay still
cannot reach the internet freely. The dialer enforces the egress policy a
second time, outside the guest. It also drops the NAT device and its DHCP,
and needs the least kernel work, since vsock now works. The ledger is
unchanged: the relay still sees and records every byte before it goes
upstream. What to prove next: vsock throughput on VZ under a realistic
download, and whether the build NIC needs raw frames (the relay design's
call). vsock also differs by hypervisor: Qemu uses vhost-vsock (Linux hosts),
and Firecracker maps it to a Unix socket.

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
| `checks.sh` | The nine checks |
| `patches/` | Loader, kernel (VZ, entropy, vsock) and hermit-rs fixes; boot-tracing patches |
| `apps/` | `hello-vz` (Stage A), `echo-vz` (Stage B), `entropy-vz`, `vsock-vz` |
| `vzrun/` | Swift VZ runner (Linux boot loader, virtio console to a file, NAT, optional fixed MAC, entropy device unless `--no-rng`, vsock test with `--vsock`) |
| `vz-trace.sh` | Boot tracing driver |
| `stub/mkstub.py` | Boot-protocol stub images |
| `probe/` | Linux probe guest: init, host echo test, sibling test |
| `evidence/` | VZ device tree, probe logs, bridge state, console logs, check results |
