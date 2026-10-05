import Foundation
import Combine

enum LibraryFilter: String, Codable, CaseIterable, Identifiable {
    case all, favorites, recent
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "Todos"
        case .favorites: return "Favoritos"
        case .recent: return "Recentes"
        }
    }
    var next: LibraryFilter {
        switch self {
        case .all: return .favorites
        case .favorites: return .recent
        case .recent: return .all
        }
    }
}

enum LibraryDensity: String, Codable, CaseIterable {
    case comfortable, compact
    var title: String { self == .comfortable ? "Confortável" : "Compacta" }
}

/// Local browsing preferences, not emulator saves or evidence of play progress.
/// Libraries on different roots deliberately keep independent favorites/history.
struct PersonalLibraryState: Codable, Equatable {
    var favoriteIDs: Set<String> = []
    var lastLaunched: [String: Date] = [:]
    var selectedGameID: String?
    var selectedSectionID: String?
    var filter: LibraryFilter = .all
    var query = ""
    var density: LibraryDensity = .comfortable
}

@MainActor
final class PersonalLibrary: ObservableObject {
    @Published private(set) var states: [String: PersonalLibraryState]
    private let defaults: UserDefaults
    private static let storageKey = "PS12.PersonalLibrary.v1"
    private static let recentLimit = 200

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: PersonalLibraryState].self, from: data) {
            states = decoded.mapValues(Self.sanitized)
        } else {
            states = [:]
        }
    }

    func state(console: String, root: URL) -> PersonalLibraryState {
        guard let key = Self.scope(console: console, root: root) else { return PersonalLibraryState() }
        return states[key] ?? PersonalLibraryState()
    }

    func setFilter(_ filter: LibraryFilter, console: String, root: URL) {
        change(console: console, root: root) { $0.filter = filter }
    }

    func setQuery(_ query: String, console: String, root: URL) {
        change(console: console, root: root) { $0.query = Self.cleanedQuery(query) }
    }

    func setDensity(_ density: LibraryDensity, console: String, root: URL) {
        change(console: console, root: root) { $0.density = density }
    }

    func toggleFavorite(_ gameID: String, console: String, root: URL) {
        guard !gameID.isEmpty else { return }
        change(console: console, root: root) { value in
            if value.favoriteIDs.contains(gameID) { value.favoriteIDs.remove(gameID) }
            else { value.favoriteIDs.insert(gameID) }
        }
    }

    /// Call only after a successful request to open this game in its emulator.
    /// This does not mean the game finished booting or that a save state exists.
    func recordLaunch(_ gameID: String, at date: Date = Date(), console: String, root: URL) {
        guard !gameID.isEmpty, date.timeIntervalSinceReferenceDate.isFinite else { return }
        change(console: console, root: root) { value in
            value.lastLaunched[gameID] = date
            value.selectedGameID = gameID
            value.selectedSectionID = nil
        }
    }

    func rememberSelection(gameID: String?, sectionID: String? = nil, console: String, root: URL) {
        change(console: console, root: root) { value in
            value.selectedGameID = gameID?.isEmpty == false ? gameID : nil
            value.selectedSectionID = sectionID?.isEmpty == false ? sectionID : nil
        }
    }

    /// Preserves the caller's folder/A–Z order, except for the Recent view.
    /// Only provided catalog entries can appear: history never invents a game.
    func filteredEntries(_ entries: [CatalogEntry], console: String, root: URL) -> [CatalogEntry] {
        let preferences = state(console: console, root: root)
        let words = preferences.query.split(whereSeparator: \.isWhitespace).map(String.init)
        let filtered = entries.filter { entry in
            let matchesFilter: Bool
            switch preferences.filter {
            case .all: matchesFilter = true
            case .favorites: matchesFilter = preferences.favoriteIDs.contains(entry.id)
            case .recent: matchesFilter = preferences.lastLaunched[entry.id] != nil
            }
            return matchesFilter && words.allSatisfy {
                entry.title.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive], locale: .current) != nil
            }
        }
        guard preferences.filter == .recent else { return filtered }
        return filtered.sorted { lhs, rhs in
            let lhsDate = preferences.lastLaunched[lhs.id] ?? .distantPast
            let rhsDate = preferences.lastLaunched[rhs.id] ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            let comparison = lhs.title.localizedStandardCompare(rhs.title)
            return comparison == .orderedSame ? lhs.id < rhs.id : comparison == .orderedAscending
        }
    }

    private func change(console: String, root: URL, update: (inout PersonalLibraryState) -> Void) {
        guard let key = Self.scope(console: console, root: root) else { return }
        var value = states[key] ?? PersonalLibraryState()
        update(&value)
        value = Self.sanitized(value)
        guard value != states[key] else { return }
        var next = states
        next[key] = value
        guard let data = try? JSONEncoder().encode(next) else { return }
        states = next
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func scope(console: String, root: URL) -> String? {
        guard ["ps1", "ps2"].contains(console), root.isFileURL else { return nil }
        // Do not resolve symlinks or touch the disk: offline browsing must work.
        return console + "|" + root.standardizedFileURL.path
    }

    private static func cleanedQuery(_ query: String) -> String {
        String(String(query.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }).prefix(120))
    }

    private static func sanitized(_ state: PersonalLibraryState) -> PersonalLibraryState {
        var value = state
        value.favoriteIDs.remove("")
        value.query = cleanedQuery(value.query)
        let recent = value.lastLaunched.filter { !$0.key.isEmpty && $0.value.timeIntervalSinceReferenceDate.isFinite }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(recentLimit)
        value.lastLaunched = Dictionary(uniqueKeysWithValues: recent.map { ($0.key, $0.value) })
        return value
    }
}
