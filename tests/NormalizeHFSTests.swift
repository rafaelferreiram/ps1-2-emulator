import Foundation
import Darwin

@main
struct NormalizeHFSTests {
    static func main() throws {
        let root = URL(fileURLWithPath: "/private/tmp/PS12HFSTests-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        var checks = 0
        func expect(_ value: Bool, _ message: String) {
            guard value else { fatalError(message) }; checks += 1
        }
        func run(_ executable: String, _ arguments: [String]) throws -> (Int32, String) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe; process.standardError = pipe
            try process.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: output, as: UTF8.self))
        }
        func succeeds(_ executable: String, _ arguments: [String], _ message: String) throws {
            let result = try run(executable, arguments)
            expect(result.0 == 0, "\(message): \(result.1)")
        }
        func rejectsPath(_ path: String, _ message: String) {
            do { _ = try HFSMetadataNormalizer.process(path: path, normalize: true); fatalError(message) }
            catch { checks += 1 }
        }
        let executable = CommandLine.arguments[1]
        let imageRoot = root.appendingPathComponent("image")
        let app = imageRoot.appendingPathComponent("Install PS1-2.app")
        let macos = app.appendingPathComponent("Contents/MacOS")
        let resources = app.appendingPathComponent("Contents/Resources")
        try fm.createDirectory(at: macos, withIntermediateDirectories: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        let helper = resources.appendingPathComponent("InspectMachO")
        for destination in [macos.appendingPathComponent("SetupWizard"), helper, resources.appendingPathComponent("MoveApp")] {
            try fm.copyItem(atPath: executable, toPath: destination.path)
            try succeeds("/usr/bin/codesign", ["--force", "--sign", "-", destination.path], "Sign fixture helper")
        }
        let plist: [String: Any] = ["CFBundleExecutable": "SetupWizard", "CFBundleIdentifier": "local.ps12.hfsfixture", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        try Data("signed content\n".utf8).write(to: resources.appendingPathComponent("fixture.txt"))
        try Data("outside signed bundle\n".utf8).write(to: imageRoot.appendingPathComponent("Read Me.txt"))
        try succeeds("/usr/bin/codesign", ["--force", "--sign", "-", app.path], "Sign fixture bundle")
        try succeeds("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path], "Initial strict verification")
        let quarantine = "0081;00000000;PS12HFSRegression;"
        try succeeds("/usr/bin/xattr", ["-w", "com.apple.quarantine", quarantine, helper.path], "Set fixture quarantine")
        let finderInfo = "00000000000000000000ffffffff000000000000000000000000000000000000"
        try succeeds("/usr/bin/xattr", ["-wx", "com.apple.FinderInfo", finderInfo, helper.path], "Reproduce exact generated FinderInfo")
        let rejected = try run("/usr/bin/codesign", ["--verify", "--strict", helper.path])
        expect(rejected.0 != 0 && rejected.1.contains("resource fork, Finder information, or similar detritus not allowed"), "Exact user's failure reproduced")
        try succeeds("/usr/bin/xattr", ["-d", "com.apple.FinderInfo", helper.path], "Remove only reproduced FinderInfo")
        try succeeds("/usr/bin/codesign", ["--verify", "--strict", helper.path], "Strict signature restored without resigning")
        let retainedQuarantine = try run("/usr/bin/xattr", ["-p", "com.apple.quarantine", helper.path])
        expect(retainedQuarantine.0 == 0 && retainedQuarantine.1.trimmingCharacters(in: .whitespacesAndNewlines) == quarantine, "Quarantine retained")
        let helperBytes = try Data(contentsOf: helper)
        var tampered = helperBytes
        tampered[4096] ^= 1
        try tampered.write(to: helper)
        let tamperResult = try run("/usr/bin/codesign", ["--verify", "--strict", helper.path])
        expect(tamperResult.0 != 0, "Actual executable tampering is still rejected")
        try helperBytes.write(to: helper)
        try succeeds("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path], "Restored fixture has original signature")
        let raw = root.appendingPathComponent("raw.dmg")
        try succeeds("/usr/bin/hdiutil", ["makehybrid", "-hfs", "-hfs-volume-name", "Metadata fixture", "-o", raw.path, imageRoot.path], "Build genuine HFS image")
        let original = try Data(contentsOf: raw)
        let oldCheck = try run(executable, ["--check", raw.path])
        expect(oldCheck.0 != 0 && oldCheck.1.contains("Generated FinderInfo"), "Old makehybrid metadata rejected")
        expect(try Data(contentsOf: raw) == original, "Read-only audit cannot change original image")
        let report = try HFSMetadataNormalizer.process(path: raw.path, normalize: true)
        expect(report.entries >= 10 && report.coordinateOffsets.count == report.entries, "Every fixture file and folder normalized")
        let normalized = try Data(contentsOf: raw)
        var permitted = Set<Int>()
        for offset in report.coordinateOffsets { for byte in 0..<4 { permitted.insert(Int(offset) + byte) } }
        var differences = Set<Int>()
        for index in original.indices where original[index] != normalized[index] {
            differences.insert(index)
            expect(original[index] == 255 && normalized[index] == 0, "Only FF coordinate bytes become zero")
        }
        expect(differences == permitted, "All data forks, root FinderInfo, signatures, permissions and other image bytes unchanged")
        let cleanReport = try HFSMetadataNormalizer.process(path: raw.path, normalize: false)
        expect(cleanReport.entries == report.entries && cleanReport.coordinateOffsets.isEmpty, "Clean image passes audit")
        let second = try HFSMetadataNormalizer.process(path: raw.path, normalize: true)
        let secondBytes = try Data(contentsOf: raw)
        expect(second.coordinateOffsets.isEmpty && secondBytes == normalized, "Normalization is idempotent")
        let compressed = root.appendingPathComponent("final.dmg")
        try succeeds("/usr/bin/hdiutil", ["convert", "-format", "UDZO", "-o", compressed.path, raw.path], "Compress normalized image")
        try succeeds("/usr/bin/hdiutil", ["verify", compressed.path], "Compressed image CRC verification")
        let roundTrip = root.appendingPathComponent("roundtrip")
        try succeeds("/usr/bin/hdiutil", ["convert", "-format", "UDTO", "-o", roundTrip.path, compressed.path], "Decompress final artifact without mounting")
        let finalCheck = try run(executable, ["--check", roundTrip.path + ".cdr"])
        expect(finalCheck.0 == 0, "Final distributed image metadata passes")
        let sourceCheck = try run("/usr/bin/xattr", ["-p", "com.apple.quarantine", helper.path])
        expect(sourceCheck.0 == 0 && sourceCheck.1.trimmingCharacters(in: .whitespacesAndNewlines) == quarantine, "Image normalizer never modifies source quarantine")

        var fixtureIndex = 0
        func rejects(_ changed: Data, _ message: String) throws {
            fixtureIndex += 1
            let url = root.appendingPathComponent("bad-\(fixtureIndex).dmg")
            try changed.write(to: url)
            rejectsPath(url.path, message)
            expect(try Data(contentsOf: url) == changed, "Rejected image was not partially modified: \(message)")
        }
        func changed(_ at: Int, _ replacement: [UInt8], source: Data = original) -> Data {
            var result = source; result.replaceSubrange(at..<(at + replacement.count), with: replacement); return result
        }
        func uint32(_ data: Data, _ offset: Int) -> Int { (0..<4).reduce(0) { ($0 << 8) | Int(data[offset + $1]) } }
        let volume = 64 * 512
        let vh = volume + 1024
        let partitionSize = uint32(original, 1024 + 12) * 512
        let alternate = volume + partitionSize - 1024
        let block = uint32(original, vh + 40)
        let catalog = volume + uint32(original, vh + 288) * block
        let nodeSize = Int(original[catalog + 32]) << 8 | Int(original[catalog + 33])
        let leaf = catalog + uint32(original, catalog + 24) * nodeSize
        try rejects(Data(original.prefix(4096)), "Truncated image")
        try rejects(changed(512, [0, 0]), "Bad partition signature")
        try rejects(changed(1024 + 8, [255, 255, 255, 255]), "Partition offset overflow")
        try rejects(changed(1024 + 12, [255, 255, 255, 255]), "Partition size overflow")
        try rejects(changed(vh, [0, 0]), "Unsupported filesystem")
        try rejects(changed(vh + 4, [0, 0, 0x21, 0]), "Journaled filesystem")
        try rejects(changed(alternate + 16, [0, 0, 0, 0]), "Alternate header disagreement")
        try rejects(changed(catalog + 32, [0, 1]), "Invalid B-tree node size")
        try rejects(changed(catalog + 36, [255, 255, 255, 255]), "Excessive B-tree node count")
        try rejects(changed(catalog + 16, [0, 0, 0, 0]), "Invalid root node")
        try rejects(changed(leaf + 10, [255, 255]), "Excessive leaf record count")
        try rejects(changed(leaf + nodeSize - 2, [0, 0]), "Record overlaps leaf descriptor")
        try rejects(changed(leaf + nodeSize - 4, [255, 255]), "Oversized intermediate offset rejected before record reads")
        try rejects(changed(leaf, [0, 0, 0, 1]), "Leaf link cycle")
        try rejects(changed(Int(report.coordinateOffsets[0]) - 10, [1]), "Non-generated FinderInfo rejected")
        try rejects(changed(Int(report.coordinateOffsets[0]), [0, 255, 255, 255]), "Partial coordinate metadata rejected")
        let helperName = "InspectMachO".data(using: .utf16BigEndian)!
        let nameRange = original.range(of: helperName)!
        let body = nameRange.upperBound
        expect(original[body] == 0 && original[body + 1] == 2, "Located fixture helper's file record")
        try rejects(changed(body + 168 + 7, [1]), "Resource fork rejected")
        try rejects(changed(body + 42, [0x81, 0xa4]), "Lost helper executable mode rejected")
        try rejects(changed(body + 88 + 16, [0, 0, 0, 1]), "Data fork overlapping catalog rejected")
        let symbolic = root.appendingPathComponent("symlink.dmg")
        try fm.createSymbolicLink(at: symbolic, withDestinationURL: raw)
        rejectsPath(symbolic.path, "Final symlink rejected")
        let parentLink = root.appendingPathComponent("linked-parent")
        try fm.createSymbolicLink(at: parentLink, withDestinationURL: root)
        rejectsPath(parentLink.appendingPathComponent("raw.dmg").path, "Parent symlink rejected")
        let hardLink = root.appendingPathComponent("hardlink.dmg")
        try fm.linkItem(at: raw, to: hardLink)
        rejectsPath(raw.path, "Shared hard-linked image rejected")
        try fm.removeItem(at: hardLink)
        let fifo = root.appendingPathComponent("fifo")
        expect(mkfifo(fifo.path, 0o600) == 0, "Create FIFO fixture")
        rejectsPath(fifo.path, "FIFO rejected without blocking")
        rejectsPath(root.path, "Directory rejected")
        rejectsPath("relative.dmg", "Relative path rejected")
        rejectsPath(raw.path + "\0hidden", "NUL path rejected")
        let badCLI = try run(executable, ["--unknown", raw.path])
        expect(badCLI.0 == 2, "Invalid CLI rejected")
        print("PASS: \(checks) HFS metadata assertions; raw-image bytes and exact signature/quarantine regression verified.")
    }
}
