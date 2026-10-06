import Foundation
import CryptoKit
import Darwin

/// Stores the last successful FULL LOAD, never ROM data. Normal browsing reads
/// only saved memory/JSON, even with the game folder unavailable. A first load or
/// forced refresh (explicit or throttled background discovery) rebuilds metadata.
actor CatalogCache {
    static let shared = CatalogCache()

    struct CachedArtwork: Sendable {
        let url: URL
        let snapshotID: String
    }

    struct Statistics: Sendable {
        var scans = 0
        var fingerprintChecks = 0
        var memoryHits = 0
        var diskHits = 0
        var coalescedRequests = 0
        var diskWrites = 0
    }

    private struct Snapshot: Codable, Sendable {
        let version: Int
        let sourceKey: String
        let fingerprint: String
        let inventory: CatalogScanner.Inventory
        let sourceRootPath: String?
        let canonicalRootPath: String?
    }

    private struct Outcome: Sendable {
        let inventory: CatalogScanner.Inventory
        let snapshot: Snapshot?
        var statistics = Statistics()
    }

    private struct Flight {
        let id: UUID
        let force: Bool
        let task: Task<Outcome, Never>
    }

    private static let version = 2
    private static let maximumSnapshotBytes = 4 * 1024 * 1024
    private static let maximumDiskBytes = 16 * 1024 * 1024
    private static let maximumEntries = 8
    private let directory: URL
    private var entries: [String: Snapshot] = [:]
    private var accessOrder: [String] = []
    private var flights: [String: Flight] = [:]
    private var counters = Statistics()

    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/local.rafael.centraldejogos/Catalog", isDirectory: true)) {
        self.directory = directory
    }

    func statistics() -> Statistics { counters }

    func load(_ source: CatalogSource, force: Bool = false,
              priority: TaskPriority = .userInitiated) async -> CatalogScanResult {
        let outcome = await loadOutcome(source, force: force, priority: priority)
        return CatalogScanResult(games: outcome.inventory.result.games, warning: outcome.inventory.result.warning,
                                 snapshotID: outcome.snapshot?.fingerprint)
    }

    /// Startup restore is saved-only: an absent/corrupt snapshot returns nil,
    /// never waking a disconnected library or triggering an initial FULL LOAD.
    func loadSaved(_ source: CatalogSource) async -> CatalogScanResult? {
        guard let snapshot = await cachedSnapshot(source) else { return nil }
        return CatalogScanResult(games: snapshot.inventory.result.games, warning: snapshot.inventory.result.warning,
                                 snapshotID: snapshot.fingerprint)
    }

    /// Compatibility wrapper: artwork lookup never triggers a full library scan.
    func coverForLoadedGame(path: String, source: CatalogSource) async -> URL? {
        await cachedArtworkForLoadedGame(path: path, source: source)?.url
    }

    /// Cover-independent ownership for session identity/history. The monitor must
    /// still confirm the process and loaded file; saved membership alone never
    /// claims that a game is running. Ambiguous playlist owners are not guessed.
    func cachedGameForLoadedGame(path: String, source: CatalogSource) async -> CatalogGame? {
        await cachedOwner(path: path, source: source)?.game
    }

    /// Resolve exactly one saved CUE/CCD/playlist owner. This intentionally does
    /// not stat the loaded game or artwork; the emulator monitor verifies the
    /// active game, and the artwork cache serves that snapshot's saved thumbnail.
    func cachedArtworkForLoadedGame(path: String, source: CatalogSource) async -> CachedArtwork? {
        guard let owner = await cachedOwner(path: path, source: source), let cover = owner.game.coverURL else { return nil }
        return CachedArtwork(url: cover, snapshotID: owner.snapshotID)
    }

    private func cachedOwner(path: String, source: CatalogSource) async -> (game: CatalogGame, snapshotID: String)? {
        guard ["ps1", "ps2"].contains(source.consoleKey), path.hasPrefix("/"),
              let snapshot = await cachedSnapshot(source) else { return nil }
        let file = Self.memberPath(path, snapshot: snapshot, source: source)
        let inventory = snapshot.inventory
        let matches = inventory.result.games.filter { game in
            inventory.members[game.id]?.contains(where: { Self.pathIdentity($0) == file }) == true
        }
        guard matches.count == 1 else { return nil }
        return (matches[0], snapshot.fingerprint)
    }

    /// Disk lookup only: used for now-playing art, where absent cache must never
    /// start scanning thousands of files merely because emulator state changed.
    private func cachedSnapshot(_ source: CatalogSource) async -> Snapshot? {
        let key = Self.key(for: source)
        if let snapshot = entries[key], Self.valid(snapshot, key: key, source: source) {
            counters.memoryHits += 1
            remember(snapshot, key: key)
            return snapshot
        }
        let file = directory.appendingPathComponent("catalog-\(key).json")
        let stored = await Task.detached(priority: .utility) {
            guard let snapshot = Self.readSnapshot(file), Self.valid(snapshot, key: key, source: source) else { return nil as Snapshot? }
            return snapshot
        }.value
        // Do not overwrite a newer forced refresh that completed during disk I/O.
        if let current = entries[key], Self.valid(current, key: key, source: source) { return current }
        if let stored {
            counters.diskHits += 1
            remember(stored, key: key)
        }
        return stored
    }

    private func loadOutcome(_ source: CatalogSource, force: Bool, priority: TaskPriority) async -> Outcome {
        let key = Self.key(for: source)
        if !force, let snapshot = entries[key], Self.valid(snapshot, key: key, source: source) {
            counters.memoryHits += 1
            remember(snapshot, key: key)
            return Outcome(inventory: snapshot.inventory, snapshot: snapshot)
        }
        if let flight = flights[key] {
            // A forced refresh must not silently turn into a pending cache hit.
            if force && !flight.force {
                _ = await complete(flight, key: key)
                return await loadOutcome(source, force: true, priority: priority)
            }
            counters.coalescedRequests += 1
            return await complete(flight, key: key)
        }
        let candidate = entries[key]
        let directory = self.directory
        let task = Task.detached(priority: priority) {
            Self.fetch(source, key: key, directory: directory, candidate: candidate, force: force)
        }
        let flight = Flight(id: UUID(), force: force, task: task)
        flights[key] = flight
        return await complete(flight, key: key)
    }

    private func remember(_ snapshot: Snapshot, key: String) {
        entries[key] = snapshot
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
        while accessOrder.count > Self.maximumEntries { entries.removeValue(forKey: accessOrder.removeFirst()) }
    }

    private func complete(_ flight: Flight, key: String) async -> Outcome {
        let outcome = await flight.task.value
        if flights[key]?.id == flight.id {
            flights.removeValue(forKey: key)
            if let snapshot = outcome.snapshot { remember(snapshot, key: key) }
            counters.scans += outcome.statistics.scans
            counters.fingerprintChecks += outcome.statistics.fingerprintChecks
            counters.memoryHits += outcome.statistics.memoryHits
            counters.diskHits += outcome.statistics.diskHits
            counters.diskWrites += outcome.statistics.diskWrites
        }
        return outcome
    }

    private static func fetch(_ source: CatalogSource, key: String, directory: URL,
                              candidate: Snapshot?, force: Bool) -> Outcome {
        var metrics = Statistics()
        let file = directory.appendingPathComponent("catalog-\(key).json")
        let previous: Snapshot?
        if let candidate, valid(candidate, key: key, source: source) { previous = candidate }
        else if let stored = readSnapshot(file), valid(stored, key: key, source: source) { previous = stored }
        else { previous = nil }
        if !force, let previous {
            if candidate != nil { metrics.memoryHits += 1 } else { metrics.diskHits += 1 }
            return Outcome(inventory: previous.inventory, snapshot: previous, statistics: metrics)
        }
        func failure(_ message: String) -> Outcome {
            if let previous {
                let inventory = CatalogScanner.Inventory(games: previous.inventory.result.games,
                    warning: "Full load did not finish. Showing the last saved catalog. \(message)",
                    members: previous.inventory.members)
                return Outcome(inventory: inventory, snapshot: previous, statistics: metrics)
            }
            return Outcome(inventory: CatalogScanner.Inventory(warning: message, reliable: false),
                           snapshot: nil, statistics: metrics)
        }
        for _ in 0..<2 {
            metrics.fingerprintChecks += 1
            let before: String
            do { before = try fingerprint(source) }
            catch { return failure("Game folder unavailable or unreadable. Check the path and permissions; if it is an external disk, reconnect it and reload the catalog.") }
            metrics.scans += 1
            let inventory = CatalogScanner.inventory(source)
            guard inventory.reliable else {
                return failure(inventory.result.warning ?? "The library could not be read safely.")
            }
            metrics.fingerprintChecks += 1
            guard let after = try? fingerprint(source) else {
                return failure("The library became unavailable during the update. Check access to the folder and try again.")
            }
            guard before == after else { continue }
            let snapshot = Snapshot(version: version, sourceKey: key, fingerprint: after, inventory: inventory,
                sourceRootPath: lexicalPath(source.root.path),
                canonicalRootPath: lexicalPath(source.root.standardizedFileURL.resolvingSymlinksInPath().path))
            if write(snapshot, to: file, directory: directory) { metrics.diskWrites += 1 }
            return Outcome(inventory: inventory, snapshot: snapshot, statistics: metrics)
        }
        return failure("The library changed during the update. Reload again when the files have finished copying.")
    }

    /// Pure string/JSON validation only. No stat, root resolution, readability
    /// check or fingerprint is permitted on the normal snapshot-browsing path.
    private static func valid(_ snapshot: Snapshot, key: String, source: CatalogSource) -> Bool {
        guard [1, version].contains(snapshot.version), snapshot.sourceKey == key,
              snapshot.fingerprint.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil,
              snapshot.inventory.reliable else { return false }
        let sourceRoot = lexicalPath(source.root.path)
        if snapshot.version == version {
            guard snapshot.sourceRootPath == sourceRoot, let root = snapshot.canonicalRootPath,
                  root.hasPrefix("/"), lexicalPath(root) == root, root != "/" else { return false }
        }
        let prefix = pathIdentity(snapshot.canonicalRootPath ?? sourceRoot) + "/"
        let games = snapshot.inventory.result.games
        // Treat local JSON as data, not authority to launch paths outside a library.
        guard Set(games.map(\.id)).count == games.count else { return false }
        return games.allSatisfy { game in
            game.consoleKey == source.consoleKey && game.fileURL.isFileURL && game.id == game.fileURL.path
                && pathIdentity(game.id).hasPrefix(prefix) && lexicalPath(game.id) == game.id
                && (game.coverURL.map { $0.isFileURL && $0.path.hasPrefix("/") && lexicalPath($0.path) == $0.path } ?? true)
                && snapshot.inventory.members[game.id]?.contains(game.id) == true
                && snapshot.inventory.members[game.id]?.allSatisfy { pathIdentity($0).hasPrefix(prefix) && lexicalPath($0) == $0 } == true
        }
    }

    private static func key(for source: CatalogSource) -> String {
        let paths = [source.consoleKey, lexicalPath(source.root.path), lexicalPath(source.covers.path),
                     source.database.map { lexicalPath($0.path) } ?? "<nil>", source.frontCovers.map { lexicalPath($0.path) } ?? "<nil>"]
        // JSON preserves boundaries even if a filename contains a newline.
        return digest((try? JSONEncoder().encode(paths)) ?? Data())
    }

    private static func lexicalPath(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/") {
            if part == "." { continue }
            if part == ".." { if !parts.isEmpty { parts.removeLast() }; continue }
            parts.append(part)
        }
        return (path.hasPrefix("/") ? "/" : "") + parts.joined(separator: "/")
    }

    /// macOS exposes these stable aliases in log paths and Foundation URLs.
    /// Normalize them lexically without resolving any live filesystem symlink.
    private static func pathIdentity(_ path: String) -> String {
        let path = lexicalPath(path)
        for alias in ["var", "tmp", "etc"] {
            let prefix = "/private/\(alias)"
            if path == prefix || path.hasPrefix(prefix + "/") { return String(path.dropFirst("/private".count)) }
        }
        return path
    }

    private static func memberPath(_ path: String, snapshot: Snapshot, source: CatalogSource) -> String {
        let path = pathIdentity(path)
        let sourceRoot = pathIdentity(snapshot.sourceRootPath ?? source.root.path)
        let canonicalRoot = pathIdentity(snapshot.canonicalRootPath ?? sourceRoot)
        if path.hasPrefix(sourceRoot + "/") { return canonicalRoot + path.dropFirst(sourceRoot.count) }
        return path
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func readSnapshot(_ file: URL) -> Snapshot? {
        guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true, let size = values.fileSize, size > 0, size <= maximumSnapshotBytes,
              let data = try? Data(contentsOf: file), data.count <= maximumSnapshotBytes else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    private static func write(_ snapshot: Snapshot, to file: URL, directory: URL) -> Bool {
        guard let data = try? JSONEncoder().encode(snapshot), data.count <= maximumSnapshotBytes else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            trimDisk(directory, keeping: file)
            return true
        } catch { return false } // A read-only/full cache volume must not break playing.
    }

    private static func trimDisk(_ directory: URL, keeping current: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]) else { return }
        var items: [(URL, Int, Date)] = files.compactMap { file in
            guard file.lastPathComponent.range(of: #"^catalog-[0-9a-f]{64}\.json$"#, options: .regularExpression) != nil,
                  let info = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]),
                  info.isRegularFile == true else { return nil }
            return (file, info.fileSize ?? 0, info.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var size = items.reduce(0) { $0 + $1.1 }
        while items.count > maximumEntries || size > maximumDiskBytes {
            guard let index = items.firstIndex(where: { $0.0 != current }) else { break }
            let item = items.remove(at: index)
            if (try? fm.removeItem(at: item.0)) != nil { size -= item.1 }
        }
    }

    private enum MetadataError: Error { case unavailable }

    /// Hash only names and stat metadata, not game contents or decoded artwork.
    /// inode/device, volume UUID, nanosecond mtime + ctime detect replacement,
    /// in-place edits, permission changes, and a different SSD at the same path.
    private static func fingerprint(_ source: CatalogSource) throws -> String {
        var hasher = SHA256()
        func append(_ fields: [String]) throws { hasher.update(data: try JSONEncoder().encode(fields)) }
        func metadata(_ url: URL) throws -> stat {
            var info = stat()
            guard lstat(url.path, &info) == 0 else { throw MetadataError.unavailable }
            try append([url.path, String(info.st_dev), String(info.st_ino), String(info.st_mode),
                        String(info.st_uid), String(info.st_gid), String(info.st_size),
                        String(info.st_mtimespec.tv_sec), String(info.st_mtimespec.tv_nsec),
                        String(info.st_ctimespec.tv_sec), String(info.st_ctimespec.tv_nsec)])
            return info
        }
        func isDirectory(_ info: stat) -> Bool { (info.st_mode & S_IFMT) == S_IFDIR }
        func readable(_ url: URL, _ info: stat) -> Bool {
            let mode = isDirectory(info) ? R_OK | X_OK : R_OK
            return info.st_mode & 0o444 != 0 && (!isDirectory(info) || info.st_mode & 0o111 != 0)
                && access(url.path, mode) == 0
        }
        func node(_ url: URL, recursive: Bool, required: Bool, requireDirectory: Bool = false, gameTree: Bool = false) throws {
            var initial = stat()
            if lstat(url.path, &initial) != 0 {
                guard !required else { throw MetadataError.unavailable }
                try append([url.path, "unavailable", String(errno)])
                return
            }
            let original = try metadata(url)
            let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
            let info: stat
            do { info = resolved.path == url.path ? original : try metadata(resolved) }
            catch {
                guard !required else { throw error }
                try append([url.path, "unavailable-target"])
                return
            }
            if (isDirectory(info) && !readable(resolved, info)) || (requireDirectory && !isDirectory(info)) {
                guard !required else { throw MetadataError.unavailable }
                try append([url.path, "unavailable-directory"])
                return
            }
            if let values = try? resolved.resourceValues(forKeys: [.volumeUUIDStringKey]), let uuid = values.volumeUUIDString {
                try append(["volume", uuid])
            }
            guard recursive, isDirectory(info) else { return }
            var pending = [resolved]
            var count = 0
            while let parent = pending.popLast() {
                let children: [URL]
                do {
                    children = try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil,
                                                                           options: [.skipsHiddenFiles])
                } catch {
                    guard !required else { throw error }
                    try append([parent.path, "unreadable-directory"])
                    continue
                }
                for child in children.sorted(by: { $0.path < $1.path }) {
                    count += 1
                    guard count <= 100_000 else { throw MetadataError.unavailable }
                    let childInfo: stat
                    do { childInfo = try metadata(child) }
                    catch {
                        guard !required else { throw error }
                        try append([child.path, "unavailable-child"])
                        continue
                    }
                    if (childInfo.st_mode & S_IFMT) == S_IFLNK {
                        let target = child.resolvingSymlinksInPath()
                        var targetInfo = stat()
                        // Game enumeration ignores symlinks; image decoding can
                        // follow one. Include target metadata without walking loops.
                        if lstat(target.path, &targetInfo) == 0 {
                            _ = try metadata(target)
                        }
                    } else {
                        if isDirectory(childInfo) {
                            if gameTree && (CatalogScanner.excludedDirectories.contains(child.lastPathComponent.lowercased())
                                || (try? child.resourceValues(forKeys: [.isPackageKey]).isPackage) == true) { continue }
                            if !readable(child, childInfo) {
                                guard !required else { throw MetadataError.unavailable }
                                try append([child.path, "unreadable-directory"])
                                continue
                            }
                            pending.append(child)
                        }
                        // Leaf permissions are part of the fingerprint. The
                        // scanner determines relevance/readability; an ignored
                        // archive, README or BIOS must not block every game.
                    }
                }
            }
        }
        try append([String(version), source.consoleKey, "portable-covers-v1"])
        try node(source.root, recursive: true, required: true, requireDirectory: true, gameTree: true)
        // Capas is excluded from ROM enumeration but still invalidates artwork
        // snapshots on an explicit/background full refresh. Warm/offline loads
        // continue to use the saved snapshot without touching the SSD.
        try node(source.portableCovers, recursive: true, required: false, requireDirectory: true)
        try node(source.covers, recursive: true, required: false, requireDirectory: true)
        if let frontCovers = source.frontCovers { try node(frontCovers, recursive: true, required: false, requireDirectory: true) }
        if let database = source.database { try node(database, recursive: false, required: false) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func readableRegularFile(_ file: URL) -> Bool {
        var info = stat()
        let resolved = file.resolvingSymlinksInPath()
        return lstat(resolved.path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
            && info.st_size > 0 && info.st_mode & 0o444 != 0 && access(resolved.path, R_OK) == 0
    }
}
