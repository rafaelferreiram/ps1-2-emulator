import Foundation
import Darwin

// Ships precompiled: no developer tools run on the receiving machine.
enum MachOInspectionError: Error, CustomStringConvertible {
    case invalid(String)
    var description: String {
        switch self { case .invalid(let message): return message }
    }
}

private enum MachOByteOrder {
    case big, little
    func uint32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        let indices = self == .big ? Array(offset..<(offset + 4)) : Array((offset..<(offset + 4)).reversed())
        return indices.reduce(0) { ($0 << 8) | UInt32(bytes[$1]) }
    }
    func uint64(_ bytes: [UInt8], _ offset: Int) -> UInt64 {
        let indices = self == .big ? Array(offset..<(offset + 8)) : Array((offset..<(offset + 8)).reversed())
        return indices.reduce(0) { ($0 << 8) | UInt64(bytes[$1]) }
    }
}

private final class MachOFile {
    let descriptor: Int32
    let size: UInt64
    init(path: String) throws {
        guard path.hasPrefix("/"), !path.utf8.contains(0) else {
            throw MachOInspectionError.invalid("An absolute file path is required.")
        }
        // A FIFO cannot block this open, and final-component symlinks are
        // rejected atomically rather than checked before a racy open.
        let opened = path.withCString { Darwin.open($0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK) }
        guard opened >= 0 else {
            throw MachOInspectionError.invalid("Cannot open executable: \(String(cString: strerror(errno)))")
        }
        var metadata = stat()
        guard fstat(opened, &metadata) == 0,
              metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), metadata.st_size >= 4 else {
            close(opened)
            throw MachOInspectionError.invalid("Executable must be a regular file containing a Mach-O header.")
        }
        descriptor = opened
        size = UInt64(metadata.st_size)
    }
    deinit { close(descriptor) }
    func read(at offset: UInt64, count: Int) throws -> [UInt8] {
        // Every read is a fixed-size header, never file-sized content.
        guard count >= 0, count <= 32, offset <= size, UInt64(count) <= size - offset else {
            throw MachOInspectionError.invalid("Truncated Mach-O header.")
        }
        var bytes = [UInt8](repeating: 0, count: count)
        var consumed = 0
        while consumed < count {
            let amount = bytes.withUnsafeMutableBytes { buffer in
                pread(descriptor, buffer.baseAddress!.advanced(by: consumed), count - consumed, off_t(offset + UInt64(consumed)))
            }
            if amount < 0 && errno == EINTR { continue }
            guard amount > 0 else { throw MachOInspectionError.invalid("Cannot read complete Mach-O header.") }
            consumed += amount
        }
        return bytes
    }
}

enum MachOInspector {
    // These bounds also cap system calls for adversarial inputs.
    private static let maximumArchitectures: UInt32 = 128
    private static let maximumLoadCommands: UInt32 = 4096
    private struct Slice {
        let cpu: UInt32
        let subtype: UInt32
        let offset: UInt64
        let size: UInt64
    }
    static func architectures(at path: String) throws -> [String] {
        let file = try MachOFile(path: path)
        let magic = MachOByteOrder.big.uint32(try file.read(at: 0, count: 4), 0)
        switch magic {
        case 0xcafebabe: return try fat(file, order: .big, is64Bit: false)
        case 0xbebafeca: return try fat(file, order: .little, is64Bit: false)
        case 0xcafebabf: return try fat(file, order: .big, is64Bit: true)
        case 0xbfbafeca: return try fat(file, order: .little, is64Bit: true)
        default: return [try thin(file, offset: 0, size: file.size, expected: nil)]
        }
    }
    private static func fat(_ file: MachOFile, order: MachOByteOrder, is64Bit: Bool) throws -> [String] {
        let header = try file.read(at: 0, count: 8)
        let count = order.uint32(header, 4)
        guard count > 0, count <= maximumArchitectures else {
            throw MachOInspectionError.invalid("Invalid universal architecture count.")
        }
        let entrySize: UInt64 = is64Bit ? 32 : 20
        let tableEnd = 8 + UInt64(count) * entrySize
        guard tableEnd <= file.size else { throw MachOInspectionError.invalid("Truncated universal architecture table.") }
        var slices: [Slice] = []
        var identities = Set<UInt64>()
        for index in 0..<count {
            let entry = try file.read(at: 8 + UInt64(index) * entrySize, count: Int(entrySize))
            let cpu = order.uint32(entry, 0)
            let subtype = order.uint32(entry, 4)
            let offset = is64Bit ? order.uint64(entry, 8) : UInt64(order.uint32(entry, 8))
            let size = is64Bit ? order.uint64(entry, 16) : UInt64(order.uint32(entry, 12))
            let alignment = order.uint32(entry, is64Bit ? 24 : 16)
            guard offset >= tableEnd, offset <= file.size, size >= 28, size <= file.size - offset,
                  alignment < 63, offset % (UInt64(1) << alignment) == 0,
                  !is64Bit || order.uint32(entry, 28) == 0 else {
                throw MachOInspectionError.invalid("Invalid universal slice bounds or alignment.")
            }
            let identity = (UInt64(cpu) << 32) | UInt64(subtype & 0x00ffffff)
            guard identities.insert(identity).inserted else { throw MachOInspectionError.invalid("Duplicate universal architecture.") }
            slices.append(Slice(cpu: cpu, subtype: subtype, offset: offset, size: size))
        }
        let ordered = slices.sorted { $0.offset < $1.offset }
        for index in 1..<ordered.count {
            guard ordered[index - 1].size <= ordered[index].offset - ordered[index - 1].offset else {
                throw MachOInspectionError.invalid("Overlapping universal slices.")
            }
        }
        return try slices.map { try thin(file, offset: $0.offset, size: $0.size, expected: $0) }
    }
    private static func thin(_ file: MachOFile, offset: UInt64, size: UInt64, expected: Slice?) throws -> String {
        guard size >= 28 else { throw MachOInspectionError.invalid("Truncated Mach-O slice.") }
        let magic = MachOByteOrder.big.uint32(try file.read(at: offset, count: 4), 0)
        let order: MachOByteOrder
        let is64Bit: Bool
        switch magic {
        case 0xfeedface: order = .big; is64Bit = false
        case 0xcefaedfe: order = .little; is64Bit = false
        case 0xfeedfacf: order = .big; is64Bit = true
        case 0xcffaedfe: order = .little; is64Bit = true
        default: throw MachOInspectionError.invalid("File or universal slice is not a Mach-O binary.")
        }
        let headerSize: UInt64 = is64Bit ? 32 : 28
        guard size >= headerSize else { throw MachOInspectionError.invalid("Truncated Mach-O slice header.") }
        let header = try file.read(at: offset, count: Int(headerSize))
        let cpu = order.uint32(header, 4)
        let subtype = order.uint32(header, 8)
        let required64Bit: Bool?
        switch cpu {
        case 0x0100000c, 0x01000007: required64Bit = true
        case 7, 12, 18: required64Bit = false
        default: required64Bit = nil
        }
        guard required64Bit == nil || required64Bit == is64Bit else {
            throw MachOInspectionError.invalid("Mach-O header width and CPU ABI disagree.")
        }
        if let expected {
            guard cpu == expected.cpu, subtype & 0x00ffffff == expected.subtype & 0x00ffffff else {
                throw MachOInspectionError.invalid("Universal table and Mach-O slice architectures disagree.")
            }
        }
        let commandCount = order.uint32(header, 16)
        let commandSize = UInt64(order.uint32(header, 20))
        guard commandSize <= size - headerSize, commandCount <= maximumLoadCommands,
              UInt64(commandCount) <= commandSize / 8 else {
            throw MachOInspectionError.invalid("Invalid Mach-O load-command bounds.")
        }
        let commandsEnd = offset + headerSize + commandSize
        var cursor = offset + headerSize
        for _ in 0..<commandCount {
            guard commandsEnd - cursor >= 8 else { throw MachOInspectionError.invalid("Truncated Mach-O load command.") }
            let command = try file.read(at: cursor, count: 8)
            let length = UInt64(order.uint32(command, 4))
            guard length >= 8, length % (is64Bit ? 8 : 4) == 0, length <= commandsEnd - cursor else {
                throw MachOInspectionError.invalid("Invalid Mach-O load-command size.")
            }
            cursor += length
        }
        guard cursor == commandsEnd else { throw MachOInspectionError.invalid("Mach-O load-command count and size disagree.") }
        return architecture(cpu: cpu, subtype: subtype & 0x00ffffff)
    }
    private static func architecture(cpu: UInt32, subtype: UInt32) -> String {
        switch cpu {
        case 0x0100000c:
            switch subtype {
            case 0, 1: return "arm64"
            case 2: return "arm64e"
            default: return "arm64_subtype_" + String(subtype)
            }
        case 0x01000007:
            switch subtype {
            case 3: return "x86_64"
            case 8: return "x86_64h"
            default: return "x86_64_subtype_" + String(subtype)
            }
        case 0x0200000c: return "arm64_32"
        case 7: return "i386"
        case 12: return "arm"
        case 18: return "ppc"
        case 0x01000012: return "ppc64"
        default: return "cpu_0x" + String(cpu, radix: 16)
        }
    }
}

#if !MACHO_INSPECTOR_TESTS
@main
struct InspectMachOCommand {
    static func main() {
        guard CommandLine.arguments.count == 2, CommandLine.arguments[1].hasPrefix("/") else {
            fputs("Usage: InspectMachO /absolute/executable\n", stderr)
            exit(2)
        }
        do {
            print(try MachOInspector.architectures(at: CommandLine.arguments[1]).joined(separator: " "))
        } catch {
            fputs("InspectMachO: \(error)\n", stderr)
            exit(1)
        }
    }
}
#endif
