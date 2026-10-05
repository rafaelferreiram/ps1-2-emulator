import Foundation

/// Only a process started for a game by this launcher is eligible for automatic
/// return. PID and launch date together prevent adopting an unrelated restart.
struct OwnedGameSession: Equatable {
    let consoleKey: String
    let pid: Int32
    let launchedAt: Date?
    let gameID: String
    let gameURL: URL
    let libraryRoot: URL

    func matches(pid: Int32, launchedAt: Date?) -> Bool {
        self.pid == pid && self.launchedAt == launchedAt
    }
}

enum EmulatorLaunchArguments {
    /// Both upstream Qt frontends support these flags. Batch exits normally
    /// after the game shuts down; it never bypasses the emulator's save prompts.
    static func game(_ url: URL) -> [String] { ["-fullscreen", "-batch", "--", url.path] }
}

/// Every collapsible header is a navigation row, even when empty or collapsed.
struct ConsoleCatalogNavigation {
    static let headerPrefix = "section:"
    let rows: [[String]]

    init(sections: [CatalogSection], columns: Int) {
        let count = max(1, columns)
        rows = sections.flatMap { section -> [[String]] in
            var result = section.collapsible ? [[Self.headerPrefix + section.id]] : []
            if !section.collapsed {
                let ids = section.games.map(\.id)
                for start in stride(from: 0, to: ids.count, by: count) {
                    result.append(Array(ids[start..<min(start + count, ids.count)]))
                }
            }
            return result
        }
    }
    var first: String? { rows.first?.first }
    func contains(_ id: String) -> Bool { rows.contains { $0.contains(id) } }
    func move(from id: String, horizontal: Int, vertical: Int) -> String? {
        guard let row = rows.firstIndex(where: { $0.contains(id) }),
              let column = rows[row].firstIndex(of: id) else { return first }
        if vertical != 0 {
            let next = row + vertical
            guard rows.indices.contains(next) else { return nil }
            return rows[next][min(column, rows[next].count - 1)]
        }
        guard horizontal != 0 else { return id }
        let next = column + horizontal
        if rows[row].indices.contains(next) { return rows[row][next] }
        let adjacent = row + horizontal
        guard rows.indices.contains(adjacent) else { return nil }
        return horizontal > 0 ? rows[adjacent].first : rows[adjacent].last
    }
}
