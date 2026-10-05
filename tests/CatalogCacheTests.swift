import Foundation
import Darwin
import Combine

@main
struct CatalogCacheTests {
    static let pixel = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/a1sAAAAASUVORK5CYII=")!

    struct Fixture {
        let directory: URL
        let games: URL
        let covers: URL
        let fronts: URL
        let database: URL
        let cacheDirectory: URL
        var source: CatalogSource { CatalogSource(consoleKey: "ps1", root: games, covers: covers, database: database, frontCovers: fronts) }

        init(_ base: URL, _ name: String) throws {
            directory = base.appendingPathComponent(name, isDirectory: true)
            games = directory.appendingPathComponent("Jogos", isDirectory: true)
            covers = directory.appendingPathComponent("covers", isDirectory: true)
            fronts = directory.appendingPathComponent("fronts", isDirectory: true)
            database = directory.appendingPathComponent("gamedb.yaml")
            cacheDirectory = directory.appendingPathComponent("cache", isDirectory: true)
            for folder in [games, covers, fronts] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
            try Data("SLUS-12345:\n  name: Database Game\n".utf8).write(to: database)
        }

        @discardableResult func game(_ path: String, _ text: String = "game data") throws -> URL {
            let file = games.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file)
            return file
        }
    }

    static func main() async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("PS12-snapshot-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try await snapshotSemantics(temporary)
        try await offlineAndFailure(temporary)
        try await ownership(temporary)
        try await corruptionAndMigration(temporary)
        try await concurrentAndBounds(temporary)
        try await savedOnlyStartup(temporary)
        try await startupModel(temporary)
        try await sourceChanges(temporary)
        try await backgroundRefreshPolicy(temporary)
        try await boundedArtworkPrefetch(temporary)
        print("PASS: FULL LOAD snapshot memory/disk browsing without metadata checks; changes visible only after forced refresh; offline browsing; failed FULL LOAD preserves saved games and disk; exact cached CUE/CCD/M3U ownership; no implicit artwork scan; v1 migration; corrupt/version/source recovery; concurrent coalescing and bounded persistence.")
    }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("FAIL: \(message)") }
    }

    static func sameFile(_ lhs: URL?, _ rhs: URL) -> Bool {
        func lexicalAlias(_ path: String) -> String {
            for prefix in ["/private/var", "/private/tmp", "/private/etc"] {
                if path == prefix || path.hasPrefix(prefix + "/") { return String(path.dropFirst("/private".count)) }
            }
            return path
        }
        return lhs.map { lexicalAlias($0.path) } == lexicalAlias(rhs.path)
    }

    static func snapshotSemantics(_ base: URL) async throws {
        let f = try Fixture(base, "snapshots")
        let firstFile = try f.game("First.iso")
        let art = f.covers.appendingPathComponent("First.png")
        try pixel.write(to: art)
        let cache = CatalogCache(directory: f.cacheDirectory)
        let first = await cache.load(f.source)
        require(first.games.count == 1 && sameFile(first.games[0].coverURL, art) && first.snapshotID != nil, "first load saves full snapshot")
        let initial = await cache.statistics()
        require(initial.scans == 1 && initial.fingerprintChecks >= 2, "first load scans and verifies consistency")
        for _ in 0..<5 {
            let hit = await cache.load(f.source)
            require(hit.games == first.games && hit.snapshotID == first.snapshotID, "memory snapshot stable")
        }
        let warm = await cache.statistics()
        require(warm.scans == initial.scans && warm.fingerprintChecks == initial.fingerprintChecks && warm.memoryHits == 5,
                "repeated memory reads perform zero metadata checks")
        let restored = CatalogCache(directory: f.cacheDirectory)
        let disk = await restored.load(f.source)
        let diskStats = await restored.statistics()
        require(disk.games == first.games && disk.snapshotID == first.snapshotID && diskStats.diskHits == 1
                && diskStats.scans == 0 && diskStats.fingerprintChecks == 0, "disk snapshot opens without traversing library")

        let secondFile = try f.game("Second.iso")
        try FileManager.default.removeItem(at: firstFile)
        try FileManager.default.removeItem(at: art)
        let unchanged = await cache.load(f.source)
        require(unchanged.games == first.games && unchanged.snapshotID == first.snapshotID, "add/delete/cover changes remain invisible until FULL LOAD")
        let renewed = await cache.load(f.source, force: true)
        require(renewed.games.count == 1 && renewed.games[0].title == "Second" && renewed.games[0].coverURL == nil
                && renewed.snapshotID != first.snapshotID, "FULL LOAD replaces snapshot with changed files")
        let renamed = secondFile.deletingLastPathComponent().appendingPathComponent("Renamed.iso")
        try FileManager.default.moveItem(at: secondFile, to: renamed)
        let beforeRenameLoad = await cache.load(f.source)
        require(beforeRenameLoad.games[0].title == "Second", "rename does not trigger automatic rescan")
        let renamedResult = await cache.load(f.source, force: true)
        require(renamedResult.games[0].title == "Renamed", "forced load observes renamed game")
        let newArt = f.covers.appendingPathComponent("Renamed.png")
        try pixel.write(to: newArt)
        let beforeArtLoad = await cache.load(f.source)
        require(beforeArtLoad.games[0].coverURL == nil, "new cover waits for FULL LOAD")
        let afterArtLoad = await cache.load(f.source, force: true)
        require(sameFile(afterArtLoad.games[0].coverURL, newArt), "FULL LOAD incorporates new cover")
        let savedArtID = afterArtLoad.snapshotID
        try pixel.write(to: newArt)
        let samePathBefore = await cache.load(f.source)
        require(samePathBefore.snapshotID == savedArtID, "in-place artwork changes retain saved snapshot ID until refresh")
        let samePathAfter = await cache.load(f.source, force: true)
        require(samePathAfter.snapshotID != savedArtID, "in-place artwork edit creates a new forced snapshot ID")
    }

    static func offlineAndFailure(_ base: URL) async throws {
        let f = try Fixture(base, "offline")
        let game = try f.game("Saved.iso")
        let cover = f.covers.appendingPathComponent("Saved.png")
        try pixel.write(to: cover)
        let cache = CatalogCache(directory: f.cacheDirectory)
        let saved = await cache.load(f.source)
        let file = try FileManager.default.contentsOfDirectory(at: f.cacheDirectory, includingPropertiesForKeys: nil).first!
        let diskBefore = try Data(contentsOf: file)
        let offline = f.directory.appendingPathComponent("Disconnected")
        try FileManager.default.moveItem(at: f.games, to: offline)
        try FileManager.default.removeItem(at: cover)
        let before = await cache.statistics()
        let ram = await cache.load(f.source)
        let after = await cache.statistics()
        require(ram.games == saved.games && ram.snapshotID == saved.snapshotID && after.fingerprintChecks == before.fingerprintChecks,
                "RAM snapshot remains browsable when game tree is removed")
        let coldOffline = CatalogCache(directory: f.cacheDirectory)
        let disk = await coldOffline.load(f.source)
        let coldStats = await coldOffline.statistics()
        require(disk.games == saved.games && coldStats.scans == 0 && coldStats.fingerprintChecks == 0, "disk snapshot remains browsable offline")
        let artwork = await coldOffline.cachedArtworkForLoadedGame(path: game.path, source: f.source)
        require(sameFile(artwork?.url, cover) && artwork?.snapshotID == saved.snapshotID,
                "cached artwork lookup does not require live game or cover readability")
        let failed = await cache.load(f.source, force: true)
        require(failed.games == saved.games && failed.snapshotID == saved.snapshotID && failed.warning?.contains("last saved catalog") == true,
                "failed force returns previous games and explains fallback")
        let diskAfterFailure = try Data(contentsOf: file)
        require(diskAfterFailure == diskBefore, "failed force preserves disk snapshot byte-for-byte")
        let offlineForce = CatalogCache(directory: f.cacheDirectory)
        let failedCold = await offlineForce.load(f.source, force: true)
        require(failedCold.games == saved.games && failedCold.snapshotID == saved.snapshotID && failedCold.warning != nil,
                "forced load on fresh actor retains previous disk snapshot on failure")
        try FileManager.default.createDirectory(at: f.games, withIntermediateDirectories: true)
        _ = try f.game("Replacement.iso")
        let newDisk = await cache.load(f.source)
        require(newDisk.games == saved.games, "different root at same path still waits for explicit FULL LOAD")
        let updated = await cache.load(f.source, force: true)
        require(updated.games.count == 1 && updated.games[0].title == "Replacement", "successful force replaces offline snapshot")
        _ = chmod(f.games.path, 0o000)
        let unreadable = await cache.load(f.source, force: true)
        _ = chmod(f.games.path, 0o755)
        require(unreadable.games == updated.games && unreadable.warning != nil, "unreadable forced refresh retains previous snapshot")

        let emptyCache = CatalogCache(directory: f.directory.appendingPathComponent("empty-cache"))
        let missingSource = CatalogSource(consoleKey: "ps1", root: f.directory.appendingPathComponent("missing"), covers: f.covers, database: nil)
        let absent = await emptyCache.load(missingSource)
        require(absent.games.isEmpty && absent.warning != nil && absent.snapshotID == nil, "without a previous snapshot offline first load is explicit")
    }

    static func ownership(_ base: URL) async throws {
        let f = try Fixture(base, "ownership")
        let bin = try f.game("Series/Disc.bin")
        _ = try f.game("Series/Disc.cue", "FILE \"Disc.bin\" BINARY\n  TRACK 01 MODE2/2352\n")
        let img = try f.game("Series/Second.img")
        _ = try f.game("Series/Second.ccd", "[CloneCD]\nVersion=3\n")
        _ = try f.game("Series/Game.m3u", "Disc.cue\nSecond.ccd\n")
        let cover = f.covers.appendingPathComponent("Game.png")
        try pixel.write(to: cover)
        let cache = CatalogCache(directory: f.cacheDirectory)
        let noSnapshot = await cache.cachedArtworkForLoadedGame(path: bin.path, source: f.source)
        let noGame = await cache.cachedGameForLoadedGame(path: bin.path, source: f.source)
        let noScan = await cache.statistics()
        require(noSnapshot == nil && noGame == nil && noScan.scans == 0 && noScan.fingerprintChecks == 0,
                "artwork and game-owner lookups never create absent inventory")
        let saved = await cache.load(f.source)
        let before = await cache.statistics()
        let cue = await cache.cachedArtworkForLoadedGame(path: bin.path, source: f.source)
        let ccd = await cache.cachedArtworkForLoadedGame(path: img.path, source: f.source)
        let cueGame = await cache.cachedGameForLoadedGame(path: bin.path, source: f.source)
        let ccdGame = await cache.cachedGameForLoadedGame(path: img.path, source: f.source)
        let after = await cache.statistics()
        require(cueGame == saved.games.first && ccdGame == saved.games.first,
                "both CUE/BIN and CCD/IMG identify their exact saved playlist game")
        require(sameFile(cue?.url, cover) && sameFile(ccd?.url, cover) && cue?.snapshotID == saved.snapshotID,
                "playlist uses saved exact CUE/BIN and CCD/IMG membership")
        require(after.fingerprintChecks == before.fingerprintChecks && after.scans == before.scans, "ownership lookup performs no filesystem traversal")
        let persisted = CatalogCache(directory: f.cacheDirectory)
        let restored = await persisted.cachedArtworkForLoadedGame(path: bin.path, source: f.source)
        let persistedStats = await persisted.statistics()
        require(sameFile(restored?.url, cover) && persistedStats.diskHits == 1 && persistedStats.fingerprintChecks == 0,
                "ownership restored directly from disk snapshot")
        _ = try f.game("Series/Other.m3u", "Disc.cue\n")
        let beforeForce = await cache.cachedArtworkForLoadedGame(path: bin.path, source: f.source)
        require(sameFile(beforeForce?.url, cover), "new competing owner ignored until FULL LOAD")
        _ = await cache.load(f.source, force: true)
        let ambiguous = await cache.cachedArtworkForLoadedGame(path: bin.path, source: f.source)
        let ambiguousGame = await cache.cachedGameForLoadedGame(path: bin.path, source: f.source)
        require(ambiguous == nil && ambiguousGame == nil, "two saved playlist owners are never guessed")
        let outside = await cache.cachedArtworkForLoadedGame(path: f.directory.appendingPathComponent("Game.iso").path, source: f.source)
        require(outside == nil, "similar external path never matches by title")

        let withoutCover = try Fixture(base, "owner-without-artwork")
        let differentlyNamedTrack = try withoutCover.game("Set/Actual Data.bin")
        _ = try withoutCover.game("Set/First Disc.cue", "FILE \"Actual Data.bin\" BINARY\n TRACK 01 MODE2/2352\n")
        _ = try withoutCover.game("Set/Collection.m3u", "First Disc.cue\n")
        let noArtCache = CatalogCache(directory: withoutCover.cacheDirectory)
        let noArtSaved = await noArtCache.load(withoutCover.source)
        require(noArtSaved.games.count == 1 && noArtSaved.games[0].coverURL == nil, "ownership fixture has no artwork")
        try FileManager.default.moveItem(at: withoutCover.games, to: withoutCover.directory.appendingPathComponent("Offline"))
        let restoredOwners = CatalogCache(directory: withoutCover.cacheDirectory)
        let noArtOwner = await restoredOwners.cachedGameForLoadedGame(path: differentlyNamedTrack.path, source: withoutCover.source)
        let noArtLookup = await restoredOwners.cachedArtworkForLoadedGame(path: differentlyNamedTrack.path, source: withoutCover.source)
        let ownerStats = await restoredOwners.statistics()
        require(noArtOwner == noArtSaved.games[0] && noArtLookup == nil,
                "coverless game resolves exact differently-named BIN through CUE and playlist offline")
        require(ownerStats.scans == 0 && ownerStats.fingerprintChecks == 0 && ownerStats.diskHits == 1,
                "restored game ownership requires only saved JSON, never descriptor reads or scans")

        let model = await GameCatalog(cache: restoredOwners, coverCache: CoverImageCache(directory: nil), sources: ["ps1": withoutCover.source])
        let modelOwner = await model.cachedGameForLoadedGame(path: differentlyNamedTrack.path, consoleKey: "ps1")
        require(modelOwner == noArtOwner, "model wrapper exposes exact ownership for its configured source")
        await model.setSource(f.source).value
        let staleOwner = await model.cachedGameForLoadedGame(path: differentlyNamedTrack.path, consoleKey: "ps1")
        let invalidConsoleOwner = await model.cachedGameForLoadedGame(path: bin.path, consoleKey: "invalid")
        require(staleOwner == nil && invalidConsoleOwner == nil, "model ownership never adopts another library or console")
    }

    static func corruptionAndMigration(_ base: URL) async throws {
        let f = try Fixture(base, "migration")
        _ = try f.game("Present.iso")
        let cache = CatalogCache(directory: f.cacheDirectory)
        let first = await cache.load(f.source)
        let file = try FileManager.default.contentsOfDirectory(at: f.cacheDirectory, includingPropertiesForKeys: nil).first!
        let original = try Data(contentsOf: file)
        var legacy = try JSONSerialization.jsonObject(with: original) as! [String: Any]
        legacy["version"] = 1
        legacy.removeValue(forKey: "sourceRootPath")
        legacy.removeValue(forKey: "canonicalRootPath")
        try JSONSerialization.data(withJSONObject: legacy).write(to: file)
        let migrated = CatalogCache(directory: f.cacheDirectory)
        let migration = await migrated.load(f.source)
        let migrationStats = await migrated.statistics()
        require(migration.games == first.games && migration.snapshotID == first.snapshotID && migrationStats.diskHits == 1
                && migrationStats.scans == 0 && migrationStats.fingerprintChecks == 0, "v1 snapshot migrates without traversing library")
        try Data("{broken".utf8).write(to: file)
        let recovered = CatalogCache(directory: f.cacheDirectory)
        let repaired = await recovered.load(f.source)
        let recoveredStats = await recovered.statistics()
        require(repaired.games.count == 1 && recoveredStats.scans == 1 && recoveredStats.diskHits == 0, "corrupt snapshot falls back to first full load")
        var wrongSource = try JSONSerialization.jsonObject(with: original) as! [String: Any]
        wrongSource["sourceKey"] = "wrong-source"
        try JSONSerialization.data(withJSONObject: wrongSource).write(to: file)
        let mismatched = CatalogCache(directory: f.cacheDirectory)
        _ = await mismatched.load(f.source)
        let mismatchStats = await mismatched.statistics()
        require(mismatchStats.scans == 1, "snapshot for another source is rejected structurally")
        var unknown = try JSONSerialization.jsonObject(with: original) as! [String: Any]
        unknown["version"] = -100
        try JSONSerialization.data(withJSONObject: unknown).write(to: file)
        let incompatible = CatalogCache(directory: f.cacheDirectory)
        _ = await incompatible.load(f.source)
        let incompatibleStats = await incompatible.statistics()
        require(incompatibleStats.scans == 1, "unknown version requires first full load")
    }

    static func concurrentAndBounds(_ base: URL) async throws {
        let f = try Fixture(base, "concurrent")
        for index in 0..<60 { _ = try f.game("Game \(index).iso") }
        let cache = CatalogCache(directory: f.cacheDirectory)
        let counts = await withTaskGroup(of: Int.self) { group in
            for _ in 0..<20 { group.addTask { await cache.load(f.source).games.count } }
            var values: [Int] = []
            for await count in group { values.append(count) }
            return values
        }
        let stats = await cache.statistics()
        require(counts.count == 20 && counts.allSatisfy { $0 == 60 } && stats.scans == 1 && stats.coalescedRequests > 0,
                "concurrent first loads share one scan")
        async let normal = cache.load(f.source)
        async let forced = cache.load(f.source, force: true)
        let pair = await (normal, forced)
        let forceStats = await cache.statistics()
        require(pair.0.games.count == 60 && pair.1.games.count == 60 && forceStats.scans == stats.scans + 1,
                "forced request cannot reduce to an ordinary saved snapshot hit")
        let sharedDirectory = base.appendingPathComponent("bounded-cache")
        let bounded = CatalogCache(directory: sharedDirectory)
        for index in 0..<10 {
            let item = try Fixture(base, "bound-\(index)")
            _ = try item.game("Game.iso")
            _ = await bounded.load(item.source)
        }
        let files = try FileManager.default.contentsOfDirectory(at: sharedDirectory, includingPropertiesForKeys: [.fileSizeKey])
        let json = files.filter { $0.pathExtension == "json" }
        let bytes = try json.reduce(0) { try $0 + ($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        require(json.count <= 8 && bytes <= 16 * 1024 * 1024, "saved snapshot cache stays bounded")
    }

    static func savedOnlyStartup(_ base: URL) async throws {
        let f = try Fixture(base, "saved-startup")
        _ = try f.game("Saved.iso")
        let cache = CatalogCache(directory: f.cacheDirectory)
        let absent = await cache.loadSaved(f.source)
        let noCacheStats = await cache.statistics()
        require(absent == nil && noCacheStats.scans == 0 && noCacheStats.fingerprintChecks == 0,
                "startup with no saved cache never starts an initial scan, even with online games")
        let saved = await cache.load(f.source)
        try FileManager.default.moveItem(at: f.games, to: f.directory.appendingPathComponent("OfflineGames"))
        let fresh = CatalogCache(directory: f.cacheDirectory)
        let restored = await fresh.loadSaved(f.source)
        let restoredStats = await fresh.statistics()
        require(restored?.games == saved.games && restored?.snapshotID == saved.snapshotID,
                "fresh-instance saved-only restore works after library disconnect")
        require(restoredStats.diskHits == 1 && restoredStats.scans == 0 && restoredStats.fingerprintChecks == 0,
                "offline startup reads only local JSON, no game-folder metadata")
        let memory = await fresh.loadSaved(f.source)
        let memoryStats = await fresh.statistics()
        require(memory?.snapshotID == saved.snapshotID && memoryStats.memoryHits == 1 && memoryStats.fingerprintChecks == 0,
                "saved-only RAM hit performs no metadata validation")
        let noDisk = CatalogCache(directory: f.directory.appendingPathComponent("NoSnapshot"))
        let offlineAbsent = await noDisk.loadSaved(f.source)
        let offlineAbsentStats = await noDisk.statistics()
        require(offlineAbsent == nil && offlineAbsentStats.scans == 0 && offlineAbsentStats.fingerprintChecks == 0,
                "offline startup without cache remains idle")
    }

    @MainActor
    static func startupModel(_ base: URL) async throws {
        let first = try Fixture(base, "startup-model-ps1")
        let second = try Fixture(base, "startup-model-ps2")
        _ = try first.game("PS1 Saved.iso")
        _ = try second.game("PS2 Saved.iso")
        let art = first.covers.appendingPathComponent("PS1 Saved.png")
        try pixel.write(to: art)
        let ps2 = CatalogSource(consoleKey: "ps2", root: second.games, covers: second.covers, database: second.database, frontCovers: second.fronts)
        let sources = ["ps1": first.source, "ps2": ps2]
        let cacheDirectory = base.appendingPathComponent("startup-model-catalog-cache")
        let thumbnails = base.appendingPathComponent("startup-model-thumbnails")
        let onlineCache = CatalogCache(directory: cacheDirectory)
        let firstSaved = await onlineCache.load(first.source)
        let secondSaved = await onlineCache.load(ps2)
        let onlineImages = CoverImageCache(directory: thumbnails)
        let cover = firstSaved.games[0].coverURL!
        _ = await onlineImages.image(at: cover, maxPixelSize: 320, snapshotID: firstSaved.snapshotID)
        _ = await onlineImages.image(at: cover, maxPixelSize: 108, snapshotID: firstSaved.snapshotID)
        try FileManager.default.moveItem(at: first.games, to: first.directory.appendingPathComponent("OfflineGames"))
        try FileManager.default.moveItem(at: second.games, to: second.directory.appendingPathComponent("OfflineGames"))
        try FileManager.default.removeItem(at: art)

        let offlineCache = CatalogCache(directory: cacheDirectory)
        let offlineImages = CoverImageCache(directory: thumbnails)
        let model = GameCatalog(cache: offlineCache, coverCache: offlineImages, sources: sources)
        await model.restoreSavedCatalogs().value
        require(model.games["ps1"] == firstSaved.games && model.games["ps2"] == secondSaved.games,
                "startup publishes both saved console catalogs without SSD")
        require(model.snapshotIDs["ps1"] == firstSaved.snapshotID && model.snapshotIDs["ps2"] == secondSaved.snapshotID
                && model.revisions["ps1"] == 1 && model.revisions["ps2"] == 1 && model.loading.isEmpty,
                "startup publishes matching snapshot IDs/revisions and leaves refresh available")
        let restoredStats = await offlineCache.statistics()
        let artworkStats = await offlineImages.statistics()
        require(restoredStats.scans == 0 && restoredStats.fingerprintChecks == 0 && restoredStats.diskHits == 2,
                "model startup restores two JSON files without scans")
        require(artworkStats.diskHits == 0 && artworkStats.sourceDecodes == 0 && artworkStats.failures == 0,
                "model startup restores metadata only, without eagerly decoding artwork")
        let demandedArt = await offlineImages.image(at: cover, maxPixelSize: 108, snapshotID: firstSaved.snapshotID)
        require(demandedArt != nil, "saved artwork stays available on demand while offline")
        await model.restoreSavedCatalogs().value
        require(model.revisions["ps1"] == 1 && model.revisions["ps2"] == 1, "startup restore is idempotent")

        let emptyBackend = CatalogCache(directory: base.appendingPathComponent("model-startup-empty"))
        let emptyModel = GameCatalog(cache: emptyBackend, coverCache: CoverImageCache(directory: nil), sources: sources)
        await emptyModel.restoreSavedCatalogs().value
        let emptyStats = await emptyBackend.statistics()
        require(emptyModel.games.values.allSatisfy(\.isEmpty) && emptyModel.errors.isEmpty && emptyStats.scans == 0
                && emptyStats.fingerprintChecks == 0, "model with no saved snapshot performs no initial scan")

        let race = try Fixture(base, "startup-race")
        let oldFile = try race.game("Old.iso")
        let raceBackend = CatalogCache(directory: race.cacheDirectory)
        _ = await raceBackend.load(race.source)
        try FileManager.default.removeItem(at: oldFile)
        _ = try race.game("New.iso")
        let raceModel = GameCatalog(cache: raceBackend, coverCache: CoverImageCache(directory: nil), sources: ["ps1": race.source])
        let staleRestore = raceModel.restoreSavedCatalogs()
        raceModel.refresh("ps1", force: true)
        await staleRestore.value
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !raceModel.loading.isEmpty && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        require(raceModel.loading.isEmpty && raceModel.games["ps1"]?.map(\.title) == ["New"] && raceModel.revisions["ps1"] == 1,
                "explicit refresh supersedes stale startup restore without overwriting its generation")
        let invalidated = GameCatalog(cache: raceBackend, coverCache: CoverImageCache(directory: nil), sources: ["ps1": race.source])
        let pending = invalidated.restoreSavedCatalogs()
        invalidated.invalidate("ps1")
        await pending.value
        require(invalidated.games["ps1"]?.isEmpty == true && invalidated.snapshotIDs["ps1"] == nil && invalidated.revisions["ps1"] == 1,
                "explicit invalidation prevents a pending saved restore from repopulating the model")
        print("PASS: saved-only app startup restores PS1/PS2 offline without eager artwork work, serves cached artwork on demand, skips scans on cache miss, and respects refresh/invalidation generations.")
    }

    @MainActor
    static func sourceChanges(_ base: URL) async throws {
        let first = try Fixture(base, "source-a")
        let second = try Fixture(base, "source-b")
        let empty = try Fixture(base, "source-empty")
        let consoleTwo = try Fixture(base, "source-ps2")
        _ = try first.game("Library A.iso")
        _ = try second.game("Library B.iso")
        _ = try consoleTwo.game("PS2 Unchanged.iso")
        // Deliberately keep every metadata folder equal: root alone must isolate
        // the two libraries' snapshots and ownership maps.
        let sourceA = first.source
        let sourceB = CatalogSource(consoleKey: "ps1", root: second.games, covers: first.covers,
                                    database: first.database, frontCovers: first.fronts)
        let emptySource = CatalogSource(consoleKey: "ps1", root: empty.games, covers: first.covers,
                                        database: first.database, frontCovers: first.fronts)
        let ps2 = CatalogSource(consoleKey: "ps2", root: consoleTwo.games, covers: consoleTwo.covers,
                                database: consoleTwo.database, frontCovers: consoleTwo.fronts)
        let custom = CatalogSource.installed("ps1", root: second.games)
        require(custom?.root == second.games && custom?.covers == CatalogSource.installed("ps1")?.covers,
                "installed source accepts a custom root without changing emulator metadata paths")
        require(CatalogSource.installed("ps2")?.root.path == "/Volumes/Extreme SSD/Emulacao/PS2/Jogos"
                && CatalogSource.installed("invalid", root: second.games) == nil,
                "default SSD paths remain unchanged and invalid consoles are rejected")

        let directory = base.appendingPathComponent("source-switch-cache")
        let seed = CatalogCache(directory: directory)
        let savedA = await seed.load(sourceA)
        let savedB = await seed.load(sourceB)
        let savedPS2 = await seed.load(ps2)
        let backend = CatalogCache(directory: directory)
        let model = GameCatalog(cache: backend, coverCache: CoverImageCache(directory: nil),
                                sources: ["ps1": sourceA, "ps2": ps2])
        await model.restoreSavedCatalogs().value
        require(model.games["ps1"] == savedA.games, "initial custom library restores its own snapshot")
        await model.setSource(sourceB).value
        require(model.source(for: "ps1")?.root == second.games && model.games["ps1"] == savedB.games
                && model.snapshotIDs["ps1"] == savedB.snapshotID, "switching root restores only the new library")
        require(model.games["ps2"] == savedPS2.games && model.revisions["ps2"] == 1,
                "switching PS1 leaves PS2 games and revisions untouched")
        let revision = model.revisions["ps1"]
        await model.setSource(sourceB).value
        require(model.revisions["ps1"] == revision, "selecting the unchanged source does not invalidate its cache")
        await model.setSource(emptySource).value
        require(model.games["ps1"]?.isEmpty == true && model.snapshotIDs["ps1"] == nil && model.errors["ps1"] == nil,
                "new library without a snapshot cannot retain the previous library's list")
        let noScan = await backend.statistics()
        require(noScan.scans == 0 && noScan.fingerprintChecks == 0, "source changes perform saved-only restoration")
        model.refresh("ps1", force: true)
        try await waitForRefresh(model)
        require(model.games["ps1"]?.isEmpty == true && model.snapshotIDs["ps1"] != nil,
                "explicit full load of an empty folder saves an empty list, not games from the previous root")

        // Both source-specific JSON snapshots must survive switching and work
        // after their game folders disappear, including a new cache actor.
        try FileManager.default.moveItem(at: first.games, to: first.directory.appendingPathComponent("OfflineGames"))
        try FileManager.default.moveItem(at: second.games, to: second.directory.appendingPathComponent("OfflineGames"))
        let offlineBackend = CatalogCache(directory: directory)
        let offlineModel = GameCatalog(cache: offlineBackend, coverCache: CoverImageCache(directory: nil),
                                       sources: ["ps1": emptySource])
        await offlineModel.setSource(sourceA).value
        require(offlineModel.games["ps1"] == savedA.games, "offline A is restored after another library was selected")
        await offlineModel.setSource(sourceB).value
        require(offlineModel.games["ps1"] == savedB.games, "offline B has a separate saved catalog")
        let offlineStats = await offlineBackend.statistics()
        require(offlineStats.scans == 0 && offlineStats.fingerprintChecks == 0 && offlineStats.diskHits == 2,
                "offline source switching never probes game folders")

        let raceModel = GameCatalog(cache: CatalogCache(directory: directory), coverCache: CoverImageCache(directory: nil),
                                    sources: ["ps1": sourceA])
        let oldRestore = raceModel.restoreSavedCatalogs()
        let newRestore = raceModel.setSource(sourceB)
        await oldRestore.value
        await newRestore.value
        require(raceModel.games["ps1"] == savedB.games && raceModel.source(for: "ps1")?.root == second.games,
                "late restoration for A cannot repopulate B")

        // Force refresh supersedes an already scheduled saved-only restoration
        // of the same source after a folder change.
        try FileManager.default.moveItem(at: second.directory.appendingPathComponent("OfflineGames"), to: second.games)
        _ = try second.game("New in B.iso")
        await raceModel.setSource(sourceA, restoreSaved: false).value
        let oldB = raceModel.setSource(sourceB)
        raceModel.refresh("ps1", force: true)
        await oldB.value
        try await waitForRefresh(raceModel)
        require(raceModel.games["ps1"]?.map(\.title) == ["Library B", "New in B"],
                "forced refresh after source switch supersedes the new source's older saved restore")

        // Schedule a forced scan of the old root, then immediately switch away.
        // Loading the same source joins its flight; a few yields deliver any
        // stale publish to the main actor before checking the displayed list.
        let pendingBackend = CatalogCache(directory: directory)
        let pendingModel = GameCatalog(cache: pendingBackend, coverCache: CoverImageCache(directory: nil),
                                       sources: ["ps1": sourceB])
        pendingModel.refresh("ps1", force: true)
        let switched = pendingModel.setSource(sourceA)
        await switched.value
        _ = await pendingBackend.load(sourceB, force: true)
        for _ in 0..<10 { await Task.yield() }
        require(pendingModel.games["ps1"] == savedA.games && pendingModel.source(for: "ps1")?.root == first.games,
                "late scan of the previous library cannot replace the current offline catalog")
        print("PASS: configurable roots preserve independent A/B offline snapshots, clear stale games, isolate consoles, and reject late restores/scans after source changes.")
    }

    @MainActor
    static func backgroundRefreshPolicy(_ base: URL) async throws {
        let first = try Fixture(base, "background-a")
        let second = try Fixture(base, "background-b")
        _ = try first.game("Saved.iso")
        _ = try second.game("Other Root.iso")
        let backend = CatalogCache(directory: base.appendingPathComponent("background-cache"))
        let saved = await backend.load(first.source)
        _ = try first.game("Discovered.iso")
        var clock: TimeInterval = 100
        let model = GameCatalog(cache: backend, coverCache: CoverImageCache(directory: nil),
                                sources: ["ps1": first.source], artworkPrefetchBatchSize: 0, now: { clock })
        var publishedSavedWhileScanning = false
        let observer = model.$revisions.sink { _ in
            if model.loading.contains("ps1"), model.games["ps1"] == saved.games {
                publishedSavedWhileScanning = true
            }
        }
        model.refreshInBackground("ps1")
        for _ in 0..<20 {
            model.refreshInBackground("ps1")
            model.refresh("ps1", force: true)
        }
        try await waitForRefresh(model)
        require(publishedSavedWhileScanning && model.games["ps1"]?.map(\.title) == ["Discovered", "Saved"],
                "entry publishes saved metadata before background discovery completes")
        withExtendedLifetime(observer) {}
        let firstStats = await backend.statistics()
        require(firstStats.scans == 2, "overlapping automatic and explicit requests share the existing full scan")

        _ = try first.game("Later.iso")
        clock = 129
        for _ in 0..<20 { model.refreshInBackground("ps1") }
        require(!model.loading.contains("ps1"), "rapid menu entry within 30 seconds starts no new task")
        let throttled = await backend.statistics()
        require(throttled.scans == firstStats.scans && throttled.fingerprintChecks == firstStats.fingerprintChecks,
                "throttled automatic refresh does not enumerate or fingerprint the source")
        clock = 130
        model.refreshInBackground("ps1")
        try await waitForRefresh(model)
        require(model.games["ps1"]?.map(\.title) == ["Discovered", "Later", "Saved"],
                "the next entry after the interval automatically discovers copied games")
        _ = try first.game("Explicit.iso")
        model.refresh("ps1", force: true)
        try await waitForRefresh(model)
        require(model.games["ps1"]?.count == 4, "explicit reload bypasses automatic discovery interval")

        await model.setSource(second.source).value
        model.refreshInBackground("ps1")
        try await waitForRefresh(model)
        require(model.games["ps1"]?.map(\.title) == ["Other Root"], "new source has an independent throttle")
        await model.setSource(first.source).value
        model.refreshInBackground("ps1")
        require(!model.loading.contains("ps1") && model.games["ps1"]?.count == 4,
                "returning to a recently scanned source restores its snapshot without scanning again")

        try FileManager.default.moveItem(at: first.games, to: first.directory.appendingPathComponent("Disconnected"))
        clock = 160
        model.refreshInBackground("ps1")
        try await waitForRefresh(model)
        let failed = await backend.statistics()
        require(model.games["ps1"]?.count == 4 && model.errors["ps1"] != nil,
                "a background failure retains the last usable catalog")
        model.refreshInBackground("ps1")
        let noRetry = await backend.statistics()
        require(!model.loading.contains("ps1") && noRetry.fingerprintChecks == failed.fingerprintChecks,
                "failed background attempts are throttled rather than hammering an absent disk")
        model.refresh("ps1", force: true)
        try await waitForRefresh(model)
        let explicitRetry = await backend.statistics()
        require(explicitRetry.fingerprintChecks > failed.fingerprintChecks, "manual retry bypasses the failure throttle")

        try FileManager.default.moveItem(at: first.directory.appendingPathComponent("Disconnected"), to: first.games)
        _ = try first.game("Forced After Cache Hit.iso")
        model.refresh("ps1")
        model.refresh("ps1", force: true)
        try await waitForRefresh(model)
        require(model.games["ps1"]?.count == 5, "a forced request behind a pending saved-only load is not lost")
        print("PASS: cached-first background discovery, 30s per-root throttling, manual bypass, coalescing, source isolation, and safe failure retries.")
    }

    @MainActor
    static func boundedArtworkPrefetch(_ base: URL) async throws {
        let fixture = try Fixture(base, "bounded-prefetch")
        for title in ["A", "B", "C", "D"] {
            _ = try fixture.game("\(title).iso")
            try pixel.write(to: fixture.covers.appendingPathComponent("\(title).png"))
        }
        let backend = CatalogCache(directory: fixture.cacheDirectory)
        let images = CoverImageCache(directory: fixture.directory.appendingPathComponent("thumbnails"))
        let model = GameCatalog(cache: backend, coverCache: images, sources: ["ps1": fixture.source], artworkPrefetchBatchSize: 2)
        model.setArtworkPrefetchSuspended(true)
        model.refreshInBackground("ps1")
        try await waitForRefresh(model)
        try await Task.sleep(for: .milliseconds(350))
        let paused = await images.statistics()
        require(paused.sourceDecodes == 0, "optional artwork warming stays suspended while a game is running")
        let remaining = model.games["ps1"]!.last!
        let demanded = await images.image(at: remaining.coverURL!, maxPixelSize: 320, snapshotID: model.snapshotIDs["ps1"])
        let afterDemand = await images.statistics()
        require(demanded != nil && afterDemand.sourceDecodes == 1, "visible cover requests still work during prefetch suspension")
        model.setArtworkPrefetchSuspended(false)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        var warmed = await images.statistics()
        while warmed.sourceDecodes < 4 && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
            warmed = await images.statistics()
        }
        require(warmed.sourceDecodes == 4 && warmed.diskEntries == 4 && warmed.failures == 0,
                "progressive background prefetch saves all covers at one canonical size")
        // Allow the final already-cached cover request to complete before taking
        // baseline counters for an unchanged snapshot refresh.
        try await Task.sleep(for: .milliseconds(100))
        let beforeRepeat = await images.statistics()
        model.refresh("ps1", force: true)
        try await waitForRefresh(model)
        try await Task.sleep(for: .milliseconds(350))
        let repeated = await images.statistics()
        require(repeated.sourceDecodes == 4 && repeated.memoryHits == beforeRepeat.memoryHits && repeated.diskHits == beforeRepeat.diskHits,
                "unchanged full reload does not warm every thumbnail again")
        print("PASS: progressive single-size artwork prefetch with suspension, demand-loaded visible covers, and no repeated warming for unchanged snapshots.")
    }

    @MainActor
    static func waitForRefresh(_ model: GameCatalog) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !model.loading.isEmpty && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        require(model.loading.isEmpty, "catalog refresh finishes within the test deadline")
    }
}
