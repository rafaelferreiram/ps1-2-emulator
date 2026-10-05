import Foundation

@main
struct SessionLifecycleTests {
    static func main() {
        var assertions = 0
        func expect(_ value: Bool, _ label: String) {
            assertions += 1
            precondition(value, label)
        }
        let time = Date(timeIntervalSince1970: 1234)
        let record = OwnedGameSession(consoleKey: "ps2", pid: 123, launchedAt: time, gameID: "game",
                                      gameURL: URL(fileURLWithPath: "/Games/game.iso"), libraryRoot: URL(fileURLWithPath: "/Games"))
        expect(record.matches(pid: 123, launchedAt: time), "owns exact process")
        expect(!record.matches(pid: 124, launchedAt: time), "does not adopt another process")
        expect(!record.matches(pid: 123, launchedAt: time.addingTimeInterval(1)), "reused PID is not owned")
        expect(!record.matches(pid: 123, launchedAt: nil), "unknown launch date is not same known launch")
        let special = URL(fileURLWithPath: "/Games/-My game; ' test.iso")
        expect(EmulatorLaunchArguments.game(special) == ["-fullscreen", "-batch", "--", special.path], "file is one literal argument after --")
        let entries = (1...5).map { CatalogEntry(id: "g\($0)", title: "Game \($0)") }
        let sections = [
            CatalogSection(id: "empty", title: "Empty", games: [], collapsible: true, collapsed: true),
            CatalogSection(id: "open", title: "Open", games: entries, collapsible: true, collapsed: false),
            CatalogSection(id: "closed", title: "Closed", games: [CatalogEntry(id: "hidden", title: "Hidden")], collapsible: true, collapsed: true)
        ]
        let board = ConsoleCatalogNavigation(sections: sections, columns: 3)
        expect(board.first == "section:empty", "empty collapsed header focusable")
        expect(!board.contains("hidden"), "collapsed games excluded")
        expect(board.contains("section:closed"), "collapsed header included")
        expect(board.move(from: "section:empty", horizontal: 0, vertical: 1) == "section:open", "down crosses empty section")
        expect(board.move(from: "section:open", horizontal: 0, vertical: 1) == "g1", "down enters expanded games")
        expect(board.move(from: "g3", horizontal: 0, vertical: 1) == "g5", "last short row clamps column")
        expect(board.move(from: "g4", horizontal: 0, vertical: 1) == "section:closed", "down reaches closed folder")
        expect(board.move(from: "section:closed", horizontal: 0, vertical: -1) == "g4", "up enters previous grid")
        expect(board.move(from: "section:empty", horizontal: 0, vertical: -1) == nil, "above first row reaches toolbar")
        expect(ConsoleCatalogNavigation(sections: [], columns: 0).first == nil, "empty catalog safe")
        print("PASS: \(assertions) session identity, launch arguments and folder navigation assertions")
    }
}
