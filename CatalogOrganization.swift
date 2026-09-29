import Foundation
import Combine

struct CatalogEntry: Equatable, Identifiable {
    let id: String
    let title: String
}

struct CatalogFolder: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var gameIDs: [String]
}

struct CatalogLayout: Codable, Equatable {
    var ascending = true
    var folders: [CatalogFolder] = []
    var collapsed: Set<String> = []
}

struct CatalogSection: Identifiable, Equatable {
    let id: String
    let title: String
    let games: [CatalogEntry]
    let collapsible: Bool
    let collapsed: Bool

    var isLibrary: Bool { id == CatalogGrouping.libraryID }
}

enum CatalogNames {
    static func cleaned(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...24).contains(name.count) else { return nil }
        guard name.unicodeScalars.allSatisfy({ scalar in
            !CharacterSet.controlCharacters.contains(scalar) && scalar != "\u{202E}" && scalar != "\u{202D}"
        }) else { return nil }
        return name
    }
}

enum CatalogGrouping {
    static let libraryID = "library"

    static func sections(entries: [CatalogEntry], layout: CatalogLayout) -> [CatalogSection] {
        let ordered = entries.sorted { lhs, rhs in
            let comparison = lhs.title.localizedStandardCompare(rhs.title)
            if comparison == .orderedSame { return layout.ascending ? lhs.id < rhs.id : lhs.id > rhs.id }
            return layout.ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
        guard !layout.folders.isEmpty else {
            return [CatalogSection(id: libraryID, title: "Library", games: ordered, collapsible: false, collapsed: false)]
        }
        var used = Set<String>()
        var sections: [CatalogSection] = []
        for folder in layout.folders {
            let ids = Set(folder.gameIDs)
            let games = ordered.filter { ids.contains($0.id) && used.insert($0.id).inserted }
            sections.append(CatalogSection(id: folder.id.uuidString, title: folder.name, games: games,
                                            collapsible: true, collapsed: layout.collapsed.contains(folder.id.uuidString)))
        }
        let rest = ordered.filter { !used.contains($0.id) }
        if !rest.isEmpty {
            sections.append(CatalogSection(id: libraryID, title: "Library", games: rest, collapsible: true,
                                            collapsed: layout.collapsed.contains(libraryID)))
        }
        return sections
    }

    static func visible(_ sections: [CatalogSection]) -> [CatalogEntry] {
        sections.filter { !$0.collapsed }.flatMap(\.games)
    }
}

/// Movement across the catalog grids. Collapsed and empty folders are not cells.
struct CatalogBoard: Equatable {
    let rows: [[String]]

    init(sections: [CatalogSection]) {
        rows = sections.compactMap { section in
            let ids = section.collapsed ? [] : section.games.map(\.id)
            return ids.isEmpty ? nil : ids
        }
    }

    func contains(_ id: String) -> Bool { locate(id) != nil }

    func move(from id: String, columns: Int, horizontal: Int, vertical: Int) -> String? {
        guard columns > 0, horizontal == 0 || vertical == 0, let place = locate(id) else { return nil }
        if horizontal != 0 {
            let next = place.index + horizontal
            if rows[place.section].indices.contains(next) { return rows[place.section][next] }
            guard let neighbor = neighbor(of: place.section, step: horizontal) else { return nil }
            return horizontal > 0 ? rows[neighbor].first : rows[neighbor].last
        }
        guard vertical != 0 else { return nil }
        let column = place.index % columns
        let row = place.index / columns
        let count = rows[place.section].count
        let rowCount = (count + columns - 1) / columns
        let targetRow = row + vertical
        if (0..<rowCount).contains(targetRow) {
            return rows[place.section][min(targetRow * columns + column, count - 1)]
        }
        guard let neighbor = neighbor(of: place.section, step: vertical) else { return nil }
        let neighborCount = rows[neighbor].count
        if vertical > 0 { return rows[neighbor][min(column, neighborCount - 1)] }
        let lastRow = (neighborCount - 1) / columns
        return rows[neighbor][min(lastRow * columns + column, neighborCount - 1)]
    }

    private func locate(_ id: String) -> (section: Int, index: Int)? {
        for (section, row) in rows.enumerated() {
            if let index = row.firstIndex(of: id) { return (section, index) }
        }
        return nil
    }

    private func neighbor(of section: Int, step: Int) -> Int? {
        var cursor = section + step
        while rows.indices.contains(cursor) {
            if !rows[cursor].isEmpty { return cursor }
            cursor += step
        }
        return nil
    }
}

@MainActor
final class CatalogOrganizer: ObservableObject {
    @Published private(set) var layouts: [String: CatalogLayout]
    private let defaults: UserDefaults
    private static let consoles = ["ps1", "ps2"]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var restored: [String: CatalogLayout] = [:]
        for console in Self.consoles {
            restored[console] = Self.restore(defaults.data(forKey: Self.key(console))) ?? CatalogLayout()
        }
        layouts = restored
    }

    func layout(for console: String) -> CatalogLayout {
        layouts[console] ?? CatalogLayout()
    }

    func setAscending(_ ascending: Bool, console: String) {
        guard Self.consoles.contains(console) else { return }
        var layout = layout(for: console)
        guard layout.ascending != ascending else { return }
        layout.ascending = ascending
        store(layout, console: console)
    }

    func toggleCollapsed(_ sectionID: String, console: String) {
        guard Self.consoles.contains(console) else { return }
        var layout = layout(for: console)
        let known = sectionID == CatalogGrouping.libraryID || layout.folders.contains { $0.id.uuidString == sectionID }
        guard known, !layout.folders.isEmpty else { return }
        if layout.collapsed.contains(sectionID) { layout.collapsed.remove(sectionID) }
        else { layout.collapsed.insert(sectionID) }
        store(layout, console: console)
    }

    @discardableResult
    func createFolder(named raw: String, console: String) -> CatalogFolder? {
        guard Self.consoles.contains(console), let name = CatalogNames.cleaned(raw) else { return nil }
        var layout = layout(for: console)
        guard layout.folders.count < 20, !layout.folders.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return nil }
        let folder = CatalogFolder(id: UUID(), name: name, gameIDs: [])
        layout.folders.append(folder)
        store(layout, console: console)
        return folder
    }

    @discardableResult
    func renameFolder(_ id: UUID, to raw: String, console: String) -> Bool {
        guard Self.consoles.contains(console), let name = CatalogNames.cleaned(raw) else { return false }
        var layout = layout(for: console)
        guard let index = layout.folders.firstIndex(where: { $0.id == id }) else { return false }
        if layout.folders.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) { return false }
        layout.folders[index].name = name
        store(layout, console: console)
        return true
    }

    func deleteFolder(_ id: UUID, console: String) {
        guard Self.consoles.contains(console) else { return }
        var layout = layout(for: console)
        layout.folders.removeAll { $0.id == id }
        layout.collapsed.remove(id.uuidString)
        if layout.folders.isEmpty { layout.collapsed.removeAll() }
        store(layout, console: console)
    }

    /// A game stays in one folder. `nil` returns it to Library. Files are not moved.
    func place(gameID: String, in folderID: UUID?, console: String) {
        guard Self.consoles.contains(console), !gameID.isEmpty, !gameID.contains("\n") else { return }
        var layout = layout(for: console)
        for index in layout.folders.indices {
            layout.folders[index].gameIDs.removeAll { $0 == gameID }
        }
        if let folderID, let index = layout.folders.firstIndex(where: { $0.id == folderID }) {
            layout.folders[index].gameIDs.append(gameID)
        }
        store(layout, console: console)
    }

    private func store(_ layout: CatalogLayout, console: String) {
        layouts[console] = layout
        guard let data = try? JSONEncoder().encode(layout) else { return }
        defaults.set(data, forKey: Self.key(console))
    }

    private static func key(_ console: String) -> String { "PS12.CatalogOrganization.\(console)" }

    private static func restore(_ data: Data?) -> CatalogLayout? {
        guard let data, let layout = try? JSONDecoder().decode(CatalogLayout.self, from: data) else { return nil }
        guard layout.folders.count <= 20, layout.folders.allSatisfy({ CatalogNames.cleaned($0.name) != nil }) else { return nil }
        let ids = layout.folders.map(\.id)
        guard Set(ids).count == ids.count else { return nil }
        return layout
    }
}
