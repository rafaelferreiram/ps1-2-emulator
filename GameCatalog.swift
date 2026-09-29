import Foundation
import Combine
import ImageIO

struct CatalogGame: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let consoleKey: String
    let title: String
    let fileURL: URL
    let coverURL: URL?
}

struct CatalogScanResult: Codable, Sendable {
    let games: [CatalogGame]
    let warning: String?
    let snapshotID: String?

    init(games: [CatalogGame], warning: String?, snapshotID: String? = nil) {
        self.games = games
        self.warning = warning
        self.snapshotID = snapshotID
    }
}

/// Read-only inventory. Enumeration and small metadata reads happen off the UI thread.
@MainActor
final class GameCatalog: ObservableObject {
    @Published private(set) var games: [String: [CatalogGame]] = ["ps1": [], "ps2": []]
    @Published private(set) var loading: Set<String> = []
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var revisions: [String: Int] = [:]
    @Published private(set) var snapshotIDs: [String: String] = [:]
    private var generations: [String: Int] = [:]
    private let cache: CatalogCache
    private let coverCache: CoverImageCache
    private var sources: [String: CatalogSource]

    init(cache: CatalogCache = .shared, coverCache: CoverImageCache = .shared, sources: [String: CatalogSource]? = nil) {
        self.cache = cache
        self.coverCache = coverCache
        self.sources = sources ?? Dictionary(uniqueKeysWithValues: ["ps1", "ps2"].compactMap { key in
            CatalogSource.installed(key).map { (key, $0) }
        })
    }

    func source(for key: String) -> CatalogSource? {
        sources[key]
    }

    /// Switching libraries immediately removes the previous console's visible
    /// inventory and invalidates its pending work. Saved snapshots remain keyed
    /// by their source, so switching back can restore offline without a scan.
    /// An explicit folder selection may pass `restoreSaved: false` then refresh.
    @discardableResult
    func setSource(_ source: CatalogSource, restoreSaved: Bool = true) -> Task<Void, Never> {
        let key = source.consoleKey
        guard ["ps1", "ps2"].contains(key) else { return Task {} }
        if let previous = sources[key],
           previous.root.standardizedFileURL == source.root.standardizedFileURL,
           previous.covers == source.covers, previous.database == source.database,
           previous.frontCovers == source.frontCovers { return Task {} }
        sources[key] = source
        invalidate(key)
        guard restoreSaved, let generation = generations[key] else { return Task {} }
        return restoreSavedCatalog(source, generation: generation)
    }

    private func restoreSavedCatalog(_ source: CatalogSource, generation: Int) -> Task<Void, Never> {
        let cache = self.cache
        return Task { [weak self] in
            guard let result = await cache.loadSaved(source), let self,
                  self.publish(result, for: source.consoleKey, generation: generation) else { return }
            await self.warm(result, for: source.consoleKey, generation: generation)
        }
    }

    /// Populate both console menus from local snapshots at app startup, including
    /// offline starts. No cached inventory means no automatic scan. Restoration
    /// does not claim `loading`, so an explicit user refresh can supersede it.
    @discardableResult
    func restoreSavedCatalogs() -> Task<Void, Never> {
        var restores: [Task<Void, Never>] = []
        for key in ["ps1", "ps2"] {
            guard generations[key] == nil, let source = source(for: key) else { continue }
            let generation = 1
            generations[key] = generation
            restores.append(restoreSavedCatalog(source, generation: generation))
        }
        return Task { for restore in restores { await restore.value } }
    }

    func refresh(_ consoleKey: String, force: Bool = false) {
        guard let source = source(for: consoleKey), force || !loading.contains(consoleKey) else { return }
        let generation = (generations[consoleKey] ?? 0) + 1
        generations[consoleKey] = generation
        loading.insert(consoleKey)
        errors.removeValue(forKey: consoleKey)
        let cache = self.cache
        Task { [weak self] in
            let result = await cache.load(source, force: force)
            guard let self, self.publish(result, for: consoleKey, generation: generation) else { return }
            await self.warm(result, for: consoleKey, generation: generation)
        }
    }

    private func publish(_ result: CatalogScanResult, for key: String, generation: Int) -> Bool {
        guard generations[key] == generation else { return false }
        games[key] = result.games
        errors[key] = result.warning
        snapshotIDs[key] = result.snapshotID
        loading.remove(key)
        revisions[key, default: 0] += 1
        return true
    }

    /// Model-owned warming survives closing the catalog view. Snapshot cache
    /// hits use local thumbnails; only a missing thumbnail tries its source art.
    private func warm(_ result: CatalogScanResult, for key: String, generation: Int) async {
        guard let snapshotID = result.snapshotID else { return }
        for url in Set(result.games.compactMap(\.coverURL)) {
            guard generations[key] == generation else { return }
            _ = await coverCache.image(at: url, maxPixelSize: 320, snapshotID: snapshotID)
            guard generations[key] == generation else { return }
            _ = await coverCache.image(at: url, maxPixelSize: 108, snapshotID: snapshotID)
        }
    }

    /// Explicitly clear the visible model when resetting the catalog, not merely
    /// when a game folder disconnects: saved inventories remain browsable offline.
    func invalidate(_ consoleKey: String) {
        generations[consoleKey, default: 0] += 1
        games[consoleKey] = []
        errors.removeValue(forKey: consoleKey)
        snapshotIDs.removeValue(forKey: consoleKey)
        loading.remove(consoleKey)
        revisions[consoleKey, default: 0] += 1
    }
}

struct CatalogSource: Sendable {
    let consoleKey: String
    let root: URL
    let covers: URL
    let database: URL?
    let frontCovers: URL?

    init(consoleKey: String, root: URL, covers: URL, database: URL?, frontCovers: URL? = nil) {
        self.consoleKey = consoleKey
        self.root = root
        self.covers = covers
        self.database = database
        self.frontCovers = frontCovers
    }

    static func installed(_ consoleKey: String, root: URL? = nil) -> CatalogSource? {
        guard consoleKey == "ps1" || consoleKey == "ps2" else { return nil }
        let emulator = consoleKey == "ps1" ? "DuckStation" : "PCSX2"
        return CatalogSource(consoleKey: consoleKey,
            root: root ?? URL(fileURLWithPath: "/Volumes/Extreme SSD/Emulacao/\(consoleKey.uppercased())/Jogos", isDirectory: true),
            covers: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/\(emulator)/covers", isDirectory: true),
            database: URL(fileURLWithPath: "/Applications/\(emulator).app/Contents/Resources/\(consoleKey == "ps1" ? "gamedb.yaml" : "GameIndex.yaml")"),
            frontCovers: Bundle.main.resourceURL?.appendingPathComponent("Covers/\(consoleKey.uppercased())", isDirectory: true))
    }
}

enum CatalogScanner {
    static let excludedDirectories: Set<String> = [
        "bios", "cache", "saves", "savestates", "memcards", "covers", "thumbnails", "__macosx"
    ]
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp"]

    static func scan(_ source: CatalogSource) -> CatalogScanResult {
        inventory(source).result
    }

    /// Resolve artwork only from an exact, existing library path. A loaded disc may
    /// belong to a CUE/CCD or playlist entry; competing owners are deliberately not guessed.
    /// Call on a background task when the emulator's loaded path changes, not on every timer tick.
    static func coverForLoadedGame(path: String, source: CatalogSource) -> URL? {
        guard (source.consoleKey == "ps1" || source.consoleKey == "ps2"), path.hasPrefix("/") else { return nil }
        let root = source.root.standardizedFileURL.resolvingSymlinksInPath()
        let file = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        guard file.path.hasPrefix(root.path + "/"), readableFile(file) else { return nil }
        let inventory = inventory(source)
        let matches = inventory.result.games.filter { inventory.members[$0.id]?.contains(file.path) == true }
        guard matches.count == 1 else { return nil }
        return matches[0].coverURL
    }

    struct Inventory: Codable, Sendable {
        let result: CatalogScanResult
        let members: [String: Set<String>]
        let reliable: Bool

        init(games: [CatalogGame] = [], warning: String?, members: [String: Set<String>] = [:], reliable: Bool = true) {
            result = CatalogScanResult(games: games, warning: warning)
            self.members = members
            self.reliable = reliable
        }
    }

    static func inventory(_ source: CatalogSource) -> Inventory {
        let fm = FileManager.default
        let root = source.root.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return Inventory(warning: "Game folder unavailable. Check the path and, if it is external, the disk connection.", reliable: false)
        }
        guard fm.isReadableFile(atPath: root.path) else {
            return Inventory(warning: "The game folder could not be read.", reliable: false)
        }
        let supported: Set<String> = source.consoleKey == "ps1"
            ? ["cue", "ccd", "chd", "iso", "pbp", "img", "bin", "m3u"]
            : ["iso", "chd", "cso", "zso", "gz", "bin", "img", "mdf"]
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        var unreadable = false
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys,
                                             options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                             errorHandler: { _, _ in unreadable = true; return true }) else {
            return Inventory(warning: "The game folder could not be listed.", reliable: false)
        }
        var files: [URL] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else {
                unreadable = true
                enumerator.skipDescendants(); continue
            }
            guard values.isSymbolicLink != true else {
                enumerator.skipDescendants(); continue
            }
            if values.isDirectory == true {
                if excludedDirectories.contains(url.lastPathComponent.lowercased()) { enumerator.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true, (values.fileSize ?? 0) > 0,
                  supported.contains(url.pathExtension.lowercased()), !isBIOS(url) else { continue }
            files.append(url.standardizedFileURL)
        }
        files.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        var candidates = Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0) })
        var members = Dictionary(uniqueKeysWithValues: files.map { ($0.path, Set([$0.path])) })
        var dataFiles: [String: URL] = [:]
        var referenced = Set<String>()
        var invalidDescriptors = 0
        for file in files where file.pathExtension.lowercased() == "cue" {
            let cue = cueReferences(file)
            let referenceNames = cue.names
            let refs = referenceNames.compactMap { resolve($0, relativeTo: file, within: root) }
            // Even a broken CUE must not expose its component audio/data tracks as games.
            referenced.formUnion(refs.map(\.path))
            let valid = cue.valid && !referenceNames.isEmpty && refs.count == referenceNames.count && refs.allSatisfy(readableFile)
            if valid {
                dataFiles[file.path] = refs.first
                members[file.path, default: []].formUnion(refs.map(\.path))
            }
            else { candidates.removeValue(forKey: file.path); invalidDescriptors += 1 }
        }
        for file in files where file.pathExtension.lowercased() == "ccd" {
            let img = file.deletingPathExtension().appendingPathExtension("img")
            if let resolved = resolve(img.lastPathComponent, relativeTo: file, within: root), readableFile(resolved) {
                referenced.insert(resolved.path)
                dataFiles[file.path] = resolved
                members[file.path, default: []].insert(resolved.path)
            } else { candidates.removeValue(forKey: file.path); invalidDescriptors += 1 }
        }
        for path in referenced { candidates.removeValue(forKey: path) }
        // Loose Track 2/3/etc. BINs are audio. A folder with no CUE still has one
        // game: its first data track. Later tracks stay attached to that entry.
        var looseTracks: [String: [URL]] = [:]
        for file in files where file.pathExtension.lowercased() == "bin" && isTrack(file) {
            candidates.removeValue(forKey: file.path)
            if !referenced.contains(file.path) {
                looseTracks[file.deletingLastPathComponent().path, default: []].append(file)
            }
        }
        for tracks in looseTracks.values {
            guard let first = tracks.min(by: { trackOrder($0, $1) }), trackNumber(first) == 1 else { continue }
            candidates[first.path] = first
            var group = members[first.path] ?? [first.path]
            for track in tracks where track.path != first.path { group.insert(track.path) }
            members[first.path] = group
            dataFiles[first.path] = first
        }

        // A valid playlist is one launch entry. Invalid/cyclic playlists never hide valid discs.
        let nonPlaylistPaths = Set(candidates.values.filter { $0.pathExtension.lowercased() != "m3u" }.map(\.path))
        var playlistDiscs = Set<String>()
        for file in files where file.pathExtension.lowercased() == "m3u" {
            let names = playlistReferences(file)
            let refs = names.compactMap { resolve($0, relativeTo: file, within: root) }
            if !names.isEmpty && refs.count == names.count && refs.allSatisfy({ nonPlaylistPaths.contains($0.path) && readableFile($0) }) {
                playlistDiscs.formUnion(refs.map(\.path))
                if let first = refs.first { dataFiles[file.path] = dataFiles[first.path] ?? first }
                for disc in refs { members[file.path, default: []].formUnion(members[disc.path] ?? [disc.path]) }
            } else { candidates.removeValue(forKey: file.path); invalidDescriptors += 1 }
        }
        for path in playlistDiscs { candidates.removeValue(forKey: path) }

        let frontCoverIndex = source.frontCovers.map { imageIndex(in: $0, consoleKey: source.consoleKey) } ?? [:]
        let coverIndex = imageIndex(in: source.covers, consoleKey: source.consoleKey)
        let names = databaseNames(source.database)
        let gamePaths = candidates.values.map(\.path)
        var pending: [PendingGame] = []
        for file in candidates.values {
            guard readableFile(file) else { unreadable = true; continue }
            let title = displayTitle(file)
            let serial = serialIn(file.deletingPathExtension().lastPathComponent)
                ?? discSerial(dataFiles[file.path] ?? file)
            let officialName = serial.flatMap { names[$0] }
            let searchDirectories = coverSearchDirectories(file: file, gamePaths: gamePaths, rootPath: root.path)
            let cover = findCover(file: file, title: title, serial: serial,
                                  databaseName: officialName, frontCoverIndex: frontCoverIndex,
                                  coverIndex: coverIndex, consoleKey: source.consoleKey,
                                  searchDirectories: searchDirectories)
            pending.append(PendingGame(file: file, title: title, officialName: officialName, cover: cover,
                                       searchDirectories: searchDirectories))
        }
        assignDistinctCovers(&pending, frontCoverIndex: frontCoverIndex, coverIndex: coverIndex, consoleKey: source.consoleKey)
        var games = pending.map {
            CatalogGame(id: $0.file.path, consoleKey: source.consoleKey, title: $0.title, fileURL: $0.file, coverURL: $0.cover)
        }
        games.sort {
            let comparison = $0.title.localizedStandardCompare($1.title)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
        var warnings: [String] = []
        if invalidDescriptors > 0 { warnings.append("\(invalidDescriptors) incomplete CUE/CCD/playlist(s) left out.") }
        if unreadable { warnings.append("Some files could not be read.") }
        return Inventory(games: games, warning: warnings.isEmpty ? nil : warnings.joined(separator: " "), members: members,
                         reliable: !unreadable)
    }

    private static func isBIOS(_ file: URL) -> Bool {
        file.deletingPathExtension().lastPathComponent.range(
            of: #"(?i)^(?:scph[-_ ]?\d+|ps[12][-_ ]?bios|bios)(?:\b|_)"#,
            options: .regularExpression) != nil
    }

    private static func isTrack(_ file: URL) -> Bool {
        file.deletingPathExtension().lastPathComponent.range(
            of: #"(?i)(?:\(|\[|[._ -])track[\s._-]*\d+(?:\)|\])?$"#,
            options: .regularExpression) != nil
    }

    private static func trackNumber(_ file: URL) -> Int {
        let stem = file.deletingPathExtension().lastPathComponent
        guard let regex = try? NSRegularExpression(pattern: #"(?i)track[\s._-]*(\d+)"#),
              let match = regex.firstMatch(in: stem, range: NSRange(stem.startIndex..., in: stem)),
              let range = Range(match.range(at: 1), in: stem),
              let number = Int(stem[range]) else { return Int.max }
        return number
    }

    private static func trackOrder(_ lhs: URL, _ rhs: URL) -> Bool {
        let left = trackNumber(lhs)
        let right = trackNumber(rhs)
        if left != right { return left < right }
        return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
    }

    private static func displayTitle(_ file: URL) -> String {
        let stem = file.deletingPathExtension().lastPathComponent
        let clean = stem.replacingOccurrences(of: #"(?i)^[A-Z]{4}[-_. ]?\d{3}[._]?\d{2}[. _-]*"#,
                                               with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\s*(?:\(|\[)track[\s._-]*\d+(?:\)|\])\s*$"#,
                                  with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return clean.isEmpty ? stem : clean
    }

    private static func textFile(_ url: URL, limit: Int = 128 * 1024) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: limit + 1), data.count <= limit else { return nil }
        return (String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252))?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
    }

    private static func cueReferences(_ file: URL) -> (names: [String], valid: Bool) {
        guard let text = textFile(file),
              let regex = try? NSRegularExpression(pattern: #"(?im)^\s*FILE\s+(?:"([^"]+)"|(\S+))\s+\S+\s*$"#) else { return ([], false) }
        let names = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            let range = match.range(at: match.range(at: 1).location == NSNotFound ? 2 : 1)
            return Range(range, in: text).map { String(text[$0]) }
        }
        let fileLines = text.components(separatedBy: .newlines).filter {
            $0.range(of: #"(?i)^\s*FILE(?:\s|$)"#, options: .regularExpression) != nil
        }.count
        let hasTrack = text.range(of: #"(?im)^\s*TRACK\s+\d+\s+\S+"#, options: .regularExpression) != nil
        return (names, fileLines == names.count && hasTrack)
    }

    private static func playlistReferences(_ file: URL) -> [String] {
        guard let text = textFile(file) else { return [] }
        return text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    private static func resolve(_ name: String, relativeTo descriptor: URL, within root: URL) -> URL? {
        let portableName = name.replacingOccurrences(of: "\\", with: "/")
        guard !portableName.hasPrefix("/"), !portableName.contains(":") else { return nil }
        var file = descriptor.deletingLastPathComponent().appendingPathComponent(portableName).standardizedFileURL
        // Case-insensitive resolution also supports an SSD formatted case-sensitively.
        if !FileManager.default.fileExists(atPath: file.path),
           let siblings = try? FileManager.default.contentsOfDirectory(at: file.deletingLastPathComponent(),
                                                                       includingPropertiesForKeys: nil) {
            let matches = siblings.filter { $0.lastPathComponent.caseInsensitiveCompare(file.lastPathComponent) == .orderedSame }
            guard matches.count == 1, let actual = matches.first else { return nil }
            file = actual.standardizedFileURL
        }
        file = file.resolvingSymlinksInPath()
        guard file.path.hasPrefix(root.path + "/"),
              !file.path.dropFirst(root.path.count + 1).split(separator: "/").contains(where: { $0.hasPrefix(".") }) else { return nil }
        return file
    }

    private static func readableFile(_ file: URL) -> Bool {
        guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, (values.fileSize ?? 0) > 0,
              let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        return ((try? handle.read(upToCount: 1))?.count ?? 0) == 1
    }

    private struct PendingGame {
        let file: URL
        let title: String
        let officialName: String?
        var cover: URL?
        let searchDirectories: [URL]
    }

    /// Folders that contain this game alone, from the disc's folder up to the
    /// library root. A cover beside `GAME/` still belongs to that one disc.
    private static func coverSearchDirectories(file: URL, gamePaths: [String], rootPath: String) -> [URL] {
        var folder = file.deletingLastPathComponent()
        var result: [URL] = []
        while folder.path.hasPrefix(rootPath + "/") {
            let prefix = folder.path + "/"
            if gamePaths.filter({ $0.hasPrefix(prefix) }).count != 1 { break }
            result.append(folder)
            let parent = folder.deletingLastPathComponent()
            if parent.path == folder.path { break }
            folder = parent
        }
        return result
    }

    /// A shared serial cover belongs to the disc that matches the official name.
    /// Another game that reused the serial, such as a patch, keeps only its own art.
    private static func assignDistinctCovers(_ games: inout [PendingGame], frontCoverIndex: [String: URL],
                                             coverIndex: [String: URL], consoleKey: String) {
        let groups = Dictionary(grouping: games.indices.filter { games[$0].cover != nil }) {
            canonicalPath(games[$0].cover!)
        }
        for indices in groups.values where indices.count > 1 {
            let shared = indices.filter { !coverIsInsideGame(games[$0].cover!, file: games[$0].file) }
            guard shared.count > 1 else { continue }
            let official = shared.compactMap { games[$0].officialName }.first ?? ""
            let best = shared.map { titleAffinity(games[$0].title, official: official) }.max() ?? 0
            let top = shared.filter { titleAffinity(games[$0].title, official: official) == best }
            let exact = top.filter { normalized(games[$0].title) == normalized(official) && !official.isEmpty }
            let winners = Set(best == 0 ? [] : (exact.isEmpty ? top : exact))
            for index in shared where !winners.contains(index) {
                let local = findCover(file: games[index].file, title: games[index].title, serial: nil,
                                      databaseName: nil, frontCoverIndex: frontCoverIndex, coverIndex: coverIndex,
                                      consoleKey: consoleKey, searchDirectories: games[index].searchDirectories)
                let sharedPath = games[index].cover.map(canonicalPath)
                games[index].cover = local.map(canonicalPath) == sharedPath ? nil : local
            }
        }
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func coverIsInsideGame(_ cover: URL, file: URL) -> Bool {
        canonicalPath(cover).hasPrefix(canonicalPath(file.deletingLastPathComponent()) + "/")
    }

    private static func titleAffinity(_ title: String, official: String) -> Int {
        let officialNorm = normalized(official)
        let titleNorm = normalized(title)
        guard !officialNorm.isEmpty, !titleNorm.isEmpty else { return 0 }
        if titleNorm == officialNorm { return 10_000 }
        return official.split { !$0.isLetter && !$0.isNumber }
            .map { normalized(String($0)) }
            .filter { $0.count >= 4 && titleNorm.contains($0) }
            .reduce(0) { $0 + $1.count }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    private static func imageIndex(in directory: URL, consoleKey: String) -> [String: URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [:] }
        var result: [String: URL] = [:]
        // Keep the emulator's custom PNG if a downloaded JPEG exists with the same name.
        for file in files.sorted(by: { ($0.pathExtension.lowercased() == "png" ? "0" : "1") + $0.path < ($1.pathExtension.lowercased() == "png" ? "0" : "1") + $1.path }) {
            guard imageExtensions.contains(file.pathExtension.lowercased()),
                  let image = CGImageSourceCreateWithURL(file as CFURL, nil), CGImageSourceGetCount(image) > 0 else { continue }
            if consoleKey == "ps2", !isPortraitCover(image) { continue }
            let key = normalized(file.deletingPathExtension().lastPathComponent)
            if result[key] == nil { result[key] = file }
        }
        return result
    }

    /// A PS2 front cover is a portrait panel. Full case scans (back + spine +
    /// front), banners and square artwork must not masquerade as a front cover,
    /// including when they happen to have the right serial or filename.
    private static func isPortraitCover(_ image: CGImageSource) -> Bool {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
              let pixelWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let pixelHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              pixelWidth.isFinite, pixelHeight.isFinite, pixelWidth > 0, pixelHeight > 0 else { return false }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let rotated = (5...8).contains(orientation)
        let ratio = rotated ? pixelHeight / pixelWidth : pixelWidth / pixelHeight
        return (0.55...0.85).contains(ratio)
    }

    /// Unfolded PS2 case art is about 3:2, with the front on the right.
    private static func soleCaseScan(in directory: URL) -> URL? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return nil }
        let images = files.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
        guard images.count == 1, let file = images.first,
              let source = CGImageSourceCreateWithURL(file as CFURL, nil), CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let pixelHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              pixelWidth > 0, pixelHeight > 0 else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let rotated = (5...8).contains(orientation)
        let ratio = rotated ? pixelHeight / pixelWidth : pixelWidth / pixelHeight
        guard (1.35...1.65).contains(ratio) else { return nil }
        return file
    }

    /// Keeps a normal cover unchanged. An unfolded case becomes its front panel.
    static func displayImage(_ image: CGImage) -> CGImage {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return image }
        let ratio = Double(width) / Double(height)
        guard (1.35...1.65).contains(ratio) else { return image }
        let frontWidth = min(width, max(1, Int((Double(height) * 0.72).rounded())))
        return image.cropping(to: CGRect(x: width - frontWidth, y: 0, width: frontWidth, height: height)) ?? image
    }

    private static func findCover(file: URL, title: String, serial: String?, databaseName: String?,
                                  frontCoverIndex: [String: URL], coverIndex: [String: URL],
                                  consoleKey: String, searchDirectories: [URL]) -> URL? {
        let stem = file.deletingPathExtension().lastPathComponent
        // App-bundled front panels take precedence without changing emulator files.
        // Every source is filtered before matching so no fallback can reintroduce a spread.
        let names = [Optional(stem), Optional(title), serial, databaseName].compactMap({ $0 })
        for index in [frontCoverIndex, coverIndex] {
            for name in names {
                if let cover = index[normalized(name)] { return cover }
            }
        }
        for directory in searchDirectories {
            let nearby = imageIndex(in: directory, consoleKey: consoleKey)
            for name in [stem, title] {
                if let cover = nearby[normalized(name)] { return cover }
            }
            // One image beside a single game is its cover, even as Capa_Titulo.png
            // or a file the user dropped in the folder above GAME/.
            if nearby.count == 1, let cover = nearby.values.first { return cover }
            if let cover = nearby["capa"] ?? nearby["cover"] ?? nearby["front"] { return cover }
            // A lone unfolded case (back, spine, front) still counts. The card shows
            // only the front panel.
            if let scan = soleCaseScan(in: directory) { return scan }
            let coverFolder = imageIndex(in: directory.appendingPathComponent("Capa", isDirectory: true),
                                        consoleKey: consoleKey)
            if let cover = coverFolder["capa"] ?? coverFolder["cover"] ?? coverFolder["front"] { return cover }
        }
        return nil
    }

    /// Reads only top-level serial + name fields, not YAML tags or executable content.
    private static func databaseNames(_ file: URL?) -> [String: String] {
        guard let file, let text = textFile(file, limit: 8 * 1024 * 1024) else { return [:] }
        var serial: String?
        var result: [String: String] = [:]
        text.enumerateLines { line, _ in
            if !line.hasPrefix(" "), line.hasSuffix(":"), let key = serialIn(line), line == key + ":" {
                serial = key
            } else if !line.hasPrefix(" "), !line.isEmpty, !line.hasPrefix("#") { serial = nil }
            if let key = serial, line.hasPrefix("  name: ") {
                var value = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                if value.first == "\"", value.last == "\"" {
                    if let data = ("[" + value + "]").data(using: .utf8),
                       let decoded = try? JSONSerialization.jsonObject(with: data) as? [String], let first = decoded.first {
                        value = first
                    } else { value = String(value.dropFirst().dropLast()) }
                } else if value.first == "'", value.last == "'" {
                    value = String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
                }
                result[key] = value
            }
        }
        return result
    }

    private static func serialIn(_ text: String) -> String? {
        guard let range = text.range(of: #"(?i)\b[A-Z]{4}[-_. ]?\d{3}[._]?\d{2}\b"#, options: .regularExpression) else { return nil }
        let matched = String(text[range]).uppercased()
        let letters = matched.filter(\.isLetter)
        let digits = matched.filter(\.isNumber)
        return letters.count == 4 && digits.count == 5 ? letters + "-" + digits : nil
    }

    /// Extracts BOOT/BOOT2 from ISO9660 SYSTEM.CNF; never scans or loads a whole ROM.
    /// Supports 2048-byte ISO and the data payloads in common 2352-byte PS1 BIN sectors.
    private static func discSerial(_ file: URL) -> String? {
        guard ["iso", "bin", "img", "mdf"].contains(file.pathExtension.lowercased()),
              let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        func read(_ offset: UInt64, _ count: Int) -> Data? {
            guard count > 0, count <= 256 * 1024 else { return nil }
            do { try handle.seek(toOffset: offset); return try handle.read(upToCount: count) } catch { return nil }
        }
        func uint32(_ data: Data, _ offset: Int) -> UInt32? {
            guard offset >= 0, data.count >= offset + 4 else { return nil }
            return (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[offset + $1]) << (8 * $1) }
        }
        for (sectorSize, payloadOffset) in [(2048, 0), (2352, 24), (2352, 16)] {
            guard let pvd = read(UInt64(16 * sectorSize + payloadOffset), 2048), pvd.count == 2048,
                  pvd[0] == 1, String(data: pvd[1..<6], encoding: .ascii) == "CD001",
                  let extent = uint32(pvd, 158), let rootSize = uint32(pvd, 166), rootSize > 0, rootSize <= 128 * 1024 else { continue }
            func sectors(_ block: UInt32, _ count: Int) -> Data? {
                guard count > 0, count <= 128 * 1024 else { return nil }
                var result = Data()
                for index in 0..<((count + 2047) / 2048) {
                    let length = min(2048, count - result.count)
                    guard let data = read((UInt64(block) + UInt64(index)) * UInt64(sectorSize) + UInt64(payloadOffset), length), data.count == length else { return nil }
                    result.append(data)
                }
                return result
            }
            guard let directory = sectors(extent, Int(rootSize)) else { continue }
            var offset = 0
            while offset < directory.count {
                let length = Int(directory[offset])
                if length == 0 { offset = ((offset / 2048) + 1) * 2048; continue }
                guard length >= 34, offset + length <= directory.count else { break }
                let nameLength = Int(directory[offset + 32])
                if nameLength > 0, nameLength <= length - 33,
                   let name = String(data: directory[(offset + 33)..<(offset + 33 + nameLength)], encoding: .ascii),
                   name.uppercased().split(separator: ";").first == "SYSTEM.CNF",
                   let block = uint32(directory, offset + 2), let size = uint32(directory, offset + 10), size > 0, size <= 64 * 1024,
                   let data = sectors(block, Int(size)), let system = String(data: data, encoding: .ascii) {
                    for line in system.components(separatedBy: .newlines) {
                        if line.range(of: #"(?i)^\s*BOOT2?\s*="#, options: .regularExpression) != nil,
                           let serial = serialIn(line) { return serial }
                    }
                }
                offset += length
            }
        }
        return nil
    }
}
