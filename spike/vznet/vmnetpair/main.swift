// vmnetpair: boots a build VM (build-vz, static address, connects to one
// target and reports whether the echo came back) on a chosen VZ network
// attachment, optionally with a relay stand-in (echo-vz, DHCP, echoes on
// TCP 7000) on the same segment and a "far" echo-vz on VZ NAT. Used to test
// whether a segment other than the socket pair keeps the build VM away from
// everything but the relay.
//
// usage: vmnetpair <kernel> <echo-initrd> <build-initrd> --net KIND
//            --build-cmdline S [--isolate] [--subnet A.B.C.0]
//            [--relay] [--relay-ip IP] [--far] [--out DIR] [--seconds N] [--port P]
//   KIND: vmnet-host | vmnet-shared | nat
//   --isolate   disable NAT44/66, DHCP, DNS proxy and RA on the vmnet network
//   --relay     add echo-vz on the same segment (needs DHCP; --relay-ip
//               pins its lease with a DHCP reservation)
//   --far       add echo-vz on a separate VZ NAT attachment (another
//               segment on this host) and log its lease
//
// The host listens on all addresses, port P, and logs each peer: a build VM
// connection there means the host is reachable from the build segment.
// While the VMs run, the host side of every bridge is dumped to DIR.

import Foundation
import Virtualization
import vmnet

func fail(_ code: Int32, _ msg: String) -> Never {
    FileHandle.standardError.write(("vmnetpair: " + msg + "\n").data(using: .utf8)!)
    exit(code)
}

func log(_ msg: String) {
    print("vmnetpair: " + msg)
    fflush(stdout)
}

var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return v
}
func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
}
let kind = option("--net") ?? "vmnet-host"
let buildCmdline = option("--build-cmdline") ?? ""
let subnet = option("--subnet")
let relayIP = option("--relay-ip")
let outDir = option("--out") ?? "."
let seconds = Double(option("--seconds") ?? "60") ?? 60
let port = UInt16(option("--port") ?? "7100") ?? 7100
let isolate = flag("--isolate")
let withRelay = flag("--relay")
let withFar = flag("--far")
guard args.count == 3 else { fail(64, "usage: vmnetpair <kernel> <echo-initrd> <build-initrd> [options]") }

let relayMAC = "02:42:0c:00:00:01"
let buildMAC = "02:42:0c:00:00:02"
let farMAC = "02:42:0c:00:00:03"

// The build segment.
var network: vmnet_network_ref? = nil
func segment() -> VZNetworkDeviceAttachment {
    if kind == "nat" { return VZNATNetworkDeviceAttachment() }
    if network == nil {
        var st = vmnet_return_t(rawValue: 0)!
        let mode = kind == "vmnet-shared" ? operating_modes_t.VMNET_SHARED_MODE : operating_modes_t.VMNET_HOST_MODE
        guard let cfg = vmnet_network_configuration_create(mode, &st) else { fail(2, "configuration_create: \(st.rawValue)") }
        if isolate {
            vmnet_network_configuration_disable_nat44(cfg)
            vmnet_network_configuration_disable_nat66(cfg)
            vmnet_network_configuration_disable_dhcp(cfg)
            vmnet_network_configuration_disable_dns_proxy(cfg)
            vmnet_network_configuration_disable_router_advertisement(cfg)
            log("network: NAT44, NAT66, DHCP, DNS proxy, RA disabled")
        }
        if let subnet {
            var a = in_addr(), m = in_addr()
            inet_pton(AF_INET, subnet, &a)
            inet_pton(AF_INET, "255.255.255.0", &m)
            let r = vmnet_network_configuration_set_ipv4_subnet(cfg, &a, &m)
            log("network: set_ipv4_subnet \(subnet)/24 -> \(r.rawValue)")
        }
        if let relayIP {
            var a = in_addr()
            inet_pton(AF_INET, relayIP, &a)
            let mac = ether_aton(relayMAC)!.pointee
            var e = mac
            let r = vmnet_network_configuration_add_dhcp_reservation(cfg, &e, &a)
            log("network: DHCP reservation \(relayMAC) -> \(relayIP): \(r.rawValue)")
        }
        guard let net = vmnet_network_create(cfg, &st) else { fail(2, "network_create: \(st.rawValue)") }
        var sub = in_addr(), mask = in_addr()
        vmnet_network_get_ipv4_subnet(net, &sub, &mask)
        log("network: \(kind) subnet \(String(cString: inet_ntoa(sub)))/\(String(cString: inet_ntoa(mask)))")
        network = net
    }
    return VZVmnetNetworkDeviceAttachment(network: network!)
}

func machine(_ name: String, initrd: String, cmdline: String, mac: String,
             attachment: VZNetworkDeviceAttachment) -> VZVirtualMachineConfiguration {
    let boot = VZLinuxBootLoader(kernelURL: URL(fileURLWithPath: args[0]))
    boot.initialRamdiskURL = URL(fileURLWithPath: initrd)
    boot.commandLine = cmdline
    let path = "\(outDir)/\(name).console.log"
    FileManager.default.createFile(atPath: path, contents: nil)
    let serial = VZVirtioConsoleDeviceSerialPortConfiguration()
    serial.attachment = VZFileHandleSerialPortAttachment(
        fileHandleForReading: FileHandle(forReadingAtPath: "/dev/null"),
        fileHandleForWriting: FileHandle(forWritingAtPath: path)!)
    let net = VZVirtioNetworkDeviceConfiguration()
    net.attachment = attachment
    net.macAddress = VZMACAddress(string: mac)!
    let config = VZVirtualMachineConfiguration()
    config.bootLoader = boot
    config.cpuCount = 1
    config.memorySize = 512 * 1024 * 1024
    config.serialPorts = [serial]
    config.networkDevices = [net]
    config.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
    do { try config.validate() } catch { fail(2, "\(name) configuration refused: \(error)") }
    return config
}

func serveEcho() {
    let s = socket(AF_INET, SOCK_STREAM, 0)
    var on: Int32 = 1
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    addr.sin_addr.s_addr = INADDR_ANY
    let bound = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    }
    guard bound == 0, listen(s, 8) == 0 else { fail(2, "host echo: cannot listen on \(port)") }
    log("host echo server on *:\(port)")
    DispatchQueue.global().async {
        while true {
            var peer = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let c = withUnsafeMutablePointer(to: &peer) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { accept(s, $0, &len) }
            }
            if c < 0 { continue }
            log("host echo: connection from \(String(cString: inet_ntoa(peer.sin_addr)))")
            DispatchQueue.global().async {
                var buf = [UInt8](repeating: 0, count: 4096)
                while true {
                    let n = read(c, &buf, buf.count)
                    if n <= 0 { break }
                    _ = buf.withUnsafeBufferPointer { write(c, $0.baseAddress, n) }
                }
                close(c)
            }
        }
    }
}

func dumpHostSide() {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", "for i in $(ifconfig -l); do case $i in bridge1*|vmenet*) ifconfig $i;; esac; done; netstat -rn -f inet | grep -E 'bridge|Destination'; sysctl net.inet.ip.forwarding"]
    let path = "\(outDir)/host-side.txt"
    FileManager.default.createFile(atPath: path, contents: nil)
    p.standardOutput = FileHandle(forWritingAtPath: path)
    try? p.run()
    p.waitUntilExit()
    log("host side dumped to \(path)")
}

final class Watcher: NSObject, VZVirtualMachineDelegate {
    let name: String
    init(_ name: String) { self.name = name }
    func guestDidStop(_ vm: VZVirtualMachine) {
        log("\(name) stopped")
        if name == "build" { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { exit(0) } }
    }
    func virtualMachine(_ vm: VZVirtualMachine, didStopWithError error: Error) {
        fail(3, "\(name) stopped with error: \(error)")
    }
}

serveEcho()
var vms: [(String, VZVirtualMachine, Watcher)] = []
if withRelay {
    let c = machine("relay", initrd: args[1], cmdline: "", mac: relayMAC, attachment: segment())
    vms.append(("relay", VZVirtualMachine(configuration: c), Watcher("relay")))
}
if withFar {
    let c = machine("far", initrd: args[1], cmdline: "", mac: farMAC, attachment: VZNATNetworkDeviceAttachment())
    vms.append(("far", VZVirtualMachine(configuration: c), Watcher("far")))
}
let buildConfig = machine("build", initrd: args[2], cmdline: buildCmdline, mac: buildMAC, attachment: segment())
let buildVM = VZVirtualMachine(configuration: buildConfig)
let buildWatcher = Watcher("build")

for (name, vm, w) in vms {
    vm.delegate = w
    vm.start { r in if case .failure(let e) = r { fail(2, "\(name) start failed: \(e)") }; log("\(name) started") }
}
// Give the relay and far VMs time to take their leases before the build
// starts its 30 s connect loop.
DispatchQueue.main.asyncAfter(deadline: .now() + (vms.isEmpty ? 0 : 4)) {
    buildVM.delegate = buildWatcher
    buildVM.start { r in if case .failure(let e) = r { fail(2, "build start failed: \(e)") }; log("build started") }
}
DispatchQueue.global().asyncAfter(deadline: .now() + 6) { dumpHostSide() }
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
    log("timed out after \(Int(seconds))s")
    exit(4)
}
RunLoop.main.run()
