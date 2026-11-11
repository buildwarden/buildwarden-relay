# VZ networking options for the build ↔ relay link

**Question.** On Apple's Virtualization framework (VZ), can entitlements or
VZ/vmnet networking options give BuildWarden a "standard" isolated segment
between a build VM and a relay VM, like the private switch or tap the QEMU
and Hyper-V drivers use? Or is the datagram socket pair attached through
`VZFileHandleNetworkDeviceAttachment` required?

**Gate.** The build VM can reach nothing but the relay program:

- no host routing, NAT or bridging for the build segment;
- the relay VM is the only other endpoint on the segment;
- the host is unreachable from the segment, or that exposure is named.

**Host.** macOS 27.0.1 (26A434), Apple silicon, SDK `MacOSX27.0.sdk`,
Swift 6.4. Tests run as uid 501 with no sudo and no system-setting changes.
`net.inet.ip.forwarding` was already 1 on this host, and was not changed.

## Answer

**The socket pair is the only VZ option that passes the gate unchanged.**
No entitlement fixes this, Apple-granted ones included.

- **`com.apple.vm.networking`** only unlocks `VZBridgedNetworkDeviceAttachment`
  (bridged to a physical NIC). That puts the VM on the host's LAN, which is
  the opposite of isolation.
  - It is not needed for any other mode on macOS 26+.
  - Requesting it is **not worth the effort** for BuildWarden.
- **The macOS 26+ custom vmnet networks** (`vmnet_network_create` with
  `VZVmnetNetworkDeviceAttachment`) are the closest thing VZ has to a private
  switch.
  - Host mode with NAT, DHCP, DNS proxy and RA all disabled does give relay and
    build a shared L2 segment with no internet and no routing to other
    segments.
  - It needs **only `com.apple.security.virtualization`**, ad-hoc signing,
    **no root**.
  - But the **host always holds the segment's `.1` address**, and the build VM
    reached a host listener there (and via the host's LAN address). No vmnet
    API removes the host address.
- **Closing that exposure needs root**: a pf anchor on the `bridgeN`
  interface, or a privileged helper. Even then the segment is owned by
  InternetSharing, a root daemon, on a host with `ip.forwarding=1`, not by
  the warden.

## Options

| # | Option | Entitlement / root | Obtainable | Isolation verdict | Tested | Evidence |
|---|---|---|---|---|---|---|
| 0 | **Socket pair** via `VZFileHandleNetworkDeviceAttachment` (current) | `com.apple.security.virtualization` | yes, ad-hoc | **PASS**. The segment has exactly two endpoints, both owned by the warden. No host interface, address or route. | yes (prior spike) | `spike/REPORT.md` (vz-pair) |
| 1 | `VZBridgedNetworkDeviceAttachment` | `com.apple.vm.networking`, a **restricted** entitlement that needs an Apple-issued provisioning profile | Apple-managed, by DTS request; no published criteria | **FAIL**. Only bridges to physical NICs (`en8`, `en0` here), so the VM is on the LAN. Not isolatable without root-created interfaces. | partly: AMFI and validation tested; a granted entitlement can't be tested | `evidence/probe-*.log` |
| 2a | vmnet **custom host network** (`vmnet_network_create(VMNET_HOST_MODE)` → `VZVmnetNetworkDeviceAttachment`), all services disabled | `com.apple.security.virtualization` only, no root | yes, ad-hoc | **FAIL (host exposure)**. Relay and build share L2 (good); no internet, no routing to VZ NAT. But the host is `.1` on `bridgeN` and answered TCP. | yes | `evidence/t1`–`t5`, `probe-virt*.log` |
| 2b | vmnet **custom shared network** (`VMNET_SHARED_MODE`) | same as 2a | yes | **FAIL**. NAT to the internet. Shared mode with NAT, DHCP, DNS and RA disabled is refused (`VMNET_FAILURE`). | yes | `evidence/t6-shared-internet`, `probe-virt.log` |
| 2c | Legacy `vmnet_start_interface` (host, or host plus `network_identifier`) | worked with `com.apple.security.virtualization` only, no root, on 27.0.1 | yes | **FAIL**, as in 2a: the host gets an address on the bridge (`192.168.129.1`, `192.168.130.1`). It also can't attach to a VZ VM without a userspace packet pump. | interface start only | `evidence/host-side-hostmode.txt` |
| 3 | `VZNATNetworkDeviceAttachment` for both VMs | `com.apple.security.virtualization` | yes | **FAIL**. Routes to the internet, and siblings are isolated from *each other* (`PRIVATE` bridge ports), so the build can't even reach the relay directly. | yes | `evidence/t7-nat-internet`, `t8-nat-sibling` |
| 4 | Anything else in the SDK | — | — | VZ's only network attachments are NAT, Bridged, FileHandle and Vmnet (26+). vsock (`VZVirtioSocketDevice`) is not a NIC: it goes guest ↔ host process only, so it is another warden-owned pipe, like the socket pair. | header review | §SDK |

## Evidence

### 1. Bridged and `com.apple.vm.networking`

`run-probes.sh` signs the same `vmnetprobe` binary three ways, all ad-hoc
(`codesign -s - -f --entitlements`):

| Entitlements | codesign | Launch | Bridged `validate()` | vmnet custom networks |
|---|---|---|---|---|
| none | ok | ok | refused by VZ: *"doesn't have the com.apple.security.virtualization entitlement"* | `vmnet_network_create` → `VMNET_MEM_FAILURE` (all modes); legacy → `VMNET_FAILURE` |
| `virtualization` | ok | ok | refused by VZ: *"Using VZBridgedNetworkDeviceAttachment in a process that lacks the com.apple.vm.networking entitlement"* | host and shared: `VMNET_SUCCESS`; two interfaces started; legacy host: `VMNET_SUCCESS` |
| `virtualization` + `com.apple.vm.networking` | **ok** (codesign doesn't check) | **SIGKILL (exit 137)** by AMFI | — | — |

AMFI's verdict, from `amfid` in `evidence/probe-virt+vmnetworking.log`:

```
amfid: Restricted entitlements not validated, bailing out. Error ... Code=-427 "Unable to retrieve certificate chain"
amfid: Adhoc signed app with restricted entitlements detected
amfid: ... not valid: ... Code=-424 "The file is adhoc signed but contains restricted entitlements"
```

So the refusal comes from AMFI at exec, not from VZ, codesign or vmnet.
Only an Apple-issued provisioning profile that authorizes the entitlement can
make that binary launch. That would be a Developer ID-signed app-like bundle
with an embedded profile.

`VZBridgedNetworkInterface.networkInterfaces` lists only physical
interfaces (`en8` "DL-Dock", `en0` "Wi-Fi"). Making an unprivileged
host-only interface to bridge to (`feth`, `vmnet`) needs root. So even with
the entitlement, bridging can only put the VM on a real LAN. **Untested:**
actually bridging with a granted entitlement, since we have none.

### 2. vmnet custom networks (macOS 26+)

**API.** `vmnet.h` (macOS 26) adds `vmnet_network_configuration_create(mode)`
and `vmnet_network_create`.

- Modes: `VMNET_HOST_MODE` or `VMNET_SHARED_MODE`.
- Knobs: `disable_nat44`, `disable_nat66`, `disable_dhcp`, `disable_dns_proxy`,
  `disable_router_advertisement`, `set_ipv4_subnet`, `add_dhcp_reservation`,
  `set_mtu`, port forwards, `set_external_interface` (shared only).
- Cross-process sharing: `vmnet_network_copy_serialization` /
  `create_with_serialization`.
- `VZVmnetNetworkDeviceAttachment(network:)` attaches VZ VMs. Its header
  says a VM may only use a network created by the same process.

**What a run does.** `vmnetpair/main.swift` creates the network and boots up
to three VMs:

- relay stand-in: `echo-vz`, using DHCP, echoes on TCP 7000;
- build: `build-vz`, with a static address, connects to one target;
- optional "far" VM: `echo-vz` on VZ NAT.

The warden process runs an echo server on `*:7100`. Each run dumps the
host's bridges and routes while the VMs are up.

| Run | Segment | Build target | Result | Meaning |
|---|---|---|---|---|
| t1-host-relay | host mode, `10.77.0.1/24`, DHCP on (reservation for relay) | relay `10.77.0.10:7000` | **echo** | relay and build share L2 ✔ |
| t2-isolated-host-gw | host mode, `10.79.0.1/24`, NAT44/66, DHCP, DNS, RA **off** | host `10.79.0.1:7100` | **echo**; host logs `connection from 10.79.0.20` | **host reachable** ✘ |
| t4-isolated-host-lan-addr | same, `10.81.0.1/24` | host LAN addr `192.168.4.21:7100` | **echo** | host reachable on *all* its addresses via the gateway ✘ |
| t3-isolated-route-far | same, `10.82.0.1/24`, far VM on VZ NAT `192.168.64.35` | `192.168.64.35:7000` | timeout | no routing between vmnet and VZ NAT segments ✔ |
| t5-isolated-internet | same, `10.83.0.1/24` | `1.1.1.1:80` | timeout | no internet ✔ (one-way leaks to the LAN not checked; needs root tcpdump) |
| t6-shared-internet | shared mode, `10.84.0.1/24` | `1.1.1.1:80` | **HTTP 400** | NAT to the internet ✘ |

Host side, for example in `t3-isolated-route-far/host-side.txt`:

```
bridge101: inet 10.82.0.1 netmask 0xffffff00
	member: vmenet1 flags=20003<LEARNING,DISCOVER,VIRTIO>     # not PRIVATE: VMs see each other
bridge100: inet 192.168.64.1                                 # VZ NAT
	member: vmenet0 flags=20803<LEARNING,DISCOVER,PRIVATE,VIRTIO>
```

**Questions from the brief:**

- **Root or entitlement?** Neither beyond `com.apple.security.virtualization`
  (tested, ad-hoc signed, uid 501). Without that entitlement every vmnet call
  fails (`VMNET_MEM_FAILURE` / `VMNET_FAILURE`).
- **Can two VMs share an isolated segment?** Yes in host mode (t1). The
  network is private to the creating process unless it hands out a
  serialization.
- **Does the host get an address, or route it?** **Always gets an address.**
  The second address of the subnet (`.1`) is reserved for the host, and
  `bridgeN` carries it (`desc: com.apple.NetworkSharing`, flag `ROUTER4`).
  - No option disables this.
  - Routing to the internet and to the VZ NAT segment was not observed with
    NAT off (t3, t5), despite `ip.forwarding=1`.
  - Packets forwarded to the LAN without NAT can't be ruled out without root
    tcpdump.
- **Is DHCP or DNS forced?** No. DHCP, the DNS proxy and RA can each be
  disabled (t2–t5 run with all off).
  - Shared mode with all of them disabled is refused (`VMNET_FAILURE`), so shared can't
    be made host-only.

**Host exposure is concrete.** Services on this Mac listening on all
addresses include:

- ollama on `*:11434`;
- ControlCenter/AirPlay on `*:5000` and `*:7000`;
- rapportd;
- Tailscale on `*:443`.

All of these, and anything any user later starts on `0.0.0.0`, would be
reachable from a build VM on a vmnet host segment
(`evidence/host-side-hostmode.txt`). The only ways to close it are:

- a pf anchor on `bridgeN` (root);
- the application firewall (a system setting, per app, not per interface).

Neither is available to an unprivileged warden.

**Quirks found:**

- **The subnet argument is the gateway address.**
  `vmnet_network_configuration_set_ipv4_subnet` takes the *host/gateway*
  address (`10.77.0.1`), not the network address.
  - With `10.78.0.0`, `vmnet_network_create` succeeds, but the interface
    start fails inside InternetSharing: *"can't have the gateway at the subnet
    address"*, `err 49`.
  - The guest just sees link down. Evidence:
    `evidence/t0-subnet-arg-quirk/`.
  - `vmnet_network_get_ipv4_subnet` likewise reports `192.168.128.1`.
- **Released subnets come back slowly.** A subnet can't be reused for a
  moment after its process exits (`network_create` → `VMNET_FAILURE`).
- **VZ sends a config-change interrupt.** On a vmnet attachment, VZ raises a
  virtio-net config change (link status) at start.
  - The copied `echo-vz` predates link-change handling and panics
    (`not yet implemented: Implement possibility to change config on the
    fly`) when it loses the race. It did on the first t1 attempt, and not on
    the second.
  - The current `build-vz` kernel logs it and carries on. Any Hermit relay
    on vmnet needs that patch.

### 3. VZ NAT for both VMs

- t7: the build on VZ NAT reaches `1.1.1.1:80` (HTTP 400): **routes out**.
- t8: the build cannot reach a sibling on the same NAT
  (`192.168.64.35:7000` times out). The bridge ports are `PRIVATE`, which
  matches the prior spike's `sibling-bridge.txt`.

So NAT fails twice over: there's an exit, and no path to the relay. As
expected.

### SDK

All read from `$(xcrun --show-sdk-path)` (MacOSX27.0.sdk).

**Network attachments** (`Virtualization.framework/Headers/*Attachment.h`):

- `VZNATNetworkDeviceAttachment` (11.0);
- `VZBridgedNetworkDeviceAttachment` (11.0, "requires the
  com.apple.vm.networking entitlement");
- `VZFileHandleNetworkDeviceAttachment` (11.0, connected datagram socket,
  MTU 1500–65535 since 13.0);
- `VZVmnetNetworkDeviceAttachment` (26.0).

**Other `vmnet.h` keys:**

- `vmnet_enable_isolation_key` stops *interfaces* talking to each other. It
  can't be set through VZ, and it is the opposite of what is wanted.
- `vmnet_network_identifier_key` with `vmnet_host_ip_address_key` is legacy
  host-only, and the host still gets an address.

There is no way to create a host-mode network without a host address.

## What requesting the entitlement would cost, and buy

**How to get it.** `com.apple.vm.networking` ("VM Networking" capability) is
a *managed* capability. Per Apple DTS (Quinn), it is not yet on Apple's newer
managed-capability request flow. You apply by:

1. opening a **DTS code-level support request**;
2. citing the forum thread
   (<https://developer.apple.com/forums/thread/826711?answerId=888355022>)
   in "who sent you".

The entitlement page's note restricts it to developers of virtualization
software, requested through Apple.

**Criteria.** No published criteria beyond "virtualization software". The
forums report approvals are per Team ID. No timeline is given.

**If granted:**

- Signing needs a Developer ID-signed app or app-like bundle with an
  embedded provisioning profile. Ad-hoc fails, as the AMFI kill above shows.
- A CLI helper has to be wrapped in a bundle with its own App ID (DTS
  sample: a child `.app` inside `Contents/MacOS/`).
- Expect sandbox-inheritance pitfalls (DTS: "potential minefield").
- Developer and CI builds can no longer just be ad-hoc signed.

**What it buys:** only `VZBridgedNetworkDeviceAttachment`. On macOS 26+ it is
*not* needed for vmnet networks. This test and the vfkit / Code-Hex/vz
reports agree. Bridging only reaches physical NICs, so it **adds no
isolated-segment capability**.

**Verdict:** for BuildWarden's gate, requesting `com.apple.vm.networking` is
**not worth the manual effort**. Revisit only if a product need appears to
put VMs directly on a LAN.

## Recommendation for the VZ driver

1. **Keep the socket-pair build link.** It is the only VZ option where the
   warden owns both ends and nothing else, the host included, is on the
   segment.
   - It needs no Apple approval and no root, and ad-hoc signing works.
   - It is the closest analogue to the other drivers' private switch. It is
     arguably stronger, since there is no host-side interface at all.
   - Document it as a deliberate design, not a workaround.
2. **Use vmnet as a fallback only if the file-handle NIC becomes a
   bottleneck.** Others report vmnet is 2–9× faster than file-handle
   networking.
   - The fallback is a per-build `vmnet_network_create(VMNET_HOST_MODE)`
     with everything disabled.
   - Treat it as a **named host exposure** that needs a **root-installed pf
     anchor** blocking all traffic on that `bridgeN` except relay ↔ build.
     That is a privileged helper, which the VZ driver doesn't have today.
   - Also use the gateway-address form of `set_ipv4_subnet`.
   - Also patch the relay kernel for virtio-net config changes.
3. **Keep the relay's upstream on `VZNATNetworkDeviceAttachment`.** No
   change: a compromised relay reaching the internet is acceptable.
4. **Don't request `com.apple.vm.networking`.** It buys only bridged mode,
   which fails the gate.

## Is the socket pair strong enough, and can every driver use it?

This section comes from reading the native drivers at
`~/src/buildwarden-native` (`driver/vz`, `driver/qemu`, `driver/hyperv`,
`driver/firecracker`). Nothing in this section was run.

### Strength against the gate

The socket pair meets the gate *by construction*, not by configuration:

- **No host network-stack endpoint.** The link has no host interface,
  address or route. So host IP forwarding, pf, InternetSharing and the
  host's listeners are irrelevant. The vmnet tests t2 and t4 show why that
  matters: any segment the host joins exposes every `*:port` listener.
- **Exactly two endpoints.** The warden creates both descriptors, and there
  is no path, port or switch to join later.
- **One link per build.** Builds can't reach each other at layer 2.
- **No privilege.** No root and no Apple-managed entitlement are involved.

It does **not** cover:

1. **The processes holding the ends.** These are the warden, VZ's
   `com.apple.Virtualization.VirtualMachine` service, and the relay.
   - `driver/vz/network_unix.go` keeps `BuildSocketFD` open in the warden
     until `Close()` at the end of the build.
   - A warden bug that wrote to it would inject frames the ledger never saw.
   - Hardening: close the warden's copies once both consumers hold theirs.
     Test first that VZ has duplicated the descriptor by then.
2. **Other guest devices.** The link says nothing about vsock, virtio-fs,
   clipboard/SPICE or the console. `driver/vz/network.go` states these as
   rules ("no virtio-fs, no shared directory, no clipboard, no NAT", plus a
   NAT guard). They should be asserted against the actual
   `VZVirtualMachineConfiguration` before every boot: exactly one network
   device, a file-handle attachment, and no socket or directory-sharing
   devices.
3. **Threats every design shares.** These are hypervisor escape and a
   same-uid process that can debug the warden.
4. **Lost frames.** A datagram socket drops frames on buffer overflow. That
   costs reliability, not isolation: a dropped frame never leaves.

### Portability across drivers

| Driver | Build link today | Socket pair possible? | Equivalent that passes the gate |
|---|---|---|---|
| VZ | `AF_UNIX`/`SOCK_DGRAM` socket pair → `VZFileHandleNetworkDeviceAttachment` | yes (in use) | — |
| QEMU (Linux, macOS) | `-netdev stream,server=on,addr.type=unix,addr.path=<workDir>/vlan.sock` between the relay and build QEMUs (`driver/qemu/vm.go`) | **yes**: QEMU ≥ 7.2 `stream`/`dgram` netdevs accept an inherited descriptor (`addr.type=fd` / `local.type=fd`) | Today's named socket is point to point, but has a file on disk that any same-uid process could connect to before the build does. A warden-made socket pair inherited by both QEMUs removes that. |
| Firecracker (Linux) | TAP devices (`driver/firecracker/slots_linux.go`) | **no**: Firecracker's only network backend is TAP | TAP plus the host posture checks the driver runs. Isolation rests on host configuration, so it needs root/`CAP_NET_ADMIN` and a re-check per build. |
| Hyper-V (Windows) | A fresh Private vSwitch per build (`provision_local_windows.go`, `driver_windows.go`) | **no**: Hyper-V has no descriptor-backed NIC, and Windows has no `SOCK_DGRAM` socket pair | A per-build Private switch has no host vNIC, so it passes the gate. It is admin-owned host configuration, so it is re-asserted each build (the driver already does). |
| QEMU (Windows) | — | no (no `AF_UNIX` datagram socket pair) | Hyper-V or WHPX with a private switch |

**Conclusion.** The socket pair can't be the *mechanism* for every driver,
but its guarantee can be the *contract* for all of them:

> The build VM's only network device is a link whose single peer is the
> relay, with no host network-stack endpoint, created fresh for each build.

Each driver satisfies it its own way:

- VZ: socket pair;
- QEMU: inherited socket pair (a change from today);
- Hyper-V: per-build Private vSwitch;
- Firecracker: TAP plus posture checks.

**One driver-independent test suite should prove it.** The t2–t8 cases
here are the template. From the build VM, try:

- the relay: expect an answer;
- the segment's other addresses, including a host address if one exists;
- the host's LAN address;
- a sibling VM on another segment;
- a public address.

Only the relay may answer.

### Follow-ups

- **QEMU:** replace the named `vlan.sock` with a warden-created socket pair
  inherited by both QEMU processes.
- **VZ:**
  - close the warden's copies of the pair once the VMs hold theirs;
  - assert the build VM's device list before boot.
- **All drivers:** a shared build-link conformance test, as above.

## Files

- `vmnetprobe/main.swift`: asks each API (bridged validation, vmnet custom
  host/shared networks, legacy `vmnet_start_interface`) for a verdict.
  `run-probes.sh` builds three entitlement variants and collects `amfid`
  logs.
- `vmnetpair/main.swift`: boots build, relay and far VMs on a chosen segment.
  `run-pair.sh <case> …` writes `evidence/<case>/`.
- `ents/*.plist`: the three entitlement sets.
- `evidence/`: all logs cited above.
- Not committed: `guests/` (copies of `hermit-loader-vz.Image`, `build-vz`
  sha256 `e3c91aa2…`, `echo-vz` sha256 `0387bd00…`) and `bin/`.

Build:

```
swiftc -O -framework Virtualization -framework vmnet -o bin/vmnetpair vmnetpair/main.swift
codesign -s - -f --entitlements ents/virt.plist bin/vmnetpair
```

## Sources

- Apple, *com.apple.vm.networking*:
  <https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.vm.networking>
- Apple DTS on requesting the VM Networking capability:
  <https://developer.apple.com/forums/thread/826711?answerId=888355022>, and
  follow-up <https://developer.apple.com/forums/thread/854840>
- Apple DTS on helper binaries and provisioning profiles:
  <https://developer.apple.com/forums/thread/850614>
- Older DTS answer (bridged needs the entitlement):
  <https://developer.apple.com/forums/thread/656411>
- vfkit: macOS 26 vmnet without root or entitlement, and speed:
  <https://github.com/crc-org/vfkit/issues/439>
- Code-Hex/vz `VZVmnetNetworkDeviceAttachment` support:
  <https://github.com/Code-Hex/vz/pull/205>
