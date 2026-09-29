import Foundation

@main
struct GameLaunchCheckTests {
    static func main() throws {
        let fm = FileManager.default
        let temporary = fm.temporaryDirectory.appendingPathComponent("PS12-launch-checks-\(UUID().uuidString)", isDirectory: true)
        let root = temporary.appendingPathComponent("Games", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temporary) }
        @discardableResult func file(_ name: String, _ text: String = "game data") throws -> URL {
            let url = root.appendingPathComponent(name)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
            return url
        }
        var checks = 0
        func check(_ url: URL, _ expected: Bool, _ description: String) {
            checks += 1
            precondition(GameLaunchCheck.isAvailable(url, library: root) == expected, "FAIL: \(description)")
        }
        let iso = try file("Single.iso")
        check(iso, true, "standalone ISO available")
        check(try file("Empty.iso", ""), false, "empty image rejected")
        check(root.appendingPathComponent("Missing.iso"), false, "missing image rejected")
        check(try file("NotPlayable.txt"), false, "unsupported entry rejected")
        let bin = try file("Disc/Track 1.bin")
        _ = try file("Disc/Track2.bin")
        let cue = try file("Disc/Game.cue", "FILE \"Track 1.bin\" BINARY\n TRACK 01 MODE2/2352\nFILE Track2.bin BINARY\n TRACK 02 AUDIO\n")
        check(cue, true, "quoted and unquoted CUE dependencies available")
        try fm.removeItem(at: bin)
        check(cue, false, "CUE rejected when one track is missing")
        try Data([1]).write(to: bin)
        check(try file("Disc/Bad.cue", "FILE \"Track 1.bin\" BINARY\n"), false, "CUE without TRACK rejected")
        check(try file("Disc/Malformed.cue", "FILE \"Track 1.bin\" BINARY\nFILE\n TRACK 01 MODE2/2352\n"), false, "malformed CUE FILE line rejected")
        let ccd = try file("Clone/Clone.ccd", "[CloneCD]\nVersion=3\n")
        let img = try file("Clone/Clone.img")
        check(ccd, true, "CCD with IMG available")
        try fm.removeItem(at: img)
        check(ccd, false, "CCD missing IMG rejected")
        try Data().write(to: img)
        check(ccd, false, "CCD empty IMG rejected")
        try Data([1]).write(to: img)
        let playlist = try file("Compilation.m3u", "#EXTM3U\nSingle.iso\nDisc/Game.cue\nClone/Clone.ccd\n")
        check(playlist, true, "playlist validates standalone and descriptor members")
        let nested = try file("Nested.m3u", "Compilation.m3u\n")
        check(nested, true, "bounded nested playlist valid")
        try fm.removeItem(at: img)
        check(playlist, false, "playlist rejects missing nested CCD dependency")
        try Data([1]).write(to: img)
        check(try file("Empty.m3u", "#EXTM3U\n"), false, "empty playlist rejected")
        check(try file("Self.m3u", "Self.m3u\n"), false, "self-cycle rejected")
        let cycle = try file("Cycle1.m3u", "Cycle2.m3u\n")
        _ = try file("Cycle2.m3u", "Cycle1.m3u\n")
        check(cycle, false, "mutual cycle rejected")
        check(try file("Huge.m3u", String(repeating: "#", count: 128 * 1024 + 1)), false, "oversized playlist rejected")
        check(try file("Huge.cue", String(repeating: " ", count: 128 * 1024 + 1)), false, "oversized CUE rejected")
        check(try file("Many.m3u", String(repeating: "Single.iso\n", count: 513)), false, "reference count bound enforced")
        for index in 0..<10 { _ = try file("Depth\(index).m3u", index == 9 ? "Single.iso\n" : "Depth\(index + 1).m3u\n") }
        check(root.appendingPathComponent("Depth0.m3u"), false, "depth bound enforced")
        let outside = temporary.appendingPathComponent("Outside.iso")
        try Data([1]).write(to: outside)
        check(outside, false, "selected file outside library rejected")
        check(try file("Escape.m3u", "../Outside.iso\n"), false, "playlist traversal escape rejected")
        check(try file("Absolute.m3u", outside.path + "\n"), false, "absolute playlist reference rejected")
        let link = root.appendingPathComponent("Linked.iso")
        try fm.createSymbolicLink(at: link, withDestinationURL: outside)
        check(link, false, "selected symlink escape rejected")
        check(try file("Link.m3u", "Linked.iso\n"), false, "symlink dependency escape rejected")
        check(try file("Escape.cue", "FILE \"../Outside.iso\" BINARY\n TRACK 01 MODE2/2352\n"), false, "CUE traversal escape rejected")
        check(try file(".hidden/Secret.iso"), false, "hidden entry rejected")
        check(root, false, "directory is not a game")
        print("PASS: \(checks) selected-game launch checks; standalone/CUE/CCD/M3U, missing/empty dependencies, traversal/symlink containment, cycle/depth/count/size bounds. No catalog scan or emulator launch.")
    }
}
