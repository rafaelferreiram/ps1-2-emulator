import AppKit
import Combine
import Darwin

struct EmulatorState: Equatable {
    var isRunning: Bool
    var pid: Int32?
    var launchedAt: Date?
    var gameTitle: String?
    var gamePath: String?
    var activityDescription: String

    static let off = EmulatorState(isRunning: false, pid: nil, launchedAt: nil,
                                   gameTitle: nil, gamePath: nil, activityDescription: "Desligado")
}

/// Reports the current app session and an image that the emulator actually has open.
/// It neither reads old logs nor infers a running game from a library selection.
/// A loaded disc may be paused: file descriptors alone cannot establish gameplay.
@MainActor
final class EmulatorMonitor: ObservableObject {
    @Published private(set) var states: [String: EmulatorState] = ["ps1": .off, "ps2": .off]

    private struct Target {
        let key: String
        let bundleID: String
        let library: String
    }

    private struct Session: Equatable {
        let pid: Int32
        let launchedAt: Date?
    }

    private struct Observation {
        let session: Session
        let identity: String
        let firstSeen: Date
    }

    private struct GameImage {
        let identity: String
        let path: String
        let title: String
        let priority: Int
    }

    private struct FileProbe {
        let available: Bool
        let paths: [String]
        var sizes: [String: Int64] = [:]
    }

    private var targets = [
        Target(key: "ps1", bundleID: "com.github.stenzek.duckstation",
               library: "/Volumes/Extreme SSD/Emulacao/PS1/Jogos"),
        Target(key: "ps2", bundleID: "net.pcsx2.pcsx2",
               library: "/Volumes/Extreme SSD/Emulacao/PS2/Jogos")
    ]
    private var observations: [String: Observation] = [:]

    init(libraries: [String: String] = [:]) {
        for (key, library) in libraries { setLibrary(library, for: key) }
    }

    func setLibrary(_ library: String, for key: String) {
        guard library.hasPrefix("/"), let index = targets.firstIndex(where: { $0.key == key }),
              targets[index].library != library else { return }
        targets[index] = Target(key: key, bundleID: targets[index].bundleID, library: library)
        observations.removeValue(forKey: key)
    }

    func refresh() {
        var next: [String: EmulatorState] = [:]
        for target in targets {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleID)
                .filter { !$0.isTerminated }
                .sorted {
                    if $0.isActive != $1.isActive { return $0.isActive }
                    return ($0.launchDate ?? .distantPast) > ($1.launchDate ?? .distantPast)
                }
            guard let app = apps.first else {
                next[target.key] = observedState(target: target, session: nil,
                                                probe: FileProbe(available: false, paths: []), now: Date())
                continue
            }

            let session = Session(pid: app.processIdentifier, launchedAt: app.launchDate)
            let probe = Self.openFiles(pid: session.pid)
            // A process may exit while its descriptors are being inspected.
            next[target.key] = observedState(target: target, session: app.isTerminated ? nil : session,
                                            probe: probe, now: Date())
        }
        if next != states { states = next }
    }

    /// Deterministic state transition, shared by actual observations and the test harness.
    private func observedState(target: Target, session: Session?, probe: FileProbe, now: Date) -> EmulatorState {
        guard let session else {
            observations.removeValue(forKey: target.key)
            return .off
        }
        var state = EmulatorState(isRunning: true, pid: session.pid, launchedAt: session.launchedAt,
                                  gameTitle: nil, gamePath: nil,
                                  activityDescription: probe.available ? "Emulador aberto · sem jogo detectado" : "Jogo não identificado")
        guard probe.available else {
            observations.removeValue(forKey: target.key)
            return state
        }
        let candidates = Self.gameImages(in: probe.paths, library: target.library)

        // A scanner can briefly open images while populating the library. Require
        // the same unambiguous disc on successive polls at least 0.75 s apart.
        // Never retain an old title once the image disappears or the PID changes.
        if candidates.count == 1, let game = candidates.first {
            if let previous = observations[target.key], previous.session == session,
               previous.identity == game.identity {
                if now.timeIntervalSince(previous.firstSeen) >= 0.75 {
                    state.gameTitle = game.title
                    state.gamePath = game.path
                    state.activityDescription = "Jogo carregado"
                } else {
                    state.activityDescription = "Verificando jogo…"
                }
            } else {
                observations[target.key] = Observation(session: session, identity: game.identity, firstSeen: now)
                state.activityDescription = "Verificando jogo…"
            }
        } else {
            observations.removeValue(forKey: target.key)
            if candidates.count > 1 {
                state.activityDescription = "Jogo não identificado · vários discos abertos"
            } else if Self.hasImageOutsideLibrary(in: probe, library: target.library) {
                // Do not expose or guess titles outside this configured library. The
                // conservative busy state also prevents an unsafe automatic disc swap.
                state.activityDescription = "Jogo não identificado · fora da biblioteca"
            }
        }
        return state
    }

    private static func openFiles(pid: Int32) -> FileProbe {
        let descriptorSize = MemoryLayout<proc_fdinfo>.stride
        let required = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard required > 0 else { return FileProbe(available: false, paths: []) }

        // Leave room for descriptors opened between the size and data queries.
        // The bound prevents an abnormal process from creating a large allocation.
        let capacity = min(Int(required) / descriptorSize + 64, 65_536)
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: capacity)
        let bytes = descriptors.withUnsafeMutableBytes { buffer in
            proc_pidinfo(pid, PROC_PIDLISTFDS, 0, buffer.baseAddress, Int32(buffer.count))
        }
        guard bytes > 0 else { return FileProbe(available: false, paths: []) }
        let count = min(Int(bytes) / descriptorSize, capacity)
        var paths = Set<String>()
        var sizes: [String: Int64] = [:]
        var denied = false
        for descriptor in descriptors.prefix(count) where descriptor.proc_fdtype == PROX_FDTYPE_VNODE {
            var info = vnode_fdinfowithpath()
            let result = proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDVNODEPATHINFO,
                                        &info, Int32(MemoryLayout<vnode_fdinfowithpath>.size))
            if result != MemoryLayout<vnode_fdinfowithpath>.size {
                // EBADF is an ordinary close between polls; EPERM/EACCES indicates
                // incomplete visibility and must not be described as an empty library.
                if errno == EPERM || errno == EACCES { denied = true }
                continue
            }
            let path = withUnsafeBytes(of: info.pvip.vip_path) { buffer in
                String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
            }
            if path.first == "/" {
                paths.insert(path)
                sizes[path] = info.pvip.vip_vi.vi_stat.vst_size
            }
        }
        let truncated = Int(bytes) >= capacity * descriptorSize
        return FileProbe(available: !denied && !truncated, paths: Array(paths), sizes: sizes)
    }

    private static let imagePriorities = ["chd": 0, "cue": 1, "iso": 2, "cso": 3, "zso": 4,
                                          "pbp": 5, "img": 6, "mdf": 7, "gz": 8, "bin": 9]
    private static let excludedDirectories: Set<String> = [
        "bios", "cache", "caches", "shadercache", "shader_cache", "saves", "savestates",
        "memcards", "memory cards", "covers", "thumbnails", "logs", "appdata", "application support"
    ]

    private static func isExcludedImage(_ url: URL, components: [Substring]) -> Bool {
        if components.contains(where: { $0.hasPrefix(".") || $0.lowercased().hasSuffix(".app") }) { return true }
        if components.dropLast().contains(where: { excludedDirectories.contains($0.lowercased()) }) { return true }
        return imageStem(url).range(of: #"(?i)^(?:scph(?:[-_ ]?\d+)?|ps[12][-_ ]?bios|bios)(?:\b|_)"#,
                                    options: .regularExpression) != nil
    }

    private static func imageStem(_ url: URL) -> String {
        let withoutOuterExtension = url.deletingPathExtension()
        if url.pathExtension.lowercased() == "gz",
           imagePriorities[withoutOuterExtension.pathExtension.lowercased()] != nil {
            return withoutOuterExtension.deletingPathExtension().lastPathComponent
        }
        return withoutOuterExtension.lastPathComponent
    }

    private static func hasImageOutsideLibrary(in probe: FileProbe, library: String) -> Bool {
        let root = URL(fileURLWithPath: library, isDirectory: true).standardizedFileURL.path + "/"
        for path in probe.paths {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            let normalizedPath = url.path
            let extensionName = url.pathExtension.lowercased()
            guard !normalizedPath.hasPrefix(root), imagePriorities[extensionName] != nil,
                  !isExcludedImage(url, components: normalizedPath.split(separator: "/")) else { continue }

            // Ignore operating-system and application data even if a cache happens
            // to share a disc-image extension. No filesystem traversal is needed.
            let systemRoots = ["/System/", "/Library/", "/Applications/", "/usr/", "/bin/", "/sbin/", "/dev/", "/opt/"]
            guard !systemRoots.contains(where: { normalizedPath.hasPrefix($0) }),
                  normalizedPath.range(of: #"^/Users/[^/]+/(?:Library|Applications)/"#, options: .regularExpression) == nil,
                  normalizedPath.range(of: #"^/Volumes/[^/]+/(?:System|Library|Applications)/"#, options: .regularExpression) == nil else { continue }

            if extensionName == "bin" {
                // Outside Jogos, .bin is ambiguous (BIOS, caches, memory cards…).
                // Typical PS1 data tracks are larger than BIOS dumps. Small external
                // homebrew BINs are intentionally not identified by this heuristic.
                guard normalizedPath.hasPrefix("/Users/") || normalizedPath.hasPrefix("/Volumes/"),
                      let size = probe.sizes[path], size >= 16 * 1024 * 1024 else { continue }
            }
            return true
        }
        return false
    }

    private static func gameImages(in paths: [String], library: String) -> [GameImage] {
        let root = URL(fileURLWithPath: library, isDirectory: true).standardizedFileURL.path + "/"
        var games: [String: GameImage] = [:]
        for path in paths {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard url.path.hasPrefix(root), let priority = imagePriorities[url.pathExtension.lowercased()] else { continue }
            let relative = String(url.path.dropFirst(root.count))
            let components = relative.split(separator: "/")
            guard !isExcludedImage(url, components: components) else { continue }
            var stem = imageStem(url)
            stem = stem.replacingOccurrences(of: #"(?i)\s*(?:\(|\[)track[\s_-]*\d+(?:\)|\])\s*$"#,
                                              with: "", options: .regularExpression)
            stem = stem.replacingOccurrences(of: #"(?i)[._ -]+track[._ -]*\d+$"#,
                                              with: "", options: .regularExpression)
            let identity = url.deletingLastPathComponent().path + "/" + stem.lowercased()
            var title = stem.replacingOccurrences(of: #"(?i)^(?:S[CL][A-Z]{2}|BETA)[-_. ]?\d{3}[._]?\d{2}[. _-]*"#,
                                                  with: "", options: .regularExpression)
            title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty { title = stem }
            let image = GameImage(identity: identity, path: url.path, title: title, priority: priority)
            if let existing = games[identity], existing.priority <= priority { continue }
            games[identity] = image
        }
        return games.values.sorted { $0.identity < $1.identity }
    }

    #if EMULATOR_MONITOR_TESTS
    // Test-only adapters. These symbols are absent from the shipped app.
    static func testImages(paths: [String], library: String) -> [(title: String, path: String)] {
        gameImages(in: paths, library: library).map { ($0.title, $0.path) }
    }

    func testObserve(key: String = "ps1", library: String, pid: Int32?, launchedAt: Date?,
                     paths: [String], sizes: [String: Int64] = [:], available: Bool = true, now: Date) -> EmulatorState {
        let session = pid.map { Session(pid: $0, launchedAt: launchedAt) }
        return observedState(target: Target(key: key, bundleID: "test", library: library), session: session,
                             probe: FileProbe(available: available, paths: paths, sizes: sizes), now: now)
    }
    #endif
}
