import Foundation
import Darwin

@main
struct InspectMachOTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PS12MachOTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var checks = 0
        var fixtureIndex = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError(message) }
            checks += 1
        }
        func write(_ bytes: [UInt8]) throws -> URL {
            fixtureIndex += 1
            let file = root.appendingPathComponent("fixture \(fixtureIndex) $literal; punctuation")
            try Data(bytes).write(to: file)
            return file
        }
        func accepts(_ bytes: [UInt8], _ expected: [String], _ message: String) throws {
            let file = try write(bytes)
            let architectures = try MachOInspector.architectures(at: file.path)
            expect(architectures == expected, message)
        }
        func rejectsPath(_ path: String, _ message: String) {
            do {
                _ = try MachOInspector.architectures(at: path)
                fatalError(message)
            } catch {
                checks += 1
            }
        }
        func rejects(_ bytes: [UInt8], _ message: String) throws { rejectsPath(try write(bytes).path, message) }
        let arm64: UInt32 = 0x0100000c
        let x86: UInt32 = 0x01000007
        try accepts(thin(cpu: arm64), ["arm64"], "Little-endian arm64")
        try accepts(thin(cpu: arm64, little: false), ["arm64"], "Big-endian 64-bit header")
        try accepts(thin(cpu: x86, subtype: 3), ["x86_64"], "Little-endian x86_64")
        try accepts(thin(cpu: x86, subtype: 8), ["x86_64h"], "Specialized x86 subtype preserved")
        try accepts(thin(cpu: arm64, subtype: 0x80000002), ["arm64e"], "ARM subtype capabilities masked")
        try accepts(thin(cpu: 7, subtype: 3, is64Bit: false), ["i386"], "Little-endian 32-bit header")
        try accepts(thin(cpu: 18, is64Bit: false, little: false), ["ppc"], "Big-endian 32-bit header")
        try accepts(thin(cpu: 0x01001234), ["cpu_0x1001234"], "Unknown CPU remains unsupported token")
        try accepts(thin(cpu: arm64, subtype: 99), ["arm64_subtype_99"], "Unknown ARM subtype remains unsupported")
        try accepts(thin(cpu: x86, subtype: 99), ["x86_64_subtype_99"], "Unknown x86 subtype remains unsupported")
        try accepts(thin(cpu: arm64, commands: [8, 16]), ["arm64"], "Valid load-command table")
        try accepts(thin(cpu: 7, is64Bit: false, commands: [12, 8]), ["i386"], "32-bit load-command alignment")
        let slices = [(arm64, UInt32(0), thin(cpu: arm64)), (x86, UInt32(3), thin(cpu: x86, subtype: 3))]
        for wide in [false, true] {
            for little in [false, true] {
                try accepts(fat(slices, is64Bit: wide, little: little), ["arm64", "x86_64"], "Universal bitness/endian variant")
            }
        }
        try accepts(fat(Array(slices.reversed())), ["x86_64", "arm64"], "Universal output follows table order")
        for length in [0, 1, 3, 4, 7, 27, 28, 31] {
            try rejects(Array(thin(cpu: arm64).prefix(length)), "Truncated thin header at \(length)")
        }
        try rejects(Array("not a Mach-O executable".utf8), "Unrecognized input rejected")
        try rejects(thin(cpu: arm64, is64Bit: false), "64-bit CPU with 32-bit header rejected")
        try rejects(thin(cpu: 7), "32-bit CPU with 64-bit header rejected")
        try rejects([0xca, 0xfe, 0xba, 0xbe], "Truncated fat header")
        var fixture = fat(slices)
        put(0, into: &fixture, at: 4)
        try rejects(fixture, "Empty universal rejected")
        put(129, into: &fixture, at: 4)
        try rejects(fixture, "Excessive universal count rejected")
        put(UInt32.max, into: &fixture, at: 4)
        try rejects(fixture, "Overflow universal count rejected")
        try rejects(Array(fat(slices).prefix(47)), "Truncated architecture table")
        fixture = fat(slices)
        put(8, into: &fixture, at: 16)
        try rejects(fixture, "Slice overlapping table rejected")
        fixture = fat(slices)
        put(UInt32.max, into: &fixture, at: 16)
        try rejects(fixture, "Slice beyond end rejected")
        fixture = fat(slices)
        put(UInt32.max, into: &fixture, at: 20)
        try rejects(fixture, "Slice length beyond file rejected")
        fixture = fat(slices)
        put(27, into: &fixture, at: 20)
        try rejects(fixture, "Undersize slice rejected")
        fixture = fat(slices)
        put(31, into: &fixture, at: 20)
        try rejects(fixture, "64-bit slice shorter than its header rejected")
        fixture = fat(slices)
        put(63, into: &fixture, at: 24)
        try rejects(fixture, "Overflowing alignment rejected")
        fixture = fat(slices)
        put(12, into: &fixture, at: 24)
        try rejects(fixture, "Misaligned slice rejected")
        fixture = fat(slices)
        put(256, into: &fixture, at: 36)
        try rejects(fixture, "Overlapping slice ranges rejected")
        fixture = fat(slices)
        put(x86, into: &fixture, at: 8)
        try rejects(fixture, "Table CPU disagreement rejected")
        fixture = fat(slices)
        put(2, into: &fixture, at: 12)
        try rejects(fixture, "Table CPU subtype disagreement rejected")
        fixture = fat(slices)
        put(0, into: &fixture, at: 256)
        try rejects(fixture, "Non-Mach-O slice rejected")
        try rejects(fat([slices[0], slices[0]]), "Duplicate architecture rejected")
        try rejects(fat([(arm64, 0, fat(slices))]), "Nested universal binary rejected")
        fixture = fat(slices, is64Bit: true)
        put64(UInt64.max, into: &fixture, at: 16)
        try rejects(fixture, "Fat64 offset overflow rejected")
        fixture = fat(slices, is64Bit: true)
        put64(UInt64.max, into: &fixture, at: 24)
        try rejects(fixture, "Fat64 length overflow rejected")
        fixture = fat(slices, is64Bit: true)
        put(1, into: &fixture, at: 36)
        try rejects(fixture, "Fat64 reserved field rejected")
        fixture = fat(slices, is64Bit: true, little: true)
        put64(UInt64.max, into: &fixture, at: 24, little: true)
        try rejects(fixture, "Swapped fat64 overflow rejected")
        fixture = thin(cpu: arm64)
        put(1, into: &fixture, at: 16, little: true)
        try rejects(fixture, "Commands outside header rejected")
        fixture = thin(cpu: arm64)
        put(UInt32.max, into: &fixture, at: 20, little: true)
        try rejects(fixture, "Commands beyond slice rejected")
        fixture = thin(cpu: arm64, commands: [8])
        put(0, into: &fixture, at: 36, little: true)
        try rejects(fixture, "Zero-length command rejected")
        fixture = thin(cpu: arm64, commands: [8])
        put(16, into: &fixture, at: 36, little: true)
        try rejects(fixture, "Oversized command rejected")
        try rejects(thin(cpu: arm64, commands: [12]), "Misaligned 64-bit load command rejected")
        fixture = thin(cpu: arm64, commands: [8, 8])
        put(1, into: &fixture, at: 16, little: true)
        try rejects(fixture, "Unaccounted command bytes rejected")
        fixture = thin(cpu: arm64, commands: [8, 8])
        put(16, into: &fixture, at: 36, little: true)
        try rejects(fixture, "Command consumes next command header rejected")
        try rejects(thin(cpu: arm64, commands: Array(repeating: 8, count: 4097)), "Excessive command count rejected")
        rejectsPath(root.path, "Directory rejected")
        rejectsPath(root.appendingPathComponent("missing").path, "Missing file rejected")
        rejectsPath("relative-path", "Relative path rejected")
        rejectsPath(root.path + "\0hidden", "Embedded NUL rejected")
        let target = try write(thin(cpu: arm64))
        let symlink = root.appendingPathComponent("symlink")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)
        rejectsPath(symlink.path, "Symlink rejected")
        let fifo = root.appendingPathComponent("fifo")
        guard mkfifo(fifo.path, mode_t(0o600)) == 0 else { fatalError("Cannot create FIFO fixture") }
        rejectsPath(fifo.path, "FIFO rejected without blocking")
        rejectsPath("/dev/null", "Character device rejected")
        // Sparse size exercises bounded I/O without allocating gigabytes.
        let sparse = try write(thin(cpu: arm64))
        let sparseHandle = try FileHandle(forWritingTo: sparse)
        try sparseHandle.truncate(atOffset: 8 * 1024 * 1024 * 1024)
        try sparseHandle.close()
        let sparseArchitectures = try MachOInspector.architectures(at: sparse.path)
        expect(sparseArchitectures == ["arm64"], "Large sparse file parsed with bounded reads")
        let executable = CommandLine.arguments[1]
        let actual = try MachOInspector.architectures(at: executable)
        expect(actual == ["arm64"], "Actual compiler-produced native executable")
        let selfArchitectures = try MachOInspector.architectures(at: CommandLine.arguments[0])
        expect(selfArchitectures == ["arm64"], "Actual test executable with real load commands")
        func run(_ arguments: [String]) throws -> (Int32, String, String) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = ["PATH": "/nonexistent"]
            let output = Pipe()
            let errors = Pipe()
            process.standardOutput = output
            process.standardError = errors
            try process.run()
            process.waitUntilExit()
            return (process.terminationStatus,
                    String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
                    String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        }
        let success = try run([executable])
        expect(success.0 == 0 && success.1 == "arm64\n" && success.2.isEmpty, "CLI works without PATH tools")
        let universal = try write(fat(slices, is64Bit: true, little: true))
        let universalResult = try run([universal.path])
        expect(universalResult.0 == 0 && universalResult.1 == "arm64 x86_64\n", "CLI universal architecture tokens")
        let invalid = try run([try write([1, 2, 3, 4]).path])
        expect(invalid.0 == 1 && invalid.1.isEmpty && invalid.2.contains("InspectMachO:"), "CLI parse failure contract")
        let usage = try run([])
        expect(usage.0 == 2 && usage.1.isEmpty && usage.2.contains("Usage:"), "CLI missing-argument contract")
        let relative = try run(["relative"])
        expect(relative.0 == 2 && relative.1.isEmpty, "CLI rejects relative path")
        let extra = try run([executable, executable])
        expect(extra.0 == 2 && extra.1.isEmpty, "CLI rejects extra arguments")
        print("InspectMachOTests: \(checks) checks passed")
    }
    static func put(_ value: UInt32, into bytes: inout [UInt8], at offset: Int, little: Bool = false) {
        for index in 0..<4 { bytes[offset + index] = UInt8(truncatingIfNeeded: value >> ((little ? index : 3 - index) * 8)) }
    }
    static func put64(_ value: UInt64, into bytes: inout [UInt8], at offset: Int, little: Bool = false) {
        for index in 0..<8 { bytes[offset + index] = UInt8(truncatingIfNeeded: value >> ((little ? index : 7 - index) * 8)) }
    }
    static func thin(cpu: UInt32, subtype: UInt32 = 0, is64Bit: Bool = true, little: Bool = true, commands: [UInt32] = []) -> [UInt8] {
        let headerSize = is64Bit ? 32 : 28
        let totalCommands = commands.reduce(0, +)
        var bytes = [UInt8](repeating: 0, count: headerSize + Int(totalCommands))
        put(is64Bit ? 0xfeedfacf : 0xfeedface, into: &bytes, at: 0, little: little)
        put(cpu, into: &bytes, at: 4, little: little)
        put(subtype, into: &bytes, at: 8, little: little)
        put(2, into: &bytes, at: 12, little: little)
        put(UInt32(commands.count), into: &bytes, at: 16, little: little)
        put(totalCommands, into: &bytes, at: 20, little: little)
        var offset = headerSize
        for size in commands {
            put(1, into: &bytes, at: offset, little: little)
            put(size, into: &bytes, at: offset + 4, little: little)
            offset += Int(size)
        }
        return bytes
    }
    static func fat(_ slices: [(UInt32, UInt32, [UInt8])], is64Bit: Bool = false, little: Bool = false) -> [UInt8] {
        let entrySize = is64Bit ? 32 : 20
        var offsets: [Int] = []
        var next = 256
        for slice in slices {
            offsets.append(next)
            next += ((slice.2.count + 255) / 256) * 256
        }
        var bytes = [UInt8](repeating: 0, count: next)
        put(is64Bit ? 0xcafebabf : 0xcafebabe, into: &bytes, at: 0, little: little)
        put(UInt32(slices.count), into: &bytes, at: 4, little: little)
        for (index, slice) in slices.enumerated() {
            let entry = 8 + index * entrySize
            put(slice.0, into: &bytes, at: entry, little: little)
            put(slice.1, into: &bytes, at: entry + 4, little: little)
            if is64Bit {
                put64(UInt64(offsets[index]), into: &bytes, at: entry + 8, little: little)
                put64(UInt64(slice.2.count), into: &bytes, at: entry + 16, little: little)
            } else {
                put(UInt32(offsets[index]), into: &bytes, at: entry + 8, little: little)
                put(UInt32(slice.2.count), into: &bytes, at: entry + 12, little: little)
            }
            put(8, into: &bytes, at: entry + (is64Bit ? 24 : 16), little: little)
            bytes.replaceSubrange(offsets[index]..<(offsets[index] + slice.2.count), with: slice.2)
        }
        return bytes
    }
}
