// vzrun: a minimal Virtualization.framework runner for the VZ spike.
//
// Boots a kernel and initrd through VZLinuxBootLoader with one CPU, 512 MB,
// a virtio console, virtio-rng and virtio-net on NAT, then reports how the
// VM ended. Unlike vfkit it hands any kernel file to VZ unchecked, so VZ's
// own verdict on a non-Linux image is what gets recorded.
//
// usage: vzrun <kernel> <initrd> [--cmdline S] [--console FILE] [--seconds N]
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
let consolePath = option("--console")
let seconds = Double(option("--seconds") ?? "20") ?? 20
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

let config = VZVirtualMachineConfiguration()
config.bootLoader = boot
config.cpuCount = 1
config.memorySize = 512 * 1024 * 1024
config.serialPorts = [console]
config.networkDevices = [net]
config.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
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

let vm = VZVirtualMachine(configuration: config)
let watcher = Watcher()
vm.delegate = watcher
vm.start { result in
    switch result {
    case .success:
        print("vzrun: started")
    case .failure(let error):
        fail(2, "start failed: \(error)")
    }
}
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
    print("vzrun: timed out after \(Int(seconds))s, state \(vm.state.rawValue)")
    exit(4)
}
RunLoop.main.run()
