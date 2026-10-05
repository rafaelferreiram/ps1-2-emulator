import Foundation
import Darwin

// Developer-only repair for the icon-position metadata injected by makehybrid.
// This tool never runs on a user's downloaded or mounted installer.
enum HFSMetadataError: Error, CustomStringConvertible {
    case invalid(String)
    var description: String { switch self { case .invalid(let text): return text } }
}
private func hfsRequire(_ value: Bool, _ message: String) throws {
    if !value { throw HFSMetadataError.invalid(message) }
}
private func hfs16(_ b: [UInt8], _ o: Int) -> UInt16 { UInt16(b[o]) << 8 | UInt16(b[o + 1]) }
private func hfs32(_ b: [UInt8], _ o: Int) -> UInt32 { (0..<4).reduce(0) { $0 << 8 | UInt32(b[o + $1]) } }
private func hfs64(_ b: [UInt8], _ o: Int) -> UInt64 { (0..<8).reduce(0) { $0 << 8 | UInt64(b[o + $1]) } }

private final class HFSImageFile {
    let descriptor: Int32
    let size: UInt64
    init(_ path: String, writable: Bool) throws {
        try hfsRequire(path.hasPrefix("/") && !path.utf8.contains(0), "An absolute image path is required.")
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        try hfsRequire(!components.isEmpty && !components.contains(".") && !components.contains(".."), "Invalid image path.")
        var parent = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        try hfsRequire(parent >= 0, "Cannot open filesystem root.")
        for component in components.dropLast() {
            let next = component.withCString { openat(parent, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            close(parent)
            guard next >= 0 else { throw HFSMetadataError.invalid("Symlinked or inaccessible image parent.") }
            parent = next
        }
        let fd = components.last!.withCString {
            openat(parent, $0, (writable ? O_RDWR : O_RDONLY) | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        }
        close(parent)
        guard fd >= 0 else { throw HFSMetadataError.invalid("Cannot open image without following symlinks.") }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_nlink == 1, info.st_uid == getuid(), info.st_size >= 4096,
              info.st_size <= 4 * 1024 * 1024 * 1024,
              flock(fd, (writable ? LOCK_EX : LOCK_SH) | LOCK_NB) == 0 else {
            close(fd)
            throw HFSMetadataError.invalid("Image must be an owned, unshared regular file (4 KiB–4 GiB).")
        }
        descriptor = fd
        size = UInt64(info.st_size)
    }
    deinit { close(descriptor) }
    func read(_ offset: UInt64, _ count: Int) throws -> [UInt8] {
        try hfsRequire(count >= 0 && count <= 16 * 1024 * 1024 && offset <= size && UInt64(count) <= size - offset, "Image read exceeds bounds.")
        var bytes = [UInt8](repeating: 0, count: count)
        var consumed = 0
        while consumed < count {
            let amount = bytes.withUnsafeMutableBytes { pread(descriptor, $0.baseAddress!.advanced(by: consumed), count - consumed, off_t(offset + UInt64(consumed))) }
            if amount < 0 && errno == EINTR { continue }
            try hfsRequire(amount > 0, "Cannot read image.")
            consumed += amount
        }
        return bytes
    }
    func zeroCoordinates(_ offset: UInt64) throws {
        try hfsRequire(try read(offset, 4) == [255, 255, 255, 255], "Image changed during normalization.")
        let zero: [UInt8] = [0, 0, 0, 0]
        var consumed = 0
        while consumed < 4 {
            let amount = zero.withUnsafeBytes { pwrite(descriptor, $0.baseAddress!.advanced(by: consumed), 4 - consumed, off_t(offset + UInt64(consumed))) }
            if amount < 0 && errno == EINTR { continue }
            try hfsRequire(amount > 0, "Cannot write normalized coordinates.")
            consumed += amount
        }
    }
}

struct HFSMetadataReport {
    let entries: Int
    let coordinateOffsets: [UInt64]
}
enum HFSMetadataNormalizer {
    private struct Entry {
        let id: UInt32
        let parent: UInt32
        let name: String
        let folder: Bool
        let mode: UInt16
        let metadata: [UInt8]
        let coordinateOffset: UInt64
        let resourceFork: [UInt8]
    }
    private struct Fork { let offset: UInt64; let size: UInt64; let allocated: UInt64 }
    static func process(path: String, normalize: Bool) throws -> HFSMetadataReport {
        let file = try HFSImageFile(path, writable: normalize)
        let report = try inspect(file)
        if !normalize {
            try hfsRequire(report.coordinateOffsets.isEmpty, "Generated FinderInfo remains in the signed installer; normalize before compression.")
            return report
        }
        // Full validation precedes the first write. Only four known coordinate
        // bytes per catalog record change, never data forks or permissions.
        for offset in report.coordinateOffsets { try file.zeroCoordinates(offset) }
        try hfsRequire(fsync(file.descriptor) == 0, "Cannot flush normalized image.")
        let verified = try inspect(file)
        try hfsRequire(verified.coordinateOffsets.isEmpty && verified.entries == report.entries, "Normalized image read-back failed.")
        return report
    }
    private static func inspect(_ file: HFSImageFile) throws -> HFSMetadataReport {
        let map = try file.read(512, 1024)
        func type(_ offset: Int) -> String { String(decoding: map[(offset + 48)..<(offset + 80)].prefix(while: { $0 != 0 }), as: UTF8.self) }
        // makehybrid uses two 512-byte APM records even though its optical DDM
        // advertises 2048-byte physical blocks. Reject other partition layouts.
        try hfsRequire(hfs16(map, 0) == 0x504d && hfs16(map, 512) == 0x504d &&
            hfs32(map, 4) == 2 && hfs32(map, 516) == 2 &&
            hfs32(map, 8) == 1 && hfs32(map, 12) == 63 &&
            type(0) == "Apple_partition_map" && type(512) == "Apple_HFS" && hfs32(map, 520) == 64,
            "Expected a standalone makehybrid HFS+ partition map.")
        let volume: UInt64 = 64 * 512
        let volumeSize = UInt64(hfs32(map, 524)) * 512
        try hfsRequire(volumeSize >= 4096 && volume <= file.size && volumeSize <= file.size - volume, "HFS partition exceeds image.")
        let header = try file.read(volume + 1024, 512)
        try hfsRequire(hfs16(header, 0) == 0x482b && hfs16(header, 2) == 4 &&
            hfs32(header, 8) == 0x63657264 && hfs32(header, 4) == 0x100 && hfs32(header, 12) == 0,
            "Only clean, non-journaled makehybrid HFS+ images are supported.")
        let block = UInt64(hfs32(header, 40))
        let blocks = UInt64(hfs32(header, 44))
        try hfsRequire(block >= 512 && block <= 65536 && block.nonzeroBitCount == 1 &&
            blocks > 0 && blocks <= volumeSize / block && blocks * block == volumeSize, "Invalid HFS allocation geometry.")
        try hfsRequire(header == file.read(volume + volumeSize - 1024, 512), "Primary and alternate HFS headers differ.")
        func fork(_ bytes: [UInt8], _ offset: Int, allowEmpty: Bool = false) throws -> Fork {
            let size = hfs64(bytes, offset)
            let allocated = UInt64(hfs32(bytes, offset + 12))
            let start = UInt64(hfs32(bytes, offset + 16))
            let count = UInt64(hfs32(bytes, offset + 20))
            try hfsRequire(bytes[(offset + 24)..<(offset + 80)].allSatisfy { $0 == 0 }, "Fragmented or overflowing forks are unsupported.")
            if size == 0 {
                try hfsRequire(allowEmpty && allocated == 0 && start == 0 && count == 0, "Unexpected empty or allocated fork.")
                return Fork(offset: 0, size: 0, allocated: 0)
            }
            try hfsRequire(start > 0 && start < blocks && count > 0 && count <= blocks - start &&
                allocated == count && size <= count * block, "Fork exceeds allocation bounds.")
            return Fork(offset: volume + start * block, size: size, allocated: count * block)
        }
        let allocation = try fork(header, 112)
        let extents = try fork(header, 192)
        let catalog = try fork(header, 272)
        _ = try fork(header, 352, allowEmpty: true)
        _ = try fork(header, 432, allowEmpty: true)
        try hfsRequire(hfs64(header, 352) == 0 && hfs64(header, 432) == 0, "Attributes/startup forks are unsupported.")
        let reserved = [allocation, extents, catalog].sorted { $0.offset < $1.offset }
        for index in 1..<reserved.count {
            try hfsRequire(reserved[index - 1].offset + reserved[index - 1].allocated <= reserved[index].offset, "Overlapping filesystem metadata forks.")
        }
        try hfsRequire(reserved.allSatisfy { $0.offset >= volume + 1536 && $0.offset + $0.allocated <= volume + volumeSize - 1024 }, "Metadata fork overlaps HFS headers.")
        try hfsRequire(catalog.size >= 512 && catalog.size <= 16 * 1024 * 1024, "Unsupported catalog size.")
        let bytes = try file.read(catalog.offset, Int(catalog.size))
        try hfsRequire(bytes[8] == 1 && bytes[9] == 0 && hfs16(bytes, 10) == 3, "Invalid catalog header node.")
        let depth = Int(hfs16(bytes, 14))
        let root = hfs32(bytes, 16)
        let expectedRecords = Int(hfs32(bytes, 20))
        let firstLeaf = hfs32(bytes, 24)
        let lastLeaf = hfs32(bytes, 28)
        let nodeSize = Int(hfs16(bytes, 32))
        let nodeCount = Int(hfs32(bytes, 36))
        try hfsRequire(depth > 0 && depth <= 16 && nodeSize >= 512 && nodeSize <= 32768 &&
            nodeSize.nonzeroBitCount == 1 && nodeCount > 1 && nodeCount <= 32768 &&
            nodeCount <= bytes.count / nodeSize && nodeCount * nodeSize == bytes.count &&
            expectedRecords > 0 && expectedRecords <= 65536 && hfs16(bytes, 34) == 516,
            "Invalid catalog B-tree geometry.")
        var visited = Set<UInt32>()
        var leaves: [UInt32] = []
        var entries: [UInt32: Entry] = [:]
        var threads: [UInt32: (UInt32, String, Bool)] = [:]
        var siblings = Set<String>()
        var recordCount = 0
        var dataForks: [Fork] = []
        func key(_ start: Int, _ end: Int) throws -> (UInt32, String, Int) {
            try hfsRequire(end - start >= 8, "Truncated catalog key.")
            let length = Int(hfs16(bytes, start))
            let characters = Int(hfs16(bytes, start + 6))
            try hfsRequire(characters <= 255 && length == 6 + characters * 2 && start + 2 + length <= end, "Malformed catalog key length.")
            guard let name = String(data: Data(bytes[(start + 8)..<(start + 8 + characters * 2)]), encoding: .utf16BigEndian) else { throw HFSMetadataError.invalid("Malformed catalog Unicode.") }
            try hfsRequire(!name.contains("/") && !name.contains(":") && !name.contains("\0") && name != "." && name != "..", "Unsafe catalog name.")
            return (hfs32(bytes, start + 2), name, start + 2 + length)
        }
        func visit(_ number: UInt32, _ height: Int) throws {
            try hfsRequire(number > 0 && Int(number) < nodeCount && visited.insert(number).inserted, "Invalid or cyclic catalog tree.")
            let base = Int(number) * nodeSize
            let leaf = height == 1
            try hfsRequire(bytes[base + 8] == (leaf ? 255 : 0) && Int(bytes[base + 9]) == height, "Catalog node kind/height mismatch.")
            let count = Int(hfs16(bytes, base + 10))
            try hfsRequire(count > 0 && count <= (nodeSize - 14) / 10, "Invalid catalog node record count.")
            let tableStart = nodeSize - (count + 1) * 2
            let offsets = (0...count).map { Int(hfs16(bytes, base + nodeSize - ($0 + 1) * 2)) }
            try hfsRequire(offsets[0] == 14 && offsets.allSatisfy { $0 >= 14 && $0 <= tableStart }, "Catalog records overlap descriptor/offset table.")
            for index in 0..<count {
                try hfsRequire(offsets[index] < offsets[index + 1], "Catalog record offsets are not strictly increasing.")
                let start = base + offsets[index]
                let end = base + offsets[index + 1]
                let (parent, name, body) = try key(start, end)
                if !leaf {
                    try hfsRequire(end - body == 4, "Malformed catalog index record.")
                    try visit(hfs32(bytes, body), height - 1)
                    continue
                }
                recordCount += 1
                try hfsRequire(recordCount <= 65536 && end - body >= 2, "Invalid catalog leaf record.")
                let kind = hfs16(bytes, body)
                if kind == 1 || kind == 2 {
                    let folder = kind == 1
                    try hfsRequire(end - body == (folder ? 88 : 248) && !name.isEmpty, "Invalid file/folder record length.")
                    let id = hfs32(bytes, body + 8)
                    try hfsRequire(id >= 2 && entries[id] == nil && siblings.insert("\(parent)/\(name)").inserted, "Duplicate catalog object.")
                    let mode = hfs16(bytes, body + 42)
                    try hfsRequire(mode & 0xf000 == (folder ? 0x4000 : 0x8000), "Only ordinary files/directories may appear in this installer image.")
                    if !folder { dataForks.append(try fork(bytes, body + 88, allowEmpty: true)) }
                    entries[id] = Entry(id: id, parent: parent, name: name, folder: folder, mode: mode,
                        metadata: Array(bytes[(body + 48)..<(body + 80)]), coordinateOffset: catalog.offset + UInt64(body + 58),
                        resourceFork: folder ? [] : Array(bytes[(body + 168)..<(body + 248)]))
                } else if kind == 3 || kind == 4 {
                    try hfsRequire(name.isEmpty && end - body >= 10, "Malformed thread record.")
                    let characters = Int(hfs16(bytes, body + 8))
                    try hfsRequire(characters <= 255 && end - body == 10 + characters * 2, "Invalid thread length.")
                    guard let threadName = String(data: Data(bytes[(body + 10)..<end]), encoding: .utf16BigEndian) else { throw HFSMetadataError.invalid("Malformed thread Unicode.") }
                    try hfsRequire(threads[parent] == nil, "Duplicate catalog thread.")
                    threads[parent] = (hfs32(bytes, body + 4), threadName, kind == 3)
                } else { throw HFSMetadataError.invalid("Unknown catalog record type.") }
            }
            if leaf { leaves.append(number) }
        }
        try visit(root, depth)
        try hfsRequire(recordCount == expectedRecords && leaves.first == firstLeaf && leaves.last == lastLeaf && entries.count == threads.count, "Catalog header/tree counts disagree.")
        for (index, number) in leaves.enumerated() {
            let base = Int(number) * nodeSize
            try hfsRequire(hfs32(bytes, base) == (index + 1 < leaves.count ? leaves[index + 1] : 0) &&
                hfs32(bytes, base + 4) == (index > 0 ? leaves[index - 1] : 0), "Catalog leaf links disagree with tree traversal.")
        }
        try hfsRequire(entries[2]?.folder == true && entries[2]?.parent == 1, "Missing HFS root folder.")
        for entry in entries.values {
            guard let thread = threads[entry.id] else { throw HFSMetadataError.invalid("Missing object thread.") }
            try hfsRequire(thread.0 == entry.parent && thread.1 == entry.name && thread.2 == entry.folder, "Catalog object/thread disagreement.")
            if entry.id != 2 { try hfsRequire(entries[entry.parent]?.folder == true, "Missing catalog parent.") }
        }
        for data in dataForks where data.size != 0 {
            try hfsRequire(data.offset >= volume + 1536 && data.offset + data.allocated <= volume + volumeSize - 1024 &&
                reserved.allSatisfy { data.offset + data.allocated <= $0.offset || $0.offset + $0.allocated <= data.offset }, "Data fork overlaps filesystem metadata.")
        }
        let targets = entries.values.filter { $0.parent == 2 && $0.name == "Install PS1-2.app" && $0.folder }
        try hfsRequire(targets.count == 1, "Expected one Install PS1-2.app at the image root.")
        let target = targets[0].id
        let generated: [UInt8] = (0..<32).map { (10..<14).contains($0) ? 255 : 0 }
        var offsets: [UInt64] = []
        var targetEntries = 0
        var executableNames = Set<String>()
        for entry in entries.values {
            var current = entry.id
            var ancestry = Set<UInt32>()
            var inside = false
            while current != 2 {
                try hfsRequire(ancestry.count < 256 && ancestry.insert(current).inserted, "Cyclic/deep catalog ancestry.")
                if current == target { inside = true }
                guard let object = entries[current] else { throw HFSMetadataError.invalid("Missing catalog ancestor.") }
                current = object.parent
            }
            if !inside { continue }
            targetEntries += 1
            try hfsRequire(entry.metadata.allSatisfy { $0 == 0 } || entry.metadata == generated, "Unexpected FinderInfo on \(entry.name); refusing broad cleanup.")
            if entry.metadata == generated { offsets.append(entry.coordinateOffset) }
            if !entry.folder {
                try hfsRequire(hfs64(entry.resourceFork, 0) == 0 && hfs32(entry.resourceFork, 12) == 0 &&
                    entry.resourceFork[16..<80].allSatisfy { $0 == 0 }, "Resource fork is not permitted in signed installer.")
                if ["SetupWizard", "InspectMachO", "MoveApp"].contains(entry.name) {
                    try hfsRequire(entry.mode & 0o111 != 0, "Installer helper lost executable mode.")
                    executableNames.insert(entry.name)
                }
            }
        }
        try hfsRequire(executableNames == Set(["SetupWizard", "InspectMachO", "MoveApp"]), "Required installer executables are absent.")
        return HFSMetadataReport(entries: targetEntries, coordinateOffsets: offsets.sorted())
    }
}

#if !HFS_METADATA_TESTS
@main
struct NormalizeHFSCommand {
    static func main() {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 && ["--check", "--normalize"].contains(arguments[1]) else {
            fputs("Usage: NormalizeHFS --normalize|--check /absolute/makehybrid-image.dmg\n", stderr)
            exit(2)
        }
        do {
            let report = try HFSMetadataNormalizer.process(path: arguments[2], normalize: arguments[1] == "--normalize")
            print("HFS+ installer metadata verified: \(report.entries) entries, \(report.coordinateOffsets.count) generated FinderInfo coordinates normalized.")
        } catch { fputs("HFS+ metadata error: \(error)\n", stderr); exit(1) }
    }
}
#endif
