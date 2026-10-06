import Foundation
import CoreGraphics
import ImageIO
import Darwin

/// Synthetic ROM bytes and generated artwork only. Never reads installed games,
/// emulator settings, the real SSD or the user's catalog/thumbnail cache.
@main
@MainActor
struct PortableCoverTests {
    private static var checks = 0

    struct Fixture {
        let directory: URL
        let root: URL
        let console: String
        var portable: URL { root.appendingPathComponent("Capas", isDirectory: true) }
        var snapshots: URL { directory.appendingPathComponent("snapshots", isDirectory: true) }
        var thumbnails: URL { directory.appendingPathComponent("thumbnails", isDirectory: true) }
        var source: CatalogSource {
            CatalogSource(consoleKey: console, root: root,
                          covers: directory.appendingPathComponent("No emulator installed/covers"), database: nil)
        }

        init(_ base: URL, _ name: String, console: String = "ps2") throws {
            directory = base.appendingPathComponent(name, isDirectory: true)
            root = directory.appendingPathComponent("Library on USB", isDirectory: true)
            self.console = console
            try FileManager.default.createDirectory(at: portable, withIntermediateDirectories: true)
        }

        @discardableResult func game(_ relative: String) throws -> URL {
            let file = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1, 2, 3]).write(to: file)
            return file
        }
    }

    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("ps12-portable-cover-fixtures-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try freshInstallAndMatching(root)
        try precedenceAndValidation(root)
        try sharedSerialAndAmbiguity(root)
        try symlinkIsolation(root)
        try await relocation(root)
        try await refreshAndOffline(root)
        print("PASS: \(checks) portable-cover assertions; fresh PS1/PS2 libraries, exact and unambiguous matching, portrait validation, relocated SSD roots, refresh invalidation and persistent offline artwork.")
    }

    private static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        guard value() else { fatalError("FAIL: \(message)") }
        checks += 1
    }

    private static func sameFile(_ lhs: URL?, _ rhs: URL) -> Bool {
        lhs?.standardizedFileURL.resolvingSymlinksInPath().path == rhs.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func game(_ result: CatalogScanResult, _ filename: String) -> CatalogGame {
        let matches = result.games.filter { $0.fileURL.lastPathComponent == filename }
        check(matches.count == 1, "one game for \(filename)")
        return matches[0]
    }

    @discardableResult
    private static func image(_ file: URL, width: Int = 72, height: Int = 100, red: CGFloat = 0.6,
                              inPlace: Bool = false) throws -> URL {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            fatalError("Could not create generated artwork")
        }
        context.setFillColor(CGColor(red: red, green: 0.25, blue: 1 - red, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        guard let artwork = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            fatalError("Could not encode generated artwork")
        }
        CGImageDestinationAddImage(destination, artwork, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("Could not finalize artwork") }
        if inPlace {
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: data as Data)
        } else {
            try (data as Data).write(to: file, options: .atomic)
        }
        return file
    }

    private static func freshInstallAndMatching(_ base: URL) throws {
        for console in ["ps1", "ps2"] {
            let f = try Fixture(base, "fresh-\(console)", console: console)
            let disc = try f.game("Tarzan.iso")
            _ = try f.game("Capas/Not a Game.iso")
            _ = try f.game("Capas/Nested/Also Not a Game.bin")
            let cover = try image(f.portable.appendingPathComponent("Tarzan.png"), width: console == "ps1" ? 100 : 72)
            check(!FileManager.default.fileExists(atPath: f.source.covers.path) && f.source.database == nil,
                  "fresh fixture has no emulator artwork or database")
            let result = CatalogScanner.scan(f.source)
            check(result.games.count == 1 && result.warning == nil, "Capas is excluded from \(console) game enumeration")
            check(sameFile(result.games.first?.fileURL, disc), "real game survives Capas filtering")
            check(sameFile(result.games.first?.coverURL, cover), "\(console) matches portable artwork without local dependencies")
            check(sameFile(CatalogScanner.coverForLoadedGame(path: disc.path, source: f.source), cover),
                  "loaded-game lookup uses portable artwork too")
        }

        let f = try Fixture(base, "matching-keys")
        _ = try f.game("SLUS-21065 Exact Name.iso")
        _ = try f.game("SLUS-21369 Title Only.iso")
        _ = try f.game("SLUS-21572 Serial Only.iso")
        _ = try f.game("SLUS-20000 Unknown Alias.iso")
        let exact = try image(f.portable.appendingPathComponent("SLUS-21065 Exact Name.png"))
        let title = try image(f.portable.appendingPathComponent("Title Only.png"))
        let serial = try image(f.portable.appendingPathComponent("SLUS-21572.png"))
        let official = try image(f.portable.appendingPathComponent("Official Database Name.png"))
        let db = f.directory.appendingPathComponent("SyntheticGameIndex.yaml")
        try Data("SLUS-20000:\n  name: Official Database Name\n".utf8).write(to: db)
        let source = CatalogSource(consoleKey: "ps2", root: f.root, covers: f.source.covers, database: db)
        let result = CatalogScanner.scan(source)
        check(sameFile(game(result, "SLUS-21065 Exact Name.iso").coverURL, exact), "full filename wins")
        check(sameFile(game(result, "SLUS-21369 Title Only.iso").coverURL, title), "unique display title matches")
        check(sameFile(game(result, "SLUS-21572 Serial Only.iso").coverURL, serial), "unique serial matches")
        check(sameFile(game(result, "SLUS-20000 Unknown Alias.iso").coverURL, official), "unique official database name matches")
    }

    private static func precedenceAndValidation(_ base: URL) throws {
        let f = try Fixture(base, "precedence")
        _ = try f.game("Only/Preferred.iso")
        let portable = try image(f.portable.appendingPathComponent("Preferred.png"))
        let fronts = f.directory.appendingPathComponent("Bundled fronts", isDirectory: true)
        let front = try image(fronts.appendingPathComponent("Preferred.png"))
        let emulator = try image(f.source.covers.appendingPathComponent("Preferred.png"))
        _ = try image(f.root.appendingPathComponent("Only/Preferred.png"))
        let source = CatalogSource(consoleKey: "ps2", root: f.root, covers: f.source.covers, database: nil, frontCovers: fronts)
        check(sameFile(CatalogScanner.scan(source).games.first?.coverURL, portable), "portable art overrides bundled, emulator and nearby art")
        try image(portable, width: 150, height: 100)
        check(sameFile(CatalogScanner.scan(source).games.first?.coverURL, front), "invalid portable spread does not suppress bundled fallback")
        try FileManager.default.removeItem(at: front)
        check(sameFile(CatalogScanner.scan(source).games.first?.coverURL, emulator), "invalid portable spread does not suppress emulator fallback")

        let wrong = try Fixture(base, "wrong-portable-ps2")
        _ = try wrong.game("Spread.iso")
        _ = try wrong.game("Square.iso")
        _ = try wrong.game("Corrupt.iso")
        try image(wrong.portable.appendingPathComponent("Spread.png"), width: 150, height: 100)
        try image(wrong.portable.appendingPathComponent("Square.png"), width: 100, height: 100)
        try Data("not image bytes".utf8).write(to: wrong.portable.appendingPathComponent("Corrupt.png"))
        let result = CatalogScanner.scan(wrong.source)
        check(result.games.count == 3 && result.games.allSatisfy { $0.coverURL == nil },
              "portable PS2 spread, square and corrupt artwork are rejected")
    }

    private static func sharedSerialAndAmbiguity(_ base: URL) throws {
        let f = try Fixture(base, "shared-serial")
        for title in ["Mod Alpha", "Mod Beta", "Mod Gamma"] { _ = try f.game("SLUS-21065 \(title).iso") }
        let alpha = try image(f.portable.appendingPathComponent("SLUS-21065 Mod Alpha.png"))
        let beta = try image(f.portable.appendingPathComponent("SLUS-21065 Mod Beta.png"))
        _ = try image(f.portable.appendingPathComponent("SLUS-21065.png"))
        let result = CatalogScanner.scan(f.source)
        check(sameFile(game(result, "SLUS-21065 Mod Alpha.iso").coverURL, alpha), "first mod keeps its exact portable art")
        check(sameFile(game(result, "SLUS-21065 Mod Beta.iso").coverURL, beta), "second mod keeps different exact portable art")
        check(game(result, "SLUS-21065 Mod Gamma.iso").coverURL == nil, "shared serial is not guessed for a mod lacking exact artwork")

        let duplicate = try Fixture(base, "ambiguous-name")
        _ = try duplicate.game("First/Duplicate.iso")
        _ = try duplicate.game("Second/Duplicate.iso")
        _ = try duplicate.game("FIFA Street.iso")
        _ = try duplicate.game("FIFA-Street.iso")
        _ = try image(duplicate.portable.appendingPathComponent("Duplicate.png"))
        _ = try image(duplicate.portable.appendingPathComponent("FIFA Street.png"))
        let ambiguous = CatalogScanner.scan(duplicate.source)
        check(ambiguous.games.count == 4 && ambiguous.games.allSatisfy { $0.coverURL == nil },
              "duplicate basenames and normalized title collisions do not share global portable art")
    }

    private static func relocation(_ base: URL) async throws {
        for console in ["ps1", "ps2"] {
            let f = try Fixture(base, "relocation-\(console)", console: console)
            _ = try f.game("Unique Adventure.iso")
            _ = try image(f.portable.appendingPathComponent("Unique Adventure.png"), width: console == "ps1" ? 100 : 72)
            let relocated = f.directory.appendingPathComponent("Another Mac/Another Disk/Library with a different name", isDirectory: true)
            try FileManager.default.createDirectory(at: relocated.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: f.root, to: relocated)
            let source = CatalogSource(consoleKey: console, root: relocated,
                                       covers: f.directory.appendingPathComponent("Different user without emulator/covers"), database: nil)
            let fresh = CatalogCache(directory: f.snapshots)
            let noSnapshot = await fresh.loadSaved(source)
            check(noSnapshot == nil, "new Mac begins without a saved catalog")
            let result = await fresh.load(source)
            let expectedCover = relocated.appendingPathComponent("Capas/Unique Adventure.png")
            check(result.games.count == 1 && sameFile(result.games.first?.coverURL, expectedCover),
                  "\(console) portable art survives a differently named disk/root with empty local cache")
            check(result.games.allSatisfy { $0.fileURL.path.hasPrefix(relocated.path + "/") }, "relocated games use no old absolute path")
            check(!FileManager.default.fileExists(atPath: f.root.path), "original library is absent in relocation test")
            let thumbnails = CoverImageCache(directory: f.thumbnails)
            let decoded = await thumbnails.image(at: expectedCover, maxPixelSize: 100, snapshotID: result.snapshotID)
            check(decoded != nil, "fresh relocated artwork decodes from portable storage")
        }
    }

    private static func symlinkIsolation(_ base: URL) throws {
        let fileFixture = try Fixture(base, "symlink-file")
        _ = try fileFixture.game("Linked.iso")
        let externalImage = try image(fileFixture.directory.appendingPathComponent("Outside library/Linked.png"))
        let link = fileFixture.portable.appendingPathComponent("Linked.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: externalImage)
        let fileResult = CatalogScanner.scan(fileFixture.source)
        check(fileResult.games.count == 1 && fileResult.games.first?.coverURL == nil,
              "portable image symlinks are not treated as self-contained artwork")

        let folderFixture = try Fixture(base, "symlink-directory")
        _ = try folderFixture.game("Linked.iso")
        let outside = folderFixture.directory.appendingPathComponent("Outside covers", isDirectory: true)
        _ = try image(outside.appendingPathComponent("Linked.png"))
        try FileManager.default.removeItem(at: folderFixture.portable)
        try FileManager.default.createSymbolicLink(at: folderFixture.portable, withDestinationURL: outside)
        let folderResult = CatalogScanner.scan(folderFixture.source)
        check(folderResult.games.count == 1 && folderResult.games.first?.coverURL == nil,
              "symlinked Capas directory cannot silently depend on artwork outside the library")
    }

    private static func refreshAndOffline(_ base: URL) async throws {
        let f = try Fixture(base, "refresh-offline")
        _ = try f.game("Saved.iso")
        _ = try f.game("New.iso")
        let cover = try image(f.portable.appendingPathComponent("Saved.png"))
        let newCover = f.portable.appendingPathComponent("New.png")
        let catalog = CatalogCache(directory: f.snapshots)
        let thumbnails = CoverImageCache(directory: f.thumbnails)
        let initial = await catalog.load(f.source)
        check(initial.snapshotID != nil && initial.games.count == 2, "initial full load saves a catalog snapshot")
        check(game(initial, "New.iso").coverURL == nil, "initial snapshot has no not-yet-created cover")
        let initialImage = await thumbnails.image(at: cover, maxPixelSize: 100, snapshotID: initial.snapshotID)
        check(initialImage?.width == 72 && initialImage?.height == 100, "initial portable image is cached locally")
        let initialStats = await catalog.statistics()

        var parentBefore = stat()
        check(lstat(f.portable.path, &parentBefore) == 0, "record portable directory metadata before in-place image edit")
        try image(cover, width: 70, height: 100, red: 0.1, inPlace: true)
        var parentAfter = stat()
        check(lstat(f.portable.path, &parentAfter) == 0 && parentBefore.st_ino == parentAfter.st_ino
              && parentBefore.st_mtimespec.tv_sec == parentAfter.st_mtimespec.tv_sec
              && parentBefore.st_mtimespec.tv_nsec == parentAfter.st_mtimespec.tv_nsec
              && parentBefore.st_ctimespec.tv_sec == parentAfter.st_ctimespec.tv_sec
              && parentBefore.st_ctimespec.tv_nsec == parentAfter.st_ctimespec.tv_nsec,
              "in-place artwork edit does not change parent-directory metadata")
        let saved = await catalog.load(f.source)
        let savedImage = await thumbnails.image(at: cover, maxPixelSize: 100, snapshotID: saved.snapshotID)
        let savedStats = await catalog.statistics()
        check(saved.games == initial.games && saved.snapshotID == initial.snapshotID, "normal catalog reads preserve the last full load")
        check(savedStats.scans == initialStats.scans && savedStats.fingerprintChecks == initialStats.fingerprintChecks,
              "normal browsing does not stat or scan portable artwork")
        check(savedImage?.width == 72, "saved snapshot retains its prior thumbnail until refresh")

        let edited = await catalog.load(f.source, force: true)
        check(edited.snapshotID != initial.snapshotID, "explicit refresh fingerprints in-place artwork edits even with unchanged directory metadata")
        try image(newCover)
        let beforeAdditionRefresh = await catalog.load(f.source)
        check(beforeAdditionRefresh.games == edited.games && beforeAdditionRefresh.snapshotID == edited.snapshotID,
              "newly added artwork waits for the next explicit refresh")
        let updated = await catalog.load(f.source, force: true)
        check(updated.snapshotID != edited.snapshotID, "explicit refresh fingerprints new portable image")
        check(sameFile(game(updated, "New.iso").coverURL, newCover), "explicit refresh discovers newly added portable artwork")
        let changed = await thumbnails.image(at: cover, maxPixelSize: 100, snapshotID: updated.snapshotID)
        check(changed?.width == 70 && changed?.height == 100, "new catalog snapshot invalidates changed-image thumbnail")
        let newImage = await thumbnails.image(at: newCover, maxPixelSize: 100, snapshotID: updated.snapshotID)
        check(newImage != nil, "new portable artwork is warmed before disconnect")
        let decodedStats = await thumbnails.statistics()
        check(decodedStats.sourceDecodes == 3, "only initial, changed and newly added images require source decoding")

        let cachedFiles = try FileManager.default.contentsOfDirectory(at: f.snapshots, includingPropertiesForKeys: nil)
        check(cachedFiles.count == 1, "one source uses one persistent snapshot file")
        let snapshotBytes = try Data(contentsOf: cachedFiles[0])
        try FileManager.default.moveItem(at: f.root, to: f.directory.appendingPathComponent("Disconnected USB"))
        let restarted = CatalogCache(directory: f.snapshots)
        let offline = await restarted.loadSaved(f.source)
        check(offline?.games == updated.games && offline?.snapshotID == updated.snapshotID, "restart restores portable-cover catalog offline")
        let offlineStats = await restarted.statistics()
        check(offlineStats.scans == 0 && offlineStats.fingerprintChecks == 0 && offlineStats.diskHits == 1,
              "offline startup never consults the disconnected library")
        let restartedImages = CoverImageCache(directory: f.thumbnails)
        let offlineImage = await restartedImages.image(at: cover, maxPixelSize: 100, snapshotID: offline?.snapshotID)
        let offlineNew = await restartedImages.image(at: newCover, maxPixelSize: 100, snapshotID: offline?.snapshotID)
        let offlineImageStats = await restartedImages.statistics()
        check(offlineImage?.width == 70 && offlineNew != nil, "persistent thumbnails remain visible without portable sources")
        check(offlineImageStats.sourceDecodes == 0 && offlineImageStats.diskHits == 2, "offline images come only from local disk cache")
        let failed = await restarted.load(f.source, force: true)
        check(failed.games == updated.games && failed.snapshotID == updated.snapshotID && failed.warning != nil,
              "disconnected explicit refresh preserves saved catalog and explains failure")
        let bytesAfterFailure = try Data(contentsOf: cachedFiles[0])
        check(bytesAfterFailure == snapshotBytes, "failed refresh preserves persistent snapshot bytes")
    }
}
