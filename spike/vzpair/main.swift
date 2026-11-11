// vzpair: boots a relay VM and a build VM joined by a build link, for the
// two-NIC prototype.
//
// The build link is a datagram socket pair this process creates: one end is
// the relay's first NIC, the other the build's only NIC, so the build reaches
// nothing but the relay. The relay's second NIC is on VZ NAT. The link NIC
// comes first in the relay's device list, so the relay kernel must pick it
// out by MAC (HERMIT_RAW_MAC), not by order. The host plays the internet: a
// TCP echo server on all addresses, port P, that logs each peer.
//
// usage: vzpair <kernel> <relay-initrd> <build-initrd> [--relay-cmdline S]
//               [--build-cmdline S] [--relay-console FILE] [--build-console FILE]
//               [--seconds N] [--port P]
//
// Exit status: 0 the build VM stopped, 2 VZ refused a configuration, 3 a
// guest errored, 4 timed out.

import Foundation
import Virtualization

func fail(_ code: Int32, _ msg: String) -> Never {
    FileHandle.standardError.write(("vzpair: " + msg + "\n").data(using: .utf8)!)
    exit(code)
}

func log(_ msg: String) {
    print("vzpair: " + msg)
    fflush(stdout)
}

var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return v
}
let relayCmdline = option("--relay-cmdline") ?? ""
let buildCmdline = option("--build-cmdline") ?? ""
let relayConsole = option("--relay-console")
let buildConsole = option("--build-console")
let seconds = Double(option("--seconds") ?? "60") ?? 60
let port = UInt16(option("--port") ?? "7100") ?? 7100
guard args.count == 3 else {
    fail(64, "usage: vzpair <kernel> <relay-initrd> <build-initrd> [options]")
}

let relayLinkMAC = "02:42:0b:00:00:01"
let buildLinkMAC = "02:42:0b:00:00:02"
let relayNatMAC = "02:42:0b:00:00:03"

// The build link. Apple asks for a receive buffer at least four times the
// send buffer on these sockets.
var pair: [Int32] = [0, 0]
guard socketpair(AF_UNIX, SOCK_DGRAM, 0, &pair) == 0 else { fail(2, "socketpair failed") }
for fd in pair {
    var snd: Int32 = 256 * 1024
    var rcv: Int32 = 1024 * 1024
    setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &snd, socklen_t(MemoryLayout<Int32>.size))
    setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &rcv, socklen_t(MemoryLayout<Int32>.size))
}

func nic(_ mac: String, _ attachment: VZNetworkDeviceAttachment) -> VZVirtioNetworkDeviceConfiguration {
    let net = VZVirtioNetworkDeviceConfiguration()
    net.attachment = attachment
    net.macAddress = VZMACAddress(string: mac)!
    return net
}

func linkNIC(_ mac: String, _ fd: Int32) -> VZVirtioNetworkDeviceConfiguration {
    nic(mac, VZFileHandleNetworkDeviceAttachment(
        fileHandle: FileHandle(fileDescriptor: fd, closeOnDealloc: false)))
}

func machine(
    initrd: String, cmdline: String, console: String?, nics: [VZVirtioNetworkDeviceConfiguration]
) -> VZVirtualMachineConfiguration {
    let boot = VZLinuxBootLoader(kernelURL: URL(fileURLWithPath: args[0]))
    boot.initialRamdiskURL = URL(fileURLWithPath: initrd)
    boot.commandLine = cmdline

    let out: FileHandle
    if let path = console {
        FileManager.default.createFile(atPath: path, contents: nil)
        out = FileHandle(forWritingAtPath: path)!
    } else {
        out = FileHandle.standardOutput
    }
    let serial = VZVirtioConsoleDeviceSerialPortConfiguration()
    serial.attachment = VZFileHandleSerialPortAttachment(
        fileHandleForReading: FileHandle(forReadingAtPath: "/dev/null"), fileHandleForWriting: out)

    let config = VZVirtualMachineConfiguration()
    config.bootLoader = boot
    config.cpuCount = 1
    config.memorySize = 512 * 1024 * 1024
    config.serialPorts = [serial]
    config.networkDevices = nics
    config.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
    do {
        try config.validate()
    } catch {
        fail(2, "configuration refused: \(error)")
    }
    return config
}

let relayConfig = machine(
    initrd: args[1], cmdline: relayCmdline, console: relayConsole,
    nics: [linkNIC(relayLinkMAC, pair[0]), nic(relayNatMAC, VZNATNetworkDeviceAttachment())])
// The build has the link and nothing else: no NAT, no socket device.
let buildConfig = machine(
    initrd: args[2], cmdline: buildCmdline, console: buildConsole,
    nics: [linkNIC(buildLinkMAC, pair[1])])

// The "internet": echoes each connection until EOF and logs who it came from.
func serveEcho() {
    let s = socket(AF_INET, SOCK_STREAM, 0)
    var on: Int32 = 1
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    addr.sin_addr.s_addr = INADDR_ANY
    let bound = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bound == 0, listen(s, 8) == 0 else { fail(2, "echo server: cannot listen on \(port)") }
    log("echo server on port \(port)")
    DispatchQueue.global().async {
        while true {
            var peer = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let c = withUnsafeMutablePointer(to: &peer) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { accept(s, $0, &len) }
            }
            if c < 0 { continue }
            let from = String(cString: inet_ntoa(peer.sin_addr))
            log("echo server: connection from \(from):\(UInt16(bigEndian: peer.sin_port))")
            DispatchQueue.global().async {
                var buf = [UInt8](repeating: 0, count: 4096)
                var total = 0
                while true {
                    let n = read(c, &buf, buf.count)
                    if n <= 0 { break }
                    total += n
                    _ = buf.withUnsafeBufferPointer { write(c, $0.baseAddress, n) }
                }
                close(c)
                log("echo server: \(from) done, \(total) bytes echoed")
            }
        }
    }
}

final class Watcher: NSObject, VZVirtualMachineDelegate {
    let name: String
    init(_ name: String) { self.name = name }
    func guestDidStop(_ vm: VZVirtualMachine) {
        log("\(name) stopped")
        if name == "build" {
            // Let the relay log the connection's end.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { exit(0) }
        }
    }
    func virtualMachine(_ vm: VZVirtualMachine, didStopWithError error: Error) {
        fail(3, "\(name) stopped with error: \(error)")
    }
}

serveEcho()
let relay = VZVirtualMachine(configuration: relayConfig)
let build = VZVirtualMachine(configuration: buildConfig)
let relayWatcher = Watcher("relay")
let buildWatcher = Watcher("build")
relay.delegate = relayWatcher
build.delegate = buildWatcher
for (name, vm) in [("relay", relay), ("build", build)] {
    vm.start { result in
        switch result {
        case .success: log("\(name) started")
        case .failure(let error): fail(2, "\(name) start failed: \(error)")
        }
    }
}
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
    log("timed out after \(Int(seconds))s")
    exit(4)
}
RunLoop.main.run()
