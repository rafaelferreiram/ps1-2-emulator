import Foundation
import CoreGraphics
import ImageIO
import CryptoKit
import Darwin

/// Shared, off-main-actor thumbnails. Originals are never rewritten. Only the
/// versioned files owned by this cache may be removed during disk maintenance.
actor CoverImageCache {
    static let shared = CoverImageCache()
    static let defaultDirectory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        .first?.appendingPathComponent("local.rafael.centraldejogos/Thumbnails", isDirectory: true)

    struct Statistics: Sendable {
        var memoryHits = 0
        var diskHits = 0
        var sourceDecodes = 0
        var coalescedRequests = 0
        var failures = 0
        var memoryBytes = 0
        var memoryEntries = 0
        var diskBytes = 0
        var diskEntries = 0
    }

    private struct Fingerprint: Equatable, Sendable {
        let path: String
        let identity: String

        static func read(_ url: URL) -> Fingerprint? {
            guard url.isFileURL else { return nil }
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            var metadata = stat()
            guard path.withCString({ Darwin.lstat($0, &metadata) }) == 0,
                  metadata.st_mode & S_IFMT == S_IFREG, metadata.st_size > 0 else { return nil }
            return Fingerprint(path: path, identity: [
                String(metadata.st_dev), String(metadata.st_ino), String(metadata.st_size),
                String(metadata.st_mtimespec.tv_sec), String(metadata.st_mtimespec.tv_nsec),
                String(metadata.st_ctimespec.tv_sec), String(metadata.st_ctimespec.tv_nsec)
            ].joined(separator: ":"))
        }

        func key(size: Int) -> String {
            let payload = "thumbnail-v1\u{0}\(path)\u{0}\(identity)\u{0}\(size)"
            return SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
        }

        static func snapshotKey(url: URL, snapshotID: String, size: Int) -> String {
            // Lexical normalization only: consulting symlinks or metadata here
            // would wake the original volume even when the local cache is warm.
            var parts: [Substring] = []
            for part in url.path.split(separator: "/") {
                if part == "." { continue }
                if part == ".." { if !parts.isEmpty { parts.removeLast() }; continue }
                parts.append(part)
            }
            let path = (url.path.hasPrefix("/") ? "/" : "") + parts.joined(separator: "/")
            let payload = "thumbnail-snapshot-v1\u{0}\(path)\u{0}\(snapshotID)\u{0}\(size)"
            return SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
        }
    }

    private struct MemoryEntry {
        let image: CGImage
        let bytes: Int
        var lastUse: UInt64
    }

    private struct DiskEntry {
        let bytes: Int
        var lastUse: Date
    }

    private struct Decoded: @unchecked Sendable {
        let image: CGImage?
        let png: Data?
        let diskHit: Bool
        let sourceDecode: Bool
        let invalidDiskFile: Bool
        var lowerResolutionFallback = false
    }

    private let directory: URL?
    private let memoryByteLimit: Int
    private let diskByteLimit: Int
    private let maxDiskEntries: Int
    private var memory: [String: MemoryEntry] = [:]
    private var memoryBytes = 0
    private var clock: UInt64 = 0
    private var disk: [String: DiskEntry] = [:]
    private var diskBytes = 0
    private var didPrepareDisk = false
    private var diskEnabled = false
    private var inFlight: [String: Task<Decoded, Never>] = [:]
    private var counters = Statistics()

    init(directory: URL? = CoverImageCache.defaultDirectory,
         memoryByteLimit: Int = 32 * 1024 * 1024,
         diskByteLimit: Int = 64 * 1024 * 1024,
         maxDiskEntries: Int = 256) {
        self.directory = directory?.standardizedFileURL
        self.memoryByteLimit = max(0, memoryByteLimit)
        self.diskByteLimit = max(0, diskByteLimit)
        self.maxDiskEntries = max(0, min(256, maxDiskEntries))
    }

    /// A snapshot keeps the last fully loaded catalog's artwork until its ID
    /// changes. Its RAM/disk hits never consult the original cover or SSD.
    /// Without a snapshot, every hit still validates the current source identity.
    func image(at url: URL, maxPixelSize: Int, snapshotID: String? = nil) async -> CGImage? {
        guard url.isFileURL else {
            counters.failures += 1
            return nil
        }
        let size = max(1, min(1024, maxPixelSize))
        let fingerprint: Fingerprint?
        let key: String
        if let snapshotID {
            fingerprint = nil
            key = Fingerprint.snapshotKey(url: url, snapshotID: snapshotID, size: size)
        } else {
            guard let current = Fingerprint.read(url) else {
                counters.failures += 1
                return nil
            }
            fingerprint = current
            key = current.key(size: size)
        }
        clock &+= 1
        if var entry = memory[key] {
            entry.lastUse = clock
            memory[key] = entry
            counters.memoryHits += 1
            return entry.image
        }
        if let pending = inFlight[key] {
            counters.coalescedRequests += 1
            let decoded = await pending.value
            if let fingerprint, Fingerprint.read(url) != fingerprint { return nil }
            return decoded.image
        }

        prepareDiskIfNeeded()
        let diskURL = diskEnabled ? cacheURL(key) : nil
        // The canonical 320px prefetch can also serve now-playing art offline.
        // Probe a fixed set of local size buckets, never the original volume,
        // instead of eagerly creating every size for every game on startup.
        let largerSnapshots: [(URL, Int)] = snapshotID.map { snapshot in
            [320, 480, 640, 1024].filter { $0 > size }.compactMap { pixels in
                let candidate = Fingerprint.snapshotKey(url: url, snapshotID: snapshot, size: pixels)
                guard diskEnabled, let file = cacheURL(candidate) else { return nil }
                return (file, pixels)
            }
        } ?? []
        let smallerSnapshots: [(URL, Int)] = snapshotID.map { snapshot in
            [108, 320, 480, 640, 1024].filter { $0 < size }.reversed().compactMap { pixels in
                let candidate = Fingerprint.snapshotKey(url: url, snapshotID: snapshot, size: pixels)
                guard diskEnabled, let file = cacheURL(candidate) else { return nil }
                return (file, pixels)
            }
        } ?? []
        let maximumDiskFile = min(diskByteLimit, 8 * 1024 * 1024)
        let priority: TaskPriority = Task.currentPriority == .background ? .background : .utility
        let task = Task.detached(priority: priority) {
            Self.decode(source: url, cache: diskURL, size: size,
                        maximumDiskFile: maximumDiskFile, expectedSource: fingerprint,
                        largerSnapshots: largerSnapshots, smallerSnapshots: smallerSnapshots)
        }
        inFlight[key] = task
        let decoded = await task.value
        inFlight[key] = nil
        if decoded.sourceDecode { counters.sourceDecodes += 1 }
        if decoded.diskHit { counters.diskHits += 1 }
        if decoded.invalidDiskFile { removeDiskEntry(key) }
        // Live lookups revalidate before publication. Snapshot hits deliberately
        // preserve their previous image; source-miss decoding is validated below.
        if let fingerprint, Fingerprint.read(url) != fingerprint {
            counters.failures += 1
            return nil
        }
        guard let image = decoded.image else {
            counters.failures += 1
            return nil
        }
        // Keep the lower-detail fallback displayable offline, but do not poison
        // the requested high-resolution key: reconnecting can still upgrade it.
        if decoded.lowerResolutionFallback { return image }
        remember(image, key: key)
        if decoded.diskHit && decoded.png == nil {
            touchDiskEntry(key)
        } else if let png = decoded.png {
            persist(png, key: key)
        }
        return image
    }

    func statistics() -> Statistics {
        var value = counters
        value.memoryBytes = memoryBytes
        value.memoryEntries = memory.count
        value.diskBytes = diskBytes
        value.diskEntries = disk.count
        return value
    }

    private static func decode(source: URL, cache: URL?, size: Int, maximumDiskFile: Int,
                               expectedSource: Fingerprint?, largerSnapshots: [(URL, Int)],
                               smallerSnapshots: [(URL, Int)]) -> Decoded {
        var invalidDiskFile = false
        if let cache, let attributes = try? FileManager.default.attributesOfItem(atPath: cache.path) {
            let length = (attributes[.size] as? NSNumber)?.intValue ?? 0
            if attributes[.type] as? FileAttributeType == .typeRegular,
               length > 0, length <= maximumDiskFile,
               let data = try? Data(contentsOf: cache),
               let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
               CGImageSourceGetType(source) as String? == "public.png",
               let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
               let width = properties[kCGImagePropertyPixelWidth] as? Int,
               let height = properties[kCGImagePropertyPixelHeight] as? Int,
               width > 0, height > 0, width <= size, height <= size,
               let image = CGImageSourceCreateImageAtIndex(source, 0,
                   [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) {
                return Decoded(image: image, png: nil, diskHit: true, sourceDecode: false, invalidDiskFile: false)
            }
            invalidDiskFile = true
        }
        for (file, maximumPixels) in largerSnapshots {
            guard let image = savedThumbnail(at: file, maximumPixels: maximumPixels,
                                             requestedPixels: size, maximumDiskFile: maximumDiskFile) else { continue }
            return Decoded(image: image, png: pngData(image), diskHit: true,
                           sourceDecode: false, invalidDiskFile: invalidDiskFile)
        }
        func unavailableSource(attemptedDecode: Bool) -> Decoded {
            for (file, maximumPixels) in smallerSnapshots {
                guard let image = savedThumbnail(at: file, maximumPixels: maximumPixels,
                                                 requestedPixels: maximumPixels, maximumDiskFile: maximumDiskFile) else { continue }
                return Decoded(image: image, png: nil, diskHit: true, sourceDecode: attemptedDecode,
                               invalidDiskFile: invalidDiskFile, lowerResolutionFallback: true)
            }
            return Decoded(image: nil, png: nil, diskHit: false, sourceDecode: attemptedDecode, invalidDiskFile: invalidDiskFile)
        }
        // Only a local-cache miss is allowed to touch the original volume.
        // Guard both ends of the decode so an in-progress replacement isn't saved.
        guard let before = Fingerprint.read(source), expectedSource == nil || before == expectedSource else {
            return unavailableSource(attemptedDecode: false)
        }
        guard let artwork = CGImageSourceCreateWithURL(URL(fileURLWithPath: before.path) as CFURL,
                  [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(artwork, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: size,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary), image.width <= size, image.height <= size,
              Fingerprint.read(source) == before else {
            return unavailableSource(attemptedDecode: true)
        }
        let png = cache != nil ? pngData(image) : nil
        return Decoded(image: image, png: png, diskHit: false, sourceDecode: true, invalidDiskFile: invalidDiskFile)
    }

    private static func savedThumbnail(at file: URL, maximumPixels: Int, requestedPixels: Int,
                                       maximumDiskFile: Int) -> CGImage? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let length = (attributes[.size] as? NSNumber)?.intValue,
              length > 0, length <= maximumDiskFile,
              let data = try? Data(contentsOf: file),
              let artwork = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(artwork) as String? == "public.png",
              let properties = CGImageSourceCopyPropertiesAtIndex(artwork, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= maximumPixels, height <= maximumPixels else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(artwork, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: requestedPixels,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }

    private static func pngData(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    private func remember(_ image: CGImage, key: String) {
        let bytes = image.bytesPerRow * image.height
        guard bytes <= memoryByteLimit else { return }
        if let old = memory.removeValue(forKey: key) { memoryBytes -= old.bytes }
        while memoryBytes + bytes > memoryByteLimit,
              let oldest = memory.min(by: { $0.value.lastUse < $1.value.lastUse })?.key {
            if let removed = memory.removeValue(forKey: oldest) { memoryBytes -= removed.bytes }
        }
        clock &+= 1
        memory[key] = MemoryEntry(image: image, bytes: bytes, lastUse: clock)
        memoryBytes += bytes
    }

    private func cacheURL(_ key: String) -> URL? {
        directory?.appendingPathComponent("thumb-v1-\(key).png", isDirectory: false)
    }

    private static func ownedKey(_ filename: String) -> String? {
        guard filename.hasPrefix("thumb-v1-"), filename.hasSuffix(".png") else { return nil }
        let key = String(filename.dropFirst(9).dropLast(4))
        guard key.count == 64, key.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
        return key
    }

    private func prepareDiskIfNeeded() {
        guard !didPrepareDisk else { return }
        didPrepareDisk = true
        guard let directory, directory.isFileURL, diskByteLimit > 0, maxDiskEntries > 0 else { return }
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let attributes = try manager.attributesOfItem(atPath: directory.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory else { return }
            guard let files = manager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey],
                                                options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]) else { return }
            // A normal namespace has at most 256 files. Refuse persistent writes
            // to an unexpectedly huge directory instead of doing unbounded work.
            var visited = 0
            while let url = files.nextObject() as? URL {
                visited += 1
                guard visited <= 1024 else { disk.removeAll(); diskBytes = 0; return }
                guard let key = Self.ownedKey(url.lastPathComponent),
                      let metadata = try? manager.attributesOfItem(atPath: url.path),
                      metadata[.type] as? FileAttributeType == .typeRegular,
                      let bytes = (metadata[.size] as? NSNumber)?.intValue else { continue }
                disk[key] = DiskEntry(bytes: bytes, lastUse: metadata[.modificationDate] as? Date ?? .distantPast)
                diskBytes += bytes
            }
            diskEnabled = true
            trimDisk()
        } catch {
            // Read-only/full/unavailable cache storage must not hide a valid cover.
        }
    }

    private func touchDiskEntry(_ key: String) {
        guard let url = cacheURL(key), let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let bytes = (attributes[.size] as? NSNumber)?.intValue else { return }
        if let previous = disk[key] { diskBytes -= previous.bytes }
        let now = Date()
        disk[key] = DiskEntry(bytes: bytes, lastUse: now)
        diskBytes += bytes
        try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
        trimDisk()
    }

    private func persist(_ data: Data, key: String) {
        guard diskEnabled, data.count <= diskByteLimit, data.count <= 8 * 1024 * 1024,
              let url = cacheURL(key) else { return }
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           attributes[.type] as? FileAttributeType != .typeRegular { return }
        do {
            try data.write(to: url, options: .atomic)
            touchDiskEntry(key)
        } catch { /* RAM cache still serves the successfully decoded thumbnail. */ }
    }

    private func trimDisk() {
        // At most 1024 known files are considered, and only our exact versioned
        // filenames are deleted. Adjacent documents/subdirectories are untouched.
        let oldest = disk.sorted { $0.value.lastUse < $1.value.lastUse }
        for (key, _) in oldest where diskBytes > diskByteLimit || disk.count > maxDiskEntries {
            removeDiskEntry(key)
        }
    }

    private func removeDiskEntry(_ key: String) {
        guard let url = cacheURL(key), Self.ownedKey(url.lastPathComponent) != nil else { return }
        let manager = FileManager.default
        if let attributes = try? manager.attributesOfItem(atPath: url.path) {
            guard attributes[.type] as? FileAttributeType == .typeRegular else { return }
            do { try manager.removeItem(at: url) } catch { return }
        }
        if let removed = disk.removeValue(forKey: key) { diskBytes -= removed.bytes }
    }
}
