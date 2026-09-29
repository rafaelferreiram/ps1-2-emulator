import Foundation
import CoreGraphics
import ImageIO

@main
struct CoverImageCacheTests {
    static func main() async throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            guard value() else { fatalError("FAIL: \(message)") }
            checks += 1
        }
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("ps12-cover-fixtures-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        // The only removed fixture directory is created by this test with a UUID.
        defer { try? manager.removeItem(at: root) }
        let original = root.appendingPathComponent("cover.png")
        try writeImage(original, width: 600, height: 900, red: 1)
        let originalData = try Data(contentsOf: original)
        let disk = root.appendingPathComponent("thumbnails", isDirectory: true)
        let cache = CoverImageCache(directory: disk)
        let first = await cache.image(at: original, maxPixelSize: 180)
        check(first?.width == 120 && first?.height == 180, "Thumbnail preserves aspect ratio and limits pixels")
        var stats = await cache.statistics()
        check(stats.sourceDecodes == 1 && stats.memoryEntries == 1 && stats.diskEntries == 1, "First lookup decodes and fills both caches")
        let second = await cache.image(at: original, maxPixelSize: 180)
        stats = await cache.statistics()
        check(second != nil && stats.memoryHits == 1 && stats.sourceDecodes == 1, "Second lookup hits decoded memory")
        let unchangedData = try Data(contentsOf: original)
        check(unchangedData == originalData, "Cache never changes original image")

        let restarted = CoverImageCache(directory: disk)
        let persisted = await restarted.image(at: original, maxPixelSize: 180)
        stats = await restarted.statistics()
        check(persisted?.height == 180 && stats.diskHits == 1 && stats.sourceDecodes == 0, "New cache instance reuses persistent PNG")

        let larger = await cache.image(at: original, maxPixelSize: 270)
        stats = await cache.statistics()
        check(larger?.height == 270 && stats.sourceDecodes == 2, "Requested resolution participates in key")
        let canonical = root.appendingPathComponent("cover-link.png")
        try manager.createSymbolicLink(at: canonical, withDestinationURL: original)
        _ = await cache.image(at: canonical, maxPixelSize: 180)
        stats = await cache.statistics()
        check(stats.memoryHits == 2 && stats.sourceDecodes == 2, "Symlink and original share canonical identity")

        let beforeReplacement = try manager.attributesOfItem(atPath: original.path)
        try originalData.write(to: original, options: .atomic)
        try manager.setAttributes([.modificationDate: beforeReplacement[.modificationDate]!], ofItemAtPath: original.path)
        _ = await cache.image(at: original, maxPixelSize: 180)
        stats = await cache.statistics()
        check(stats.sourceDecodes == 3, "New inode invalidates even when path, size, content and mtime are unchanged")

        try writeImage(original, width: 800, height: 400, red: 0.2)
        let changed = await cache.image(at: original, maxPixelSize: 180)
        stats = await cache.statistics()
        check(changed?.width == 180 && changed?.height == 90 && stats.sourceDecodes == 4, "Same-path replacement invalidates thumbnail")
        try manager.removeItem(at: original)
        let missing = await cache.image(at: original, maxPixelSize: 180)
        check(missing == nil, "Removed source does not return old memory or disk image")
        try Data("not a real image".utf8).write(to: original)
        let corrupt = await cache.image(at: original, maxPixelSize: 180)
        check(corrupt == nil, "Corrupt replacement cannot return a previous valid thumbnail")
        let unavailable = await cache.image(at: URL(string: "https://example.invalid/cover.png")!, maxPixelSize: 180)
        check(unavailable == nil, "Non-file URLs are rejected")

        try writeImage(original, width: 900, height: 600, red: 0.6)
        let repairDisk = root.appendingPathComponent("repair", isDirectory: true)
        let seed = CoverImageCache(directory: repairDisk)
        _ = await seed.image(at: original, maxPixelSize: 160)
        let cacheFile = try manager.contentsOfDirectory(at: repairDisk, includingPropertiesForKeys: nil).first!
        try Data("broken cache PNG".utf8).write(to: cacheFile)
        let recovering = CoverImageCache(directory: repairDisk)
        let repaired = await recovering.image(at: original, maxPixelSize: 160)
        stats = await recovering.statistics()
        check(repaired?.width == 160 && stats.sourceDecodes == 1 && stats.diskHits == 0, "Corrupt persisted thumbnail is recreated")
        let repairedNextRun = CoverImageCache(directory: repairDisk)
        _ = await repairedNextRun.image(at: original, maxPixelSize: 160)
        stats = await repairedNextRun.statistics()
        check(stats.diskHits == 1 && stats.sourceDecodes == 0, "Recovered PNG persists successfully")

        let coalesced = CoverImageCache(directory: nil)
        let concurrent = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for _ in 0..<30 {
                group.addTask { await coalesced.image(at: original, maxPixelSize: 320) != nil }
            }
            var results: [Bool] = []
            for await result in group { results.append(result) }
            return results
        }
        stats = await coalesced.statistics()
        check(concurrent.count == 30 && concurrent.allSatisfy { $0 }, "Concurrent callers all receive their thumbnail")
        check(stats.sourceDecodes == 1 && stats.memoryHits + stats.coalescedRequests == 29, "Concurrent requests do not duplicate source decoding")

        let oriented = root.appendingPathComponent("rotated.jpg")
        try writeImage(oriented, width: 200, height: 100, red: 0.3, orientation: 6)
        let upright = await cache.image(at: oriented, maxPixelSize: 80)
        check(upright?.width == 40 && upright?.height == 80, "EXIF orientation is applied before caching")
        let uprightNextRun = CoverImageCache(directory: disk)
        let uprightPersisted = await uprightNextRun.image(at: oriented, maxPixelSize: 80)
        stats = await uprightNextRun.statistics()
        check(uprightPersisted?.width == 40 && uprightPersisted?.height == 80 && stats.diskHits == 1,
              "Persisted PNG preserves upright orientation without applying it twice")
        let bounded = await cache.image(at: original, maxPixelSize: 100_000)
        check((bounded?.width ?? Int.max) <= 1024 && (bounded?.height ?? Int.max) <= 1024, "Untrusted large request is capped at 1024 pixels")

        let tiny = CoverImageCache(directory: nil, memoryByteLimit: 32_000)
        _ = await tiny.image(at: original, maxPixelSize: 100)
        _ = await tiny.image(at: oriented, maxPixelSize: 100)
        stats = await tiny.statistics()
        check(stats.memoryBytes <= 32_000 && stats.memoryEntries <= 1, "Decoded RAM budget evicts oldest thumbnails")
        _ = await tiny.image(at: original, maxPixelSize: 100)
        stats = await tiny.statistics()
        check(stats.sourceDecodes == 3, "Evicted RAM thumbnail is decoded again without a disk cache")
        let tooSmall = CoverImageCache(directory: nil, memoryByteLimit: 1)
        let oversized = await tooSmall.image(at: original, maxPixelSize: 100)
        check(oversized != nil, "Oversized entry is returned without retention")
        stats = await tooSmall.statistics()
        check(stats.memoryBytes == 0 && stats.memoryEntries == 0, "Single entry cannot exceed RAM budget")

        let limitedDisk = root.appendingPathComponent("limited", isDirectory: true)
        try manager.createDirectory(at: limitedDisk, withIntermediateDirectories: true)
        let unrelated = limitedDisk.appendingPathComponent("personal-note.txt")
        try Data("preserve".utf8).write(to: unrelated)
        let fakeName = limitedDisk.appendingPathComponent("thumb-v1-not-a-key.png")
        try Data("preserve".utf8).write(to: fakeName)
        let limited = CoverImageCache(directory: limitedDisk, memoryByteLimit: 0, diskByteLimit: 1_000_000, maxDiskEntries: 1)
        _ = await limited.image(at: original, maxPixelSize: 80)
        _ = await limited.image(at: oriented, maxPixelSize: 80)
        stats = await limited.statistics()
        check(stats.diskEntries == 1 && stats.diskBytes <= 1_000_000, "Persistent cache obeys entry and byte limits")
        check(manager.fileExists(atPath: unrelated.path) && manager.fileExists(atPath: fakeName.path), "Maintenance preserves files not owned by cache")
        _ = await limited.image(at: original, maxPixelSize: 80)
        stats = await limited.statistics()
        check(stats.sourceDecodes == 3, "Oldest persistent thumbnail was evicted")
        let existingBudget = stats.diskBytes
        let byteLimited = CoverImageCache(directory: limitedDisk, memoryByteLimit: 0, diskByteLimit: max(1, existingBudget - 1))
        _ = await byteLimited.image(at: original, maxPixelSize: 80)
        stats = await byteLimited.statistics()
        check(stats.diskBytes <= max(1, existingBudget - 1), "Existing persisted files trimmed to smaller byte budget")

        let unusableDirectory = root.appendingPathComponent("not-a-directory")
        try Data("file".utf8).write(to: unusableDirectory)
        let diskUnavailable = CoverImageCache(directory: unusableDirectory)
        let fallback = await diskUnavailable.image(at: original, maxPixelSize: 80)
        check(fallback != nil, "Unavailable disk storage falls back to source and RAM")
        stats = await diskUnavailable.statistics()
        check(stats.memoryEntries == 1 && stats.diskEntries == 0, "Unavailable disk does not prevent memory caching")

        let lruDisk = root.appendingPathComponent("lru", isDirectory: true)
        let lru = CoverImageCache(directory: lruDisk, memoryByteLimit: 0, maxDiskEntries: 2)
        _ = await lru.image(at: original, maxPixelSize: 80)
        _ = await lru.image(at: original, maxPixelSize: 100)
        _ = await lru.image(at: original, maxPixelSize: 80)
        _ = await lru.image(at: original, maxPixelSize: 120)
        stats = await lru.statistics()
        check(stats.diskHits == 1 && stats.sourceDecodes == 3 && stats.diskEntries == 2, "Reading an existing disk thumbnail updates LRU ordering")
        _ = await lru.image(at: original, maxPixelSize: 80)
        stats = await lru.statistics()
        check(stats.diskHits == 2 && stats.sourceDecodes == 3, "Recently used disk entry survives eviction")
        _ = await lru.image(at: original, maxPixelSize: 100)
        stats = await lru.statistics()
        check(stats.sourceDecodes == 4, "Least recently used disk entry is the one evicted")

        let vanished = root.appendingPathComponent("removed-cover.png")
        try writeImage(vanished, width: 300, height: 600, red: 0.4)
        let vanishedDisk = root.appendingPathComponent("removed-disk")
        let vanishedSeed = CoverImageCache(directory: vanishedDisk)
        _ = await vanishedSeed.image(at: vanished, maxPixelSize: 80)
        try manager.removeItem(at: vanished)
        let afterRemoval = CoverImageCache(directory: vanishedDisk)
        let noSource = await afterRemoval.image(at: vanished, maxPixelSize: 80)
        stats = await afterRemoval.statistics()
        check(noSource == nil && stats.diskHits == 0, "New process cannot serve persisted image after source deletion")

        let snapshotSource = root.appendingPathComponent("snapshot-cover.png")
        try writeImage(snapshotSource, width: 400, height: 600, red: 0.2)
        let snapshotDisk = root.appendingPathComponent("snapshots")
        let snapshotCache = CoverImageCache(directory: snapshotDisk)
        let snapshotFirst = await snapshotCache.image(at: snapshotSource, maxPixelSize: 150, snapshotID: "catalog-full-load-1")
        stats = await snapshotCache.statistics()
        check(snapshotFirst?.width == 100 && snapshotFirst?.height == 150 && stats.sourceDecodes == 1,
              "Snapshot cache miss decodes source once and stores original aspect ratio")
        check(stats.memoryEntries == 1 && stats.diskEntries == 1, "Snapshot miss populates both bounded caches")

        try writeImage(snapshotSource, width: 500, height: 250, red: 0.8)
        let snapshotUnchanged = await snapshotCache.image(at: snapshotSource, maxPixelSize: 150, snapshotID: "catalog-full-load-1")
        stats = await snapshotCache.statistics()
        check(snapshotUnchanged?.width == 100 && snapshotUnchanged?.height == 150 && stats.memoryHits == 1 && stats.sourceDecodes == 1,
              "Warm snapshot RAM preserves last-load cover despite source replacement")
        let snapshotRestarted = CoverImageCache(directory: snapshotDisk)
        let snapshotPersisted = await snapshotRestarted.image(at: snapshotSource, maxPixelSize: 150, snapshotID: "catalog-full-load-1")
        stats = await snapshotRestarted.statistics()
        check(snapshotPersisted?.width == 100 && snapshotPersisted?.height == 150 && stats.diskHits == 1 && stats.sourceDecodes == 0,
              "Reopened snapshot disk preserves last-load cover despite source replacement")

        try manager.removeItem(at: snapshotSource)
        let snapshotOffline = await snapshotCache.image(at: snapshotSource, maxPixelSize: 150, snapshotID: "catalog-full-load-1")
        stats = await snapshotCache.statistics()
        check(snapshotOffline?.width == 100 && stats.memoryHits == 2 && stats.sourceDecodes == 1,
              "Warm snapshot RAM serves artwork even when source is missing or volume offline")
        let snapshotOfflineRestarted = CoverImageCache(directory: snapshotDisk)
        let snapshotOfflinePersisted = await snapshotOfflineRestarted.image(at: snapshotSource, maxPixelSize: 150, snapshotID: "catalog-full-load-1")
        stats = await snapshotOfflineRestarted.statistics()
        check(snapshotOfflinePersisted?.height == 150 && stats.diskHits == 1 && stats.sourceDecodes == 0,
              "Reopened local snapshot disk serves artwork without its original source")
        let missingNewSnapshot = await snapshotCache.image(at: snapshotSource, maxPixelSize: 150, snapshotID: "catalog-full-load-2")
        check(missingNewSnapshot == nil, "New snapshot does not inherit old artwork when its original source is absent")

        try writeImage(snapshotSource, width: 500, height: 250, red: 0.8)
        let refreshedSnapshot = await snapshotCache.image(at: snapshotSource, maxPixelSize: 150, snapshotID: "catalog-full-load-2")
        stats = await snapshotCache.statistics()
        check(refreshedSnapshot?.width == 150 && refreshedSnapshot?.height == 75 && stats.sourceDecodes == 2,
              "Changed snapshot ID loads changed artwork at the same source path")
        _ = await snapshotCache.image(at: snapshotSource, maxPixelSize: 150, snapshotID: "catalog-full-load-2")
        stats = await snapshotCache.statistics()
        check(stats.sourceDecodes == 2 && stats.memoryHits == 3, "New snapshot fallback decodes only once")
        let refreshedResolution = await snapshotCache.image(at: snapshotSource, maxPixelSize: 200, snapshotID: "catalog-full-load-2")
        check(refreshedResolution?.width == 200 && refreshedResolution?.height == 100,
              "Snapshot key includes requested resolution")
        let separateSource = await snapshotCache.image(at: oriented, maxPixelSize: 150, snapshotID: "catalog-full-load-2")
        check(separateSource?.height == 150 && separateSource?.width == 75,
              "Snapshot key separates different artwork paths")
        let rejectedSnapshotURL = await snapshotCache.image(at: URL(string: "https://example.invalid/cover.png")!,
                                                           maxPixelSize: 150, snapshotID: "catalog-full-load-1")
        check(rejectedSnapshotURL == nil, "Snapshot lookups still reject non-file URLs")

        let snapshotConcurrentCache = CoverImageCache(directory: nil)
        let concurrentSnapshots = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for _ in 0..<30 {
                group.addTask {
                    await snapshotConcurrentCache.image(at: snapshotSource, maxPixelSize: 320, snapshotID: "concurrent-load") != nil
                }
            }
            var results: [Bool] = []
            for await result in group { results.append(result) }
            return results
        }
        stats = await snapshotConcurrentCache.statistics()
        check(concurrentSnapshots.count == 30 && concurrentSnapshots.allSatisfy { $0 } && stats.sourceDecodes == 1 &&
              stats.memoryHits + stats.coalescedRequests == 29, "Snapshot requests retain concurrent miss coalescing")

        let snapshotRepairDisk = root.appendingPathComponent("snapshot-repair")
        let snapshotRepairSeed = CoverImageCache(directory: snapshotRepairDisk)
        _ = await snapshotRepairSeed.image(at: snapshotSource, maxPixelSize: 160, snapshotID: "repair-load")
        let snapshotCacheFile = try manager.contentsOfDirectory(at: snapshotRepairDisk, includingPropertiesForKeys: nil).first!
        try Data("broken snapshot cache PNG".utf8).write(to: snapshotCacheFile)
        let snapshotRecovering = CoverImageCache(directory: snapshotRepairDisk)
        let snapshotRepaired = await snapshotRecovering.image(at: snapshotSource, maxPixelSize: 160, snapshotID: "repair-load")
        stats = await snapshotRecovering.statistics()
        check(snapshotRepaired?.width == 160 && stats.sourceDecodes == 1 && stats.diskHits == 0,
              "Corrupt snapshot disk thumbnail falls back to a fresh source decode")
        try manager.removeItem(at: snapshotSource)
        let snapshotRepairedRestart = CoverImageCache(directory: snapshotRepairDisk)
        let snapshotRecoveredOffline = await snapshotRepairedRestart.image(at: snapshotSource, maxPixelSize: 160, snapshotID: "repair-load")
        stats = await snapshotRepairedRestart.statistics()
        check(snapshotRecoveredOffline?.width == 160 && stats.diskHits == 1 && stats.sourceDecodes == 0,
              "Repaired snapshot persists and can subsequently reopen offline")
        print("PASS: \(checks) cover-cache checks (live/snapshot modes, memory, disk, coalescing, budgets and orientation)")
    }

    private static func writeImage(_ url: URL, width: Int, height: Int, red: CGFloat, orientation: Int? = nil) throws {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: red, green: 0.3, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let type = orientation == nil ? "public.png" : "public.jpeg"
        let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil)!
        let options = orientation.map { [kCGImagePropertyOrientation: $0] as CFDictionary }
        CGImageDestinationAddImage(destination, context.makeImage()!, options)
        guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "CoverCacheFixture", code: 1) }
        try (data as Data).write(to: url, options: .atomic)
    }
}
