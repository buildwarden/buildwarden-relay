// vmnetprobe: asks each VZ / vmnet networking API whether this process may
// use it, and records who refuses (VZ validation, vmnet status, or the kernel
// killing the process at launch). Built three times with different
// entitlements (see run-probes.sh); the output is the evidence.
//
// usage: vmnetprobe [--hold N]
//   --hold N  keep networks and interfaces up N seconds so the host side
//             (ifconfig, netstat) can be inspected from outside.

import Foundation
import Virtualization
import vmnet

func log(_ msg: String) {
    print(msg)
    fflush(stdout)
}

let statusNames: [UInt32: String] = [
    1000: "VMNET_SUCCESS", 1001: "VMNET_FAILURE", 1002: "VMNET_MEM_FAILURE",
    1003: "VMNET_INVALID_ARGUMENT", 1004: "VMNET_SETUP_INCOMPLETE",
    1005: "VMNET_INVALID_ACCESS", 1006: "VMNET_PACKET_TOO_BIG",
    1007: "VMNET_BUFFER_EXHAUSTED", 1008: "VMNET_TOO_MANY_PACKETS",
    1009: "VMNET_SHARING_SERVICE_BUSY", 1010: "VMNET_NOT_AUTHORIZED",
]
func name(_ s: vmnet_return_t) -> String { statusNames[s.rawValue] ?? "status \(s.rawValue)" }

var args = Array(CommandLine.arguments.dropFirst())
var hold = 0.0
if let i = args.firstIndex(of: "--hold"), i + 1 < args.count { hold = Double(args[i + 1]) ?? 0 }

var keep: [AnyObject] = []
var keepNetworks: [vmnet_network_ref] = []
var keepIfaces: [interface_ref] = []

// --- vmnet custom networks (macOS 26) ---------------------------------------

func custom(_ label: String, _ mode: vmnet_mode_t, isolate: Bool,
            subnet: String? = nil, startInterfaces: Int = 0) {
    var st = vmnet_return_t(rawValue: 0)!
    guard let cfg = vmnet_network_configuration_create(mode, &st) else {
        log("custom[\(label)] configuration_create: \(name(st))")
        return
    }
    if isolate {
        vmnet_network_configuration_disable_nat44(cfg)
        vmnet_network_configuration_disable_nat66(cfg)
        vmnet_network_configuration_disable_dhcp(cfg)
        vmnet_network_configuration_disable_dns_proxy(cfg)
        vmnet_network_configuration_disable_router_advertisement(cfg)
    }
    if let subnet {
        var a = in_addr(), m = in_addr()
        inet_pton(AF_INET, subnet, &a)
        inet_pton(AF_INET, "255.255.255.0", &m)
        log("custom[\(label)] set_ipv4_subnet \(subnet)/24: \(name(vmnet_network_configuration_set_ipv4_subnet(cfg, &a, &m)))")
    }
    guard let net = vmnet_network_create(cfg, &st) else {
        log("custom[\(label)] network_create: \(name(st))")
        return
    }
    var sub = in_addr(), mask = in_addr()
    vmnet_network_get_ipv4_subnet(net, &sub, &mask)
    log("custom[\(label)] network_create: \(name(st)) subnet \(String(cString: inet_ntoa(sub)))/\(String(cString: inet_ntoa(mask)))")
    keepNetworks.append(net)

    // Can VZ take it?
    let att = VZVmnetNetworkDeviceAttachment(network: net)
    keep.append(att)
    log("custom[\(label)] VZVmnetNetworkDeviceAttachment: created")

    for n in 0..<startInterfaces {
        let desc = xpc_dictionary_create(nil, nil, 0)
        let done = DispatchSemaphore(value: 0)
        let iface = vmnet_interface_start_with_network(net, desc, DispatchQueue.global()) { s, params in
            var extra = ""
            if let p = params {
                for k in [vmnet_mac_address_key, vmnet_mtu_key, vmnet_start_address_key, vmnet_subnet_mask_key] {
                    if let v = xpc_dictionary_get_value(p, k) { extra += " \(String(cString: k))=\(String(cString: xpc_copy_description(v)))" }
                }
            }
            log("custom[\(label)] interface \(n) start: \(name(s))\(extra)")
            done.signal()
        }
        if iface == nil { log("custom[\(label)] interface \(n) start: returned NULL") }
        _ = done.wait(timeout: .now() + 10)
        if let iface { keepIfaces.append(iface) }
    }
}

// --- legacy vmnet_start_interface ------------------------------------------

func legacy(_ label: String, _ build: (xpc_object_t) -> Void) {
    let desc = xpc_dictionary_create(nil, nil, 0)
    build(desc)
    let done = DispatchSemaphore(value: 0)
    let iface = vmnet_start_interface(desc, DispatchQueue.global()) { s, _ in
        log("legacy[\(label)] start_interface: \(name(s))")
        done.signal()
    }
    if iface == nil { log("legacy[\(label)] start_interface: returned NULL") }
    if done.wait(timeout: .now() + 10) == .timedOut { log("legacy[\(label)] no completion in 10s") }
    if let iface { keepIfaces.append(iface) }
}

// --- VZ bridged ------------------------------------------------------------

func bridged() {
    let ifs = VZBridgedNetworkInterface.networkInterfaces
    log("bridged: networkInterfaces = [\(ifs.map { "\($0.identifier)(\($0.localizedDisplayName ?? "-"))" }.joined(separator: ", "))]")
    guard let first = ifs.first else { return }
    let net = VZVirtioNetworkDeviceConfiguration()
    net.attachment = VZBridgedNetworkDeviceAttachment(interface: first)
    let cfg = VZVirtualMachineConfiguration()
    cfg.bootLoader = VZLinuxBootLoader(kernelURL: URL(fileURLWithPath: "/dev/null"))
    cfg.networkDevices = [net]
    do {
        try cfg.validate()
        log("bridged: validate() accepted")
    } catch {
        log("bridged: validate() refused: \(error)")
    }
}

log("pid \(getpid()) uid \(getuid())")
bridged()
custom("host-default", operating_modes_t.VMNET_HOST_MODE, isolate: false)
custom("host-isolated", operating_modes_t.VMNET_HOST_MODE, isolate: true, subnet: "10.77.0.0", startInterfaces: 2)
custom("shared-default", operating_modes_t.VMNET_SHARED_MODE, isolate: false)
custom("shared-nat-off", operating_modes_t.VMNET_SHARED_MODE, isolate: true)
legacy("host") { xpc_dictionary_set_uint64($0, vmnet_operation_mode_key, UInt64(operating_modes_t.VMNET_HOST_MODE.rawValue)) }
legacy("host+network_identifier") {
    xpc_dictionary_set_uint64($0, vmnet_operation_mode_key, UInt64(operating_modes_t.VMNET_HOST_MODE.rawValue))
    var u = UUID().uuid
    let d = $0
    withUnsafeBytes(of: &u) { xpc_dictionary_set_uuid(d, vmnet_network_identifier_key, $0.bindMemory(to: UInt8.self).baseAddress!) }
}
if hold > 0 {
    log("holding \(Int(hold))s")
    Thread.sleep(forTimeInterval: hold)
}
log("done")
