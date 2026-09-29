import Foundation
import Combine

@main
struct LibrarySettingsTests {
    @MainActor
    static func main() throws {
        let fm = FileManager.default
        let testRoot = fm.temporaryDirectory.appendingPathComponent("PS12-library-settings-\(UUID().uuidString)", isDirectory: true)
        let localPS1 = testRoot.appendingPathComponent("PlayStation 1 — Jogos", isDirectory: true)
        let localPS2 = testRoot.appendingPathComponent("PlayStation 2", isDirectory: true)
        try fm.createDirectory(at: localPS1, withIntermediateDirectories: true)
        try fm.createDirectory(at: localPS2, withIntermediateDirectories: true)
        let suite = "local.ps12.tests.library-settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? fm.removeItem(at: testRoot)
        }
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            checks += 1
            precondition(condition, "FAIL: \(message)")
        }
        func saved(_ path: String, volumePath: String? = nil, volumeName: String = "Disco local", version: Int = 1) throws -> Data {
            var object: [String: Any] = ["version": version, "path": path, "volumeName": volumeName]
            if let volumePath { object["volumePath"] = volumePath }
            return try JSONSerialization.data(withJSONObject: object)
        }
        let settings = GameLibrarySettings(defaults: defaults)
        check(settings.locations.count == 2, "only two console preferences")
        check(settings.folder(for: "ps1").path == "/Volumes/Extreme SSD/Emulacao/PS1/Jogos", "PS1 retains original default")
        check(settings.folder(for: "ps2").path == "/Volumes/Extreme SSD/Emulacao/PS2/Jogos", "PS2 retains original default")
        check(settings.location(for: "ps1").isExternal, "default volume is external")
        check(settings.location(for: "ps2").volumeName == "Extreme SSD", "default volume label retained")
        check(defaults.data(forKey: GameLibrarySettings.storageKey(for: "ps1")) == nil, "initialization does not write defaults")

        var notifications = 0
        let observation = settings.$locations.dropFirst().sink { _ in notifications += 1 }
        check(try settings.setFolder(localPS1, for: "ps1"), "selecting valid local folder changes PS1")
        check(settings.folder(for: "ps1") == localPS1.standardizedFileURL.resolvingSymlinksInPath(), "selected folder stored")
        check(!settings.location(for: "ps1").isExternal && settings.location(for: "ps1").volumeName == "Disco local", "local volume described accurately")
        check(settings.location(for: "ps2") == GameLibrarySettings.defaultLocation(for: "ps2"), "PS1 selection preserves PS2")
        check(notifications == 1, "selection publishes once")
        check(!(try settings.setFolder(localPS1, for: "ps1")), "same folder is a no-op")
        check(notifications == 1, "same folder does not publish")
        check(try settings.setFolder(localPS2, for: "ps2"), "PS2 has independent folder")
        let restored = GameLibrarySettings(defaults: defaults)
        check(restored.locations == settings.locations, "preferences survive initialization")
        check(restored.folder(for: "ps1") != restored.folder(for: "ps2"), "console folders persist independently")

        let beforeCancel = settings.locations
        let cancelledSelection: URL? = nil
        if let cancelledSelection { _ = try settings.setFolder(cancelledSelection, for: "ps1") }
        check(settings.locations == beforeCancel, "cancelled picker requires no mutation")
        let plainFile = testRoot.appendingPathComponent("game.iso")
        try Data([1]).write(to: plainFile)
        let invalidURLs = [
            plainFile,
            testRoot.appendingPathComponent("Missing", isDirectory: true),
            URL(string: "https://example.com/Games")!,
            URL(string: "file://remote.example/Games")!,
            URL(string: "file:///tmp/Games?query=value")!,
            URL(string: "file:///tmp/Games#fragment")!
        ]
        for invalidURL in invalidURLs {
            do {
                _ = try settings.setFolder(invalidURL, for: "ps1")
                check(false, "invalid selection must throw: \(invalidURL)")
            } catch {
                check(settings.locations == beforeCancel, "invalid selection leaves settings unchanged")
            }
        }
        let rootAlias = testRoot.appendingPathComponent("RootAlias", isDirectory: true)
        try fm.createSymbolicLink(at: rootAlias, withDestinationURL: URL(fileURLWithPath: "/", isDirectory: true))
        for rootSelection in [URL(fileURLWithPath: "/", isDirectory: true), rootAlias] {
            do {
                _ = try settings.setFolder(rootSelection, for: "ps1")
                check(false, "filesystem root or its alias must be rejected")
            } catch GameLibrarySettingsError.filesystemRoot {
                check(settings.locations == beforeCancel, "root rejection keeps existing folder and gives dedicated explanation")
            } catch {
                check(false, "root selection must give the dedicated-folder guidance")
            }
        }
        do {
            _ = try settings.setFolder(localPS1, for: "ps3")
            check(false, "unsupported console rejected")
        } catch { check(settings.locations == beforeCancel, "unsupported console leaves settings unchanged") }
        check(!settings.reset(for: "ps3"), "unknown console reset is no-op")

        // Deleted selected folders remain saved: launch-time validation, not
        // startup preference loading, decides whether games are available.
        try fm.removeItem(at: localPS1)
        check(GameLibrarySettings(defaults: defaults).folder(for: "ps1") == restored.folder(for: "ps1"), "missing local folder preserved after restart")
        check(settings.reset(for: "ps1"), "reset restores original SSD without requiring it to be mounted")
        check(settings.location(for: "ps1") == GameLibrarySettings.defaultLocation(for: "ps1"), "reset restores volume metadata")
        check(defaults.data(forKey: GameLibrarySettings.storageKey(for: "ps1")) == nil, "reset removes only PS1 preference")
        check(settings.folder(for: "ps2") == restored.folder(for: "ps2"), "reset does not change other console")
        check(!settings.reset(for: "ps1"), "repeated reset returns no change")
        check(GameLibrarySettings(defaults: defaults).locations == settings.locations, "reset survives restart")

        let offlineMount = "/Volumes/PS12-test-offline-\(UUID().uuidString)"
        let offlinePath = offlineMount + "/Jogos PS1"
        defaults.set(try saved(offlinePath, volumePath: offlineMount, volumeName: "Meu SSD"), forKey: GameLibrarySettings.storageKey(for: "ps1"))
        let offline = GameLibrarySettings(defaults: defaults)
        check(offline.folder(for: "ps1").path == offlinePath, "disconnected external path restored unchanged")
        check(offline.location(for: "ps1").volumePath == offlineMount && offline.location(for: "ps1").volumeName == "Meu SSD", "offline volume root and label retained")
        check(offline.location(for: "ps1").isExternal, "offline selection remains external")
        check(offline.reset(for: "ps1"), "offline custom folder can be reset without a disk access")
        defaults.set(try saved(offlineMount, volumePath: offlineMount, volumeName: "Meu SSD"), forKey: GameLibrarySettings.storageKey(for: "ps1"))
        check(GameLibrarySettings(defaults: defaults).folder(for: "ps1").path == offlineMount, "an external volume's root remains a supported folder")

        let invalidData = try [
            Data("broken JSON".utf8),
            saved("/"),
            saved("relative/Games"),
            saved("//remote/Games"),
            saved("/tmp/../Games"),
            saved("/tmp/./Games"),
            saved("/tmp//Games"),
            saved("/tmp/Games/"),
            saved("/tmp/Games\n"),
            saved("/tmp/Games", version: 99),
            saved("/tmp/Games", volumeName: ""),
            saved("/Volumes/DiskTwo/Games", volumePath: "/Volumes/Disk"),
            saved("/tmp/Games", volumePath: "/"),
            saved("/tmp/Games", volumePath: "relative"),
            saved("/tmp/Games", volumeName: String(repeating: "x", count: 1025)),
            Data(repeating: 32, count: 16 * 1024 + 1)
        ]
        for data in invalidData {
            defaults.set(data, forKey: GameLibrarySettings.storageKey(for: "ps1"))
            let invalid = GameLibrarySettings(defaults: defaults)
            check(invalid.location(for: "ps1") == GameLibrarySettings.defaultLocation(for: "ps1"), "invalid stored paths fall back lexically")
            check(invalid.folder(for: "ps2") == restored.folder(for: "ps2"), "malformed PS1 record preserves PS2")
            check(defaults.data(forKey: GameLibrarySettings.storageKey(for: "ps1")) == data, "initialization does not silently rewrite malformed preferences")
        }
        let roundTrip = try JSONDecoder().decode(GameLibraryLocation.self, from: JSONEncoder().encode(restored.location(for: "ps2")))
        check(roundTrip == restored.location(for: "ps2"), "location Codable round-trip")
        observation.cancel()
        print("PASS: \(checks) game-library settings checks; independent consoles, observable no-ops, isolated persistence, offline startup/reset, cancellation, invalid folder/record rejection. No real preferences or game files changed.")
    }
}
