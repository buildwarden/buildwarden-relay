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
| Second NIC: build VM → build link → relay → NAT → host, on VZ | PASS: the host sees the relay's NAT address, never the build's (`evidence/vz-pair-*.log`) |
| Second NIC: relay not reading the link, the build reaches nothing | PASS (`evidence/vz-pair-closed-*.log`) |

`evidence/checks-summary.txt` holds the full run; all eleven checks also pass
from fresh clones of BuildWarden's Hermit forks at their `-bw.1` tags.

**Scope:** the VZ escape hatch (Decision 12) is not triggered. The VZ work is
about 170 lines of kernel changes and one new loader target, carried as
commits on BuildWarden's Hermit forks. Most of it is bound for upstream. The
deviations, carried by design, are fail-closed entropy, the packet sockets,
and the loader's VZ-only Image header and fixed link address ("Carrying the
patches" classes every commit). Two findings bind the
relay on every hypervisor, not just VZ: **Hermit has one network interface**,
and **aarch64 Hermit had no real entropy**. The follow-ups fixed both: a
virtio-rng driver that fails closed without one, and a second NIC served to
the relay app as raw frames ("The second NIC" below, prototyped VM-to-VM on
VZ). vsock works on VZ too.

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
  connection handling are fixed (kernel commit `f248077`), in
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
4. **Upstream:** a virtio-net device on `VZNATNetworkDeviceAttachment`
   (DHCP, egress and host → relay all verified), served by the kernel's
   network stack.
5. **Build link (sibling build VM ↔ relay):** a datagram socketpair that
   warden creates, one end the build VM's only NIC and the other the relay's
   second NIC (`VZFileHandleNetworkDeviceAttachment` on both). The relay
   kernel keeps that NIC from its network stack (`HERMIT_RAW_MAC`) and hands
   its frames to the relay app through a packet socket. Verified VM-to-VM
   (`vzpair/`, checks `vz-pair` and `vz-pair-closed`).

## Patches

Every change is a commit on a `bw/` branch of BuildWarden's Hermit forks,
tagged `-bw.1`, which `make` clones ("Carrying the patches"):
- the loader's, on [buildwarden/hermit-loader](https://github.com/buildwarden/hermit-loader/tree/bw/v0.5.7) `bw/v0.5.7`;
- the kernel's six (VZ boot, entropy, vsock, VZ's file handle attachment,
  packet sockets, TCP half-close, in that order), on
  [buildwarden/hermit-kernel](https://github.com/buildwarden/hermit-kernel/tree/bw/v0.13.2) `bw/v0.13.2`;
- two one-line hermit-rs commits that forward the new `virtio-rng` and
  `net-packet` features, on
  [buildwarden/hermit-rs](https://github.com/buildwarden/hermit-rs/tree/bw/hermit-0.13.2) `bw/hermit-0.13.2`.

The section headings below name each commit.

### Loader: `bd578a1`, a new `aarch64-vz` target

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

### Kernel: `58eaa91`, VZ boot

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

### Kernel: `0b0d1e3`, entropy

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

### Kernel: `f248077`, vsock connections

Hermit's vsock worked for a guest that listens; a guest that connects, or a
peer that closes, hung. On VZ, in the order the test hit them:

| # | Bug | Effect |
|---|---|---|
| 1 | `connect()` stores the peer's CID in `self.port` | The socket loses its own port |
| 2 | A `Response` marks the socket connected but neither wakes `connect()` nor records the peer's `buf_alloc` | `connect()` never returns; writes would see zero credit and block |
| 3 | `Shutdown` and `Rst` do not wake readers, and an `Rst` is answered with another | `read()` never returns 0 after the peer closes |
| 4 | A `Request` for a port nobody listens on is dropped | The peer's connect hangs instead of failing, so it cannot retry |

None is VZ-specific. Throughput was not measured: the test moves a few lines.

### Kernel: `d4c0f8c`, the build link's NIC

VZ's file handle attachment (raw frames over a datagram socket) behaves
differently from its NAT attachment in two ways, both found with the build
link:

| Symptom | Cause | Fix |
|---|---|---|
| The NIC goes dead in both directions after the first frame arrives | It sets `DEVICE_NEEDS_RESET` when a receive buffer is the 1526 bytes the spec suggests; VZ's log says "Guest buffer on the receive queue is smaller than expected". 1530 works: room for an 802.1Q tag | Post 1530-byte receive buffers |
| Kernel panic when the peer VM comes up | It reports link status changes with a configuration interrupt, which hit a `todo!()` | Log the link state; nothing the driver reads changes at run time |

The first was found by streaming the log of VZ's XPC service
(`/usr/bin/log stream --predicate 'process BEGINSWITH "com.apple.Virtualization"'`),
which names the device and the complaint. That log is the first place to look
for the next VZ device problem.

### Kernel: `2f5029d`, packet sockets

Behind a `net-packet` feature (virtio-net over PCI):

| Piece | What |
|---|---|
| Device roles at boot (`executor/device.rs`) | The virtio-net device whose MAC is `HERMIT_RAW_MAC` (`env=HERMIT_RAW_MAC=…` on the command line) goes to packet sockets and never to smoltcp. The first other device goes to the stack, as before. Any further device is left unused and logged. An unparsable `HERMIT_RAW_MAC` stops the boot |
| `socket(AF_PACKET = 5, SOCK_RAW)` (`fd/socket/packet.rs`) | One whole Ethernet frame per `read()` or `write()`, blocking or not, with `poll()`. One socket holds the device at a time (a second gets `EBUSY`) |
| Interrupts | The device's own handler acknowledges it and wakes the reader |

About 265 lines, in safe Rust apart from two one-line `unsafe` arms in the
syscall layer's `sockaddr` conversion, written like the existing arms
beside them. The device driver is the existing virtio-net driver,
unchanged: the build NIC is a second instance of it, not new driver code.

### Kernel: `62346b3`, TCP half-close

Hermit's TCP sockets could not be half-closed: `shutdown()` returned success
and did nothing, and three other paths treated a half-open connection as
closed. Not VZ-specific; found by the relay prototype, which has to pass a
build's FIN upstream and still relay the reply.

| Was | Now |
|---|---|
| `shutdown()` a no-op for every direction | `SHUT_WR` sends a FIN once the send buffer drains and keeps receiving; `SHUT_RD` makes reads return 0; `ENOTCONN` on a closed socket |
| `read()` returns `EIO` in FinWait1/FinWait2, so the reply after our FIN is lost | Reads until the buffer is empty and the peer's FIN has arrived, then 0 |
| `write()` returns 0 in CloseWait, so a server cannot answer a client that half-closed | CloseWait sends; after our own FIN, or on a closed socket, `EPIPE` |
| `poll()` reports `POLLHUP` in FinWait1/FinWait2 | Reports whether data is waiting |

`vz-pair` covers the first three rows from the client side: the build
half-closes and reads the reply to EOF, and the relay's upstream socket
does the same towards the host. The CloseWait write (a Hermit server
answering after the client's FIN) is not exercised by any check yet.

### Boot tracing (debugging only)

`patches/loader-vz-checkpoints.patch` and `patches/kernel-vz-tracing-wip.patch`
are the tools that found the kernel bugs, on a machine where the guest cannot
print. Applied by hand on top of the fork checkouts, they turn bootargs into one-bit
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
| File handle NIC | raw frames, no padding, over the datagram socket; offers no `CSUM`; receive buffers of at least 1530 bytes; a configuration interrupt when the link comes up | |

## Findings for M3 and beyond (not VZ-specific)

1. **One NIC (prototyped in the follow-up).** Hermit's network stack takes a
   single global `NETWORK_DEVICE` into one smoltcp `Interface`. The relay
   needs two: the build link and upstream. Rather than make the stack
   multi-homed, the packet-socket patch keeps the build NIC out of the
   kernel's stack altogether and gives its raw frames to the relay app ("The
   second NIC").
2. **No real entropy on aarch64 (fixed in the follow-up).** `seed_entropy()`
   is a stub returning `None` there, and the kernel had no virtio-rng driver.
   `sys_read_entropy`, which promises cryptographically secure bytes, then
   fell back silently to a 31-bit Park–Miller–Lehmer generator seeded from the
   boot timestamp. Any TLS key a relay generated on aarch64 Hermit was
   effectively guessable. Now: a virtio-rng driver (VZ, Qemu and Firecracker
   all offer the device; VZ's is `00:06.0`) and failing closed
   (kernel commit `0b0d1e3`). `RNDR` where the CPU has it is still
   to do; no Mac guest has it today.
3. **Packed virtqueues** do not work on VZ (patch row 9); split queues do.
   Unexplained; worth an upstream issue before relying on packed rings.
4. **vsock connections** from the guest, and peers closing, hung (four bugs,
   fixed in kernel commit `f248077`). Its throughput is unknown;
   the driver busy-polls and moves 8 KiB packets.
5. Upstream nightly `nightly-2026-11-01` builds a loader that hangs
   mid-print on Qemu; `nightly-2026-08-15` (near the loader release) works.
6. **Hermit's TCP could not half-close (fixed in the follow-up).**
   `shutdown()` was a no-op, a half-closed socket could not read its reply,
   and a server could not answer a client that had half-closed
   (kernel commit `62346b3`).
7. **`connect_timeout` does not time out** while the gateway's ARP goes
   unanswered (seen in `vz-pair-closed`: the build's 1-second connects never
   returned). Harmless for the relay, which only dials out over NAT, but an
   upstream bug.

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
| NIC 2 | Relay and build VMs over a socketpair (`vzpair`) | Device roles by MAC worked first time; the relay then panicked on the link-up interrupt, and the link NIC went dead on the first frame. VZ's own log named the receive buffer size; with 1530-byte buffers the round trip passes |

## Judgement calls made unattended

1. **Location:** `spike/` on branch `spike/vz-hermit` in
   `buildwarden/buildwarden-relay`, with a draft PR. Clones of
   BuildWarden's Hermit forks and the stock downloads go in `spike/.work/`
   (git-ignored). The changes started here as patch files; since
   2026-11-11 they are commits on the forks' `bw/` branches ("Carrying the
   patches"). Nothing has been sent upstream to hermit-os (Question 3).
2. **Toolchains:** hermit-rs's pinned nightly for apps; a second, older
   nightly for the loader (see finding 4). Both are pinned in the Makefile.
3. **Stock artifacts** (the loader release binary and its LFS test fixture,
   sha256-pinned) for the unpatched attempts; they run only as guests.
4. **Linux probe guest** built from the main repo's `relay-vm` kernel,
   modules and busybox, to measure VZ without Hermit.
5. **The kernel is consumed via `HERMIT_MANIFEST_DIR`** (the hermit crate's
   hook for an out-of-tree kernel), so hermit-rs needs no change to find it.
   hermit-rs carries only the two commits that forward new kernel features.
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
12. **The build NIC is picked by MAC, not by device order.** Warden sets
    every MAC, so this is deterministic, and the check lists the link NIC
    first to prove order does not matter. Anything unexpected fails closed:
    a bad `HERMIT_RAW_MAC` stops the boot, and a third NIC is never used.
13. **Packet socket ABI:** `AF_PACKET` is 5, Hermit's next free family
    number (Hermit's are not Linux's: its `AF_INET` is 3). The spike's relay
    app defines the constants itself rather than patching `hermit-abi`.
14. **The relay prototype is minimal on purpose:** one thread polling every
    millisecond, a listener created per port as each SYN arrives, TCP only,
    and a blocking upstream dial. It dials once a build connection reaches
    Established or CloseWait, since a build that sends and half-closes at
    once is already in CloseWait when the relay looks. It proves the path, not the relay's
    design. The fixes tried while finding the buffer size (header and frame
    in one descriptor, indirect descriptors, filling RX after `DRIVER_OK`,
    padding short frames) did not help and are not in the patches.

## Questions for you

1. ~~The relay's second NIC on Hermit.~~ Answered 2026-11-08: a compromised
   relay reaching the internet is expected; the guarantee is that nothing
   bypasses the relay. Two NICs, prototyped here ("The second NIC").
2. ~~Entropy.~~ Answered 2026-11-07: in scope; done here.
3. **Upstreaming.** With the fork (Decision 18), the relay no longer waits
   on upstream, but each submission still needs your approval. May I open
   issues and PRs on `hermit-os/kernel` (the upstream-bound commits in
   "Carrying the patches", and issues for the packed rings and
   `connect_timeout`) and `hermit-os/loader` (`aarch64-vz`, ideally as a
   PIE loader)? Deviations are offered only if you want them to be.
4. ~~Warden's Local Network permission versus vsock.~~ Answered 2026-11-07:
   vsock for the host ↔ relay interface, now working.

## The second NIC

The requirement (Jeff, 2026-11-08): the build environment cannot reach the
outside at all, and all of its traffic goes through the relay. The relay
itself reaching the internet is expected; the protection is a small relay
and a network that cannot route around it. So the relay has two NICs, and
the prototype is built so that nothing but the relay app can carry a byte
from one to the other:

```
build VM                      relay VM                                host
 eth0 ──── socketpair ──── NIC 1 (HERMIT_RAW_MAC) ── packet socket ─┐
 (only NIC,                     kernel stack never sees it          │
  no NAT,                                                       relay app:
  no vsock)                                                     own smoltcp,
                                                                any address
                               NIC 2 ── kernel smoltcp ── TCP ──────┘
                               (VZ NAT, DHCP) ─────────────────────────► internet
```

- **Outside the relay**, warden creates the socketpair and gives the build VM
  that one NIC: no NAT device, no socket device. Its only peer is the relay's
  NIC 1, so a misconfigured build VM has nowhere else to send a frame.
- **Inside the relay**, build frames never reach the kernel's network stack.
  The packet socket hands them to the relay app, whose own smoltcp
  instance answers for every destination address (`any_ip`), terminates
  each TCP connection and dials the same destination through the kernel's
  stack on NIC 2. The kernel has no path between the devices: smoltcp does
  not forward, and the build device is never registered with it. With the
  relay app not reading the link, the build reaches nothing
  (`vz-pair-closed`), so the kernel itself answers nothing, not even ARP.
- **Memory safety** is the same as Hermit's existing networking: both NICs
  run the same virtio-net driver, and the new kernel code is safe Rust apart
  from two `sockaddr` conversion arms. On Hermit's single address space that
  is the whole boundary, so the relay's own code should stay free of
  `unsafe` too. The prototype's four `unsafe` calls are raw `hermit-abi`
  syscalls, for a safe wrapper type to hold.

What `vz-pair` shows: the build (`10.0.9.2`, gateway `10.0.9.1`) connects to
`192.168.64.1:47100`, the host's NAT address. The relay accepts the
connection for that foreign address, dials it from its own lease, and the
host's echo server logs the relay's NAT address as the peer. The build
sends 14 bytes and half-closes; the relay passes the FIN upstream, the host
echoes and closes, and the build reads the 14 bytes back to EOF.

The size came in under the estimate: about 265 kernel lines (packet sockets)
plus 16 (the file-handle fixes), against 500–800 estimated. The relay app is
about 300 lines.

Open before the real relay:
- **UDP/DNS:** the prototype relays TCP only. DNS from the build would need
  the relay to answer it. (Half-close works, after the shutdown patch: the
  relay passes the build's FIN upstream and relays the reply until the
  upstream's own FIN.)
- **Throughput:** the relay app polls every millisecond and copies each frame
  twice. Not measured.
- **Other hypervisors:** the packet socket is generic virtio-net. The 1530-byte
  buffer is harmless elsewhere, but the build link's form (a socketpair on
  VZ, a tap or socket netdev on Qemu) is per driver.

## Carrying the patches

Decided 2026-11-08 (kickoff "Hermit fork", Decision 18): BuildWarden forks
Hermit's kernel, loader and hermit-rs into the `buildwarden` GitHub org. The
fork is both the base for upstream PRs and the home of deliberate
deviations. Done 2026-11-11:

| Fork | Branch | Tag the Makefile pins |
|---|---|---|
| [buildwarden/hermit-kernel](https://github.com/buildwarden/hermit-kernel) | `bw/v0.13.2` | `v0.13.2-bw.1` |
| [buildwarden/hermit-loader](https://github.com/buildwarden/hermit-loader) | `bw/v0.5.7` | `v0.5.7-bw.1` |
| [buildwarden/hermit-rs](https://github.com/buildwarden/hermit-rs) | `bw/hermit-0.13.2` | `hermit-0.13.2-bw.1` |

Each branch's `CARRIED.md` classes every commit:

| Commit | Class |
|---|---|
| Loader `bd578a1`, the `aarch64-vz` target | Deviation until split: the generic parts (`x0`, the device tree copy, the null console) go upstream on their own; the image header and fixed link address stay until a position-independent loader replaces them |
| Kernel `58eaa91`, VZ boot | Upstream-bound |
| Kernel `0b0d1e3`, entropy | Deviation (fail-closed entropy). The driver itself may still be offered upstream |
| Kernel `f248077`, vsock | Upstream-bound |
| Kernel `d4c0f8c`, file handle NIC | Upstream-bound |
| Kernel `2f5029d`, packet sockets | Deviation (the relay's build link) |
| Kernel `62346b3`, TCP half-close | Upstream-bound |
| hermit-rs `4fc4125`, `e417545`, feature forwards | Follow their kernel commits: deviations |

The forks replace the patch files the spike used to apply. `patches/` now
holds only the boot-tracing tools. The kernel is still built from the
checkout named by `HERMIT_MANIFEST_DIR`, so the fork changed only where the
Makefile clones from and which tags it pins.

## Files

| Path | What |
|---|---|
| `Makefile` | `make checks` builds everything from the fork tags and runs the checks; `stock`, `vz-stock`, `stubs`, `probe`, `probe-sibling` rerun the earlier experiments |
| `checks.sh` | The eleven checks |
| `patches/` | The boot-tracing patches, applied by hand on top of the fork checkouts |
| `apps/` | `hello-vz` (Stage A), `echo-vz` (Stage B), `entropy-vz`, `vsock-vz`, `relay-vz` and `build-vz` (the second NIC) |
| `vzpair/` | Swift runner for the relay and build VMs joined by a socketpair, with a host echo server as the destination |
| `vzrun/` | Swift VZ runner (Linux boot loader, virtio console to a file, NAT, optional fixed MAC, entropy device unless `--no-rng`, vsock test with `--vsock`) |
| `vz-trace.sh` | Boot tracing driver |
| `stub/mkstub.py` | Boot-protocol stub images |
| `probe/` | Linux probe guest: init, host echo test, sibling test |
| `evidence/` | VZ device tree, probe logs, bridge state, console logs, check results |
