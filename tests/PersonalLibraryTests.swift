import Foundation

@main
@MainActor
struct PersonalLibraryTests {
    static var assertions = 0
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        guard condition() else { fatalError("FAIL: \(message)") }
    }

    static func main() {
        let suite = "local.ps12.tests.personal-library.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = URL(fileURLWithPath: "/Volumes/Offline SSD/Jogos/PS1", isDirectory: true)
        let other = URL(fileURLWithPath: "/Volumes/Other/Jogos/PS1", isDirectory: true)
        let library = PersonalLibrary(defaults: defaults)
        let entries = [CatalogEntry(id: "a", title: "Futebol Clássico"),
                       CatalogEntry(id: "b", title: "Space Jam"),
                       CatalogEntry(id: "c", title: "Tarzan")]
        require(library.state(console: "ps1", root: root) == PersonalLibraryState(), "new library has useful defaults")
        library.toggleFavorite("b", console: "ps1", root: root)
        library.toggleFavorite("missing", console: "ps1", root: root)
        library.setFilter(.favorites, console: "ps1", root: root)
        require(library.filteredEntries(entries, console: "ps1", root: root).map(\.id) == ["b"], "favorites never invent missing entries")
        library.toggleFavorite("b", console: "ps1", root: root)
        require(library.filteredEntries(entries, console: "ps1", root: root).isEmpty, "favorite toggles off")
        require(library.state(console: "ps2", root: root).favoriteIDs.isEmpty, "consoles are isolated")
        require(library.state(console: "ps1", root: other).favoriteIDs.isEmpty, "roots are isolated")
        library.setFilter(.all, console: "ps1", root: root)
        library.setQuery("CLASSICO futebol", console: "ps1", root: root)
        require(library.filteredEntries(entries, console: "ps1", root: root).map(\.id) == ["a"], "search ignores accents/case and matches all terms")
        library.setQuery("no match", console: "ps1", root: root)
        require(library.filteredEntries(entries, console: "ps1", root: root).isEmpty, "search can have no results")
        library.setQuery("", console: "ps1", root: root)
        require(library.filteredEntries(Array(entries.reversed()), console: "ps1", root: root).map(\.id) == ["c", "b", "a"], "all view preserves incoming order")
        library.recordLaunch("a", at: Date(timeIntervalSince1970: 100), console: "ps1", root: root)
        library.recordLaunch("b", at: Date(timeIntervalSince1970: 200), console: "ps1", root: root)
        library.recordLaunch("a", at: Date(timeIntervalSince1970: 300), console: "ps1", root: root)
        library.recordLaunch("missing", at: Date(timeIntervalSince1970: 400), console: "ps1", root: root)
        library.setFilter(.recent, console: "ps1", root: root)
        require(library.filteredEntries(entries, console: "ps1", root: root).map(\.id) == ["a", "b"], "recent uses latest launch, deduplicates and excludes missing games")
        library.setDensity(.compact, console: "ps1", root: root)
        library.rememberSelection(gameID: "b", sectionID: "folder-1", console: "ps1", root: root)
        let restored = PersonalLibrary(defaults: defaults)
        require(restored.state(console: "ps1", root: root) == library.state(console: "ps1", root: root), "favorites/history/selection/query/filter/density survive relaunch")
        require(restored.state(console: "ps1", root: root).selectedSectionID == "folder-1", "header selection is persisted")
        let equivalentRoot = root.appendingPathComponent("unused/..", isDirectory: true)
        require(restored.state(console: "ps1", root: equivalentRoot) == restored.state(console: "ps1", root: root), "standardized equivalent roots share state without disk access")
        restored.setQuery(String(repeating: "x", count: 300) + "\u{0}", console: "ps1", root: root)
        require(restored.state(console: "ps1", root: root).query.count == 120, "query has a persistence limit and no controls")
        restored.rememberSelection(gameID: nil, console: "ps1", root: root)
        require(restored.state(console: "ps1", root: root).selectedGameID == nil && restored.state(console: "ps1", root: root).selectedSectionID == nil, "selection can be cleared")
        restored.toggleFavorite("x", console: "ps3", root: root)
        restored.toggleFavorite("x", console: "ps1", root: URL(string: "https://example.com/games")!)
        require(restored.state(console: "ps3", root: root) == PersonalLibraryState(), "unknown consoles are ignored")
        for index in 0..<205 {
            restored.recordLaunch("game-\(index)", at: Date(timeIntervalSince1970: Double(1000 + index)), console: "ps2", root: root)
        }
        let history = restored.state(console: "ps2", root: root).lastLaunched
        require(history.count == 200 && history["game-0"] == nil && history["game-204"] != nil, "recents remain bounded to the newest 200 launches")
        defaults.set(Data("broken".utf8), forKey: "PS12.PersonalLibrary.v1")
        require(PersonalLibrary(defaults: defaults).states.isEmpty, "corrupted preferences fall back safely")
        print("PASS: \(assertions) personal library assertions")
    }
}
