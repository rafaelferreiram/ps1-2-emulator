import Foundation

@main
@MainActor
struct CatalogOrganizationTests {
    static var assertions = 0
    static func require(_ condition: @autoclosure () -> Bool, _ description: String) {
        assertions += 1
        guard condition() else { fatalError("FAIL: \(description)") }
    }

    static func entry(_ title: String, _ id: String = "") -> CatalogEntry {
        CatalogEntry(id: id.isEmpty ? title : id, title: title)
    }

    static func main() {
        let games = [entry("Zulu"), entry("Alpha"), entry("Muse")]
        let ascending = CatalogGrouping.sections(entries: games, layout: CatalogLayout())
        require(ascending.count == 1 && !ascending[0].collapsible, "without folders the catalog is one open list")
        require(ascending[0].games.map(\.title) == ["Alpha", "Muse", "Zulu"], "default order is A to Z")
        var reverse = CatalogLayout()
        reverse.ascending = false
        require(CatalogGrouping.sections(entries: games, layout: reverse)[0].games.map(\.title) == ["Zulu", "Muse", "Alpha"],
                "Z to A reverses titles")

        let suite = "local.ps12.tests.catalog-organization.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let organizer = CatalogOrganizer(defaults: defaults)
        require(organizer.createFolder(named: "   ", console: "ps2") == nil, "blank folder name is rejected")
        require(organizer.createFolder(named: "Futebol", console: "ps2") != nil, "folder is created")
        require(organizer.createFolder(named: "futebol", console: "ps2") == nil, "folder names stay unique")
        require(organizer.createFolder(named: "Luta", console: "ps2") != nil, "second folder is created")
        let folders = organizer.layout(for: "ps2").folders
        require(folders.map(\.name) == ["Futebol", "Luta"], "folders keep creation order")
        organizer.place(gameID: "/games/FIFA.iso", in: folders[0].id, console: "ps2")
        organizer.place(gameID: "/games/GTA.iso", in: folders[1].id, console: "ps2")
        organizer.place(gameID: "/games/FIFA.iso", in: folders[1].id, console: "ps2")
        let moved = organizer.layout(for: "ps2")
        require(moved.folders[0].gameIDs.isEmpty && Set(moved.folders[1].gameIDs) == ["/games/FIFA.iso", "/games/GTA.iso"],
                "a game lives in only one folder")

        let entries = [
            entry("FIFA 08", "/games/FIFA.iso"),
            entry("GTA", "/games/GTA.iso"),
            entry("Cars", "/games/Cars.iso"),
            entry("Antigo", "/games/missing.iso")
        ]
        let grouped = CatalogGrouping.sections(entries: entries.filter { $0.id != "/games/missing.iso" }, layout: moved)
        require(grouped.map(\.title) == ["Futebol", "Luta", "Library"], "folders come first and loose games stay in Library")
        require(grouped[1].games.map(\.title) == ["FIFA 08", "GTA"], "games inside a folder stay A to Z")
        require(grouped[2].games.map(\.title) == ["Cars"], "a game without a folder stays visible")
        require(!grouped.flatMap(\.games).map(\.id).contains("/games/missing.iso"), "a folder cannot invent a missing game")

        let catalogEntries = entries.filter { $0.id != "/games/missing.iso" }
        organizer.toggleCollapsed(folders[1].id.uuidString, console: "ps2")
        let hidden = CatalogGrouping.sections(entries: catalogEntries, layout: organizer.layout(for: "ps2"))
        require(hidden[1].collapsed && CatalogGrouping.visible(hidden).map(\.title) == ["Cars"],
                "minimizing a folder hides its games and keeps the others")
        let board = CatalogBoard(sections: hidden)
        require(board.move(from: "/games/Cars.iso", columns: 3, horizontal: -1, vertical: 0) == nil,
                "navigation does not enter a minimized folder")
        organizer.toggleCollapsed(folders[1].id.uuidString, console: "ps2")

        let open = CatalogBoard(sections: CatalogGrouping.sections(entries: entries.filter { $0.id != "/games/missing.iso" },
                                                                   layout: organizer.layout(for: "ps2")))
        require(open.move(from: "/games/GTA.iso", columns: 2, horizontal: 1, vertical: 0) == "/games/Cars.iso",
                "the last game of a folder continues into the next open folder")
        require(open.move(from: "/games/Cars.iso", columns: 2, horizontal: 0, vertical: -1) == "/games/FIFA.iso",
                "moving up keeps the same column in the folder above")
        var stale = CatalogLayout()
        stale.folders = [CatalogFolder(id: UUID(), name: "Luta", gameIDs: ["/gone", "/games/GTA.iso"])]
        let shown = CatalogGrouping.sections(entries: [entry("GTA", "/games/GTA.iso")], layout: stale)
        require(shown[0].games.map(\.id) == ["/games/GTA.iso"], "a folder ignores a game that is not in the catalog")

        require(organizer.renameFolder(folders[0].id, to: "Carros", console: "ps2"), "folder can be renamed")
        organizer.deleteFolder(folders[1].id, console: "ps2")
        let afterDelete = CatalogGrouping.sections(entries: entries.filter { $0.id != "/games/missing.iso" },
                                                   layout: organizer.layout(for: "ps2"))
        require(afterDelete.map(\.title) == ["Carros", "Library"], "deleting a folder keeps the games in Library")
        require(afterDelete[1].games.map(\.id).contains("/games/FIFA.iso"), "deleting a folder does not remove its games")

        let restored = CatalogOrganizer(defaults: defaults)
        require(restored.layout(for: "ps2").folders.map(\.name) == ["Carros"], "folders survive a relaunch")
        require(restored.layout(for: "ps1").folders.isEmpty && restored.layout(for: "ps1").ascending,
                "PS1 organization stays separate")
        print("PASS: \(assertions) catalog sort, folder and navigation assertions")
    }
}
