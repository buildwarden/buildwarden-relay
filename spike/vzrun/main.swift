// vzrun: a minimal Virtualization.framework runner for the VZ spike.
//
// Boots a kernel and initrd through VZLinuxBootLoader with one CPU, 512 MB,
// a virtio console, virtio-rng and virtio-net on NAT, then reports how the
// VM ended. Unlike vfkit it hands any kernel file to VZ unchecked, so VZ's
// own verdict on a non-Linux image is what gets recorded.
//
// usage: vzrun <kernel> <initrd> [--cmdline S] [--console FILE] [--seconds N]
//              [--mac XX:XX:XX:XX:XX:XX] [--no-rng] [--vsock]
//
// --no-rng leaves out the entropy device. --vsock adds a virtio socket device
// and talks to the guest over it both ways: the host accepts on port 5001 and
// answers each line with "host says hi", and connects to guest port 5000
// (retrying while the guest gets there), sends a line and prints the echo.
//
// The console goes to FILE (default stdout). The run stops after N seconds
// (default 20) if the guest has not stopped itself. Exit status: 0 guest
// stopped, 2 VZ refused the configuration or failed to start, 3 the guest
// errored at run time, 4 timed out (still running).

import Foundation
import Virtualization

func fail(_ code: Int32, _ msg: String) -> Never {
    FileHandle.standardError.write(("vzrun: " + msg + "\n").data(using: .utf8)!)
    exit(code)
}

var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return v
}
let cmdline = option("--cmdline") ?? ""
let mac = option("--mac")
let consolePath = option("--console")
let seconds = Double(option("--seconds") ?? "20") ?? 20
func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
}
let rng = !flag("--no-rng")
let vsock = flag("--vsock")
guard args.count == 2 else {
    fail(64, "usage: vzrun <kernel> <initrd> [--cmdline S] [--console FILE] [--seconds N]")
}

let boot = VZLinuxBootLoader(kernelURL: URL(fileURLWithPath: args[0]))
boot.initialRamdiskURL = URL(fileURLWithPath: args[1])
boot.commandLine = cmdline

let out: FileHandle
if let path = consolePath {
    FileManager.default.createFile(atPath: path, contents: nil)
    out = FileHandle(forWritingAtPath: path)!
} else {
    out = FileHandle.standardOutput
}
let console = VZVirtioConsoleDeviceSerialPortConfiguration()
console.attachment = VZFileHandleSerialPortAttachment(
    fileHandleForReading: FileHandle(forReadingAtPath: "/dev/null"), fileHandleForWriting: out)

let net = VZVirtioNetworkDeviceConfiguration()
net.attachment = VZNATNetworkDeviceAttachment()
if let mac = mac {
    // A fixed MAC finds the guest's lease in /var/db/dhcpd_leases.
    guard let address = VZMACAddress(string: mac) else { fail(64, "bad --mac \(mac)") }
    net.macAddress = address
}

let config = VZVirtualMachineConfiguration()
config.bootLoader = boot
config.cpuCount = 1
config.memorySize = 512 * 1024 * 1024
config.serialPorts = [console]
config.networkDevices = [net]
config.entropyDevices = rng ? [VZVirtioEntropyDeviceConfiguration()] : []
config.socketDevices = vsock ? [VZVirtioSocketDeviceConfiguration()] : []

do {
    try config.validate()
} catch {
    fail(2, "configuration refused: \(error)")
}

final class Watcher: NSObject, VZVirtualMachineDelegate {
    func guestDidStop(_ vm: VZVirtualMachine) {
        print("vzrun: guest stopped")
        exit(0)
    }
    func virtualMachine(_ vm: VZVirtualMachine, didStopWithError error: Error) {
        fail(3, "guest stopped with error: \(error)")
    }
}

func log(_ msg: String) {
    print("vzrun: " + msg)
    fflush(stdout)
}

// Reads what is available on fd, up to a line's worth.
func readLine(_ fd: Int32) -> String {
    var buf = [UInt8](repeating: 0, count: 256)
    let n = read(fd, &buf, buf.count)
    return n > 0 ? String(decoding: buf[0..<n], as: UTF8.self) : ""
}

func writeAll(_ fd: Int32, _ s: String) {
    let bytes = Array(s.utf8)
    var off = 0
    while off < bytes.count {
        let n = bytes[off...].withUnsafeBufferPointer { write(fd, $0.baseAddress, $0.count) }
        if n <= 0 { return }
        off += n
    }
}

let hostPort: UInt32 = 5001
let guestPort: UInt32 = 5000

// Answers each guest connection's first line. Connections are kept so VZ
// does not close them under the reader.
final class HostListener: NSObject, VZVirtioSocketListenerDelegate {
    var connections: [VZVirtioSocketConnection] = []
    func listener(
        _ listener: VZVirtioSocketListener, shouldAcceptNewConnection conn: VZVirtioSocketConnection,
        from device: VZVirtioSocketDevice
    ) -> Bool {
        connections.append(conn)
        log("vsock: accepted guest port \(conn.sourcePort)")
        let fd = conn.fileDescriptor
        DispatchQueue.global().async {
            let line = readLine(fd)
            log("vsock: guest port \(conn.sourcePort) said: \(line.trimmingCharacters(in: .newlines))")
            writeAll(fd, "host says hi\n")
        }
        return true
    }
}
let hostListener = HostListener()
var guestConnection: VZVirtioSocketConnection?

// Connects to the guest's port, retrying until it listens, then checks the echo.
func connectToGuest(_ device: VZVirtioSocketDevice, attempt: Int = 0) {
    device.connect(toPort: guestPort) { result in
        switch result {
        case .success(let conn):
            guestConnection = conn
            let fd = conn.fileDescriptor
            DispatchQueue.global().async {
                let sent = "host echo test\n"
                writeAll(fd, sent)
                let got = readLine(fd)
                log("vsock: guest echoed: \(got.trimmingCharacters(in: .newlines))")
                log(got == sent ? "vsock: echo ok" : "vsock: echo mismatch")
                DispatchQueue.main.async { conn.close() }
            }
        case .failure(let error):
            if attempt < 100 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    connectToGuest(device, attempt: attempt + 1)
                }
            } else {
                log("vsock: connect to guest port \(guestPort) failed: \(error)")
            }
        }
    }
}

let vm = VZVirtualMachine(configuration: config)
let watcher = Watcher()
vm.delegate = watcher
if vsock, let device = vm.socketDevices.first as? VZVirtioSocketDevice {
    let listener = VZVirtioSocketListener()
    listener.delegate = hostListener
    device.setSocketListener(listener, forPort: hostPort)
}
vm.start { result in
    switch result {
    case .success:
        print("vzrun: started")
        if vsock, let device = vm.socketDevices.first as? VZVirtioSocketDevice {
            connectToGuest(device)
        }
    case .failure(let error):
        fail(2, "start failed: \(error)")
    }
}
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
    print("vzrun: timed out after \(Int(seconds))s, state \(vm.state.rawValue)")
    exit(4)
}
RunLoop.main.run()
