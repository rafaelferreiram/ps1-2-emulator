import AppKit
import SwiftUI

@main
@MainActor
struct LauncherPreviewTests {
    static var assertions = 0

    static func require(_ condition: @autoclosure () -> Bool, _ description: String) {
        assertions += 1
        guard condition() else { fatalError("FAIL: \(description)") }
    }

    static func main() async throws {
        // Initialize AppKit without running the app delegate, showing a window,
        // or invoking any emulator-launching action.
        _ = NSApplication.shared
        for selected in [false, true] {
            let renderer = ImageRenderer(content: PlayerOneIndicator(selected: selected))
            renderer.scale = 2
            guard let image = renderer.cgImage else { fatalError("Could not render P1 indicator") }
            require(image.width == 64 && image.height == 48, "P1 always reserves the same compact slot")
            let bitmap = NSBitmapImageRep(cgImage: image)
            var opaquePixels = 0
            for x in 0..<bitmap.pixelsWide {
                for y in 0..<bitmap.pixelsHigh {
                    if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 { opaquePixels += 1 }
                }
            }
            require(selected ? opaquePixels > 100 : opaquePixels == 0, "P1 is visible only for the preselected console")
        }
        let suite = "local.ps12.tests.launcher.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = LauncherModel(librarySettings: GameLibrarySettings(defaults: defaults), startServices: false)
        require(model.selected == .ps2, "PS2 is initially preselected")
        require(model.previewConsole == nil, "boot hides the preview")
        model.finishBoot()
        require(model.previewConsole == .ps2, "default selection previews without mouse hover")

        // Keyboard arrows and controller navigation call these same methods.
        model.move(-1)
        require(model.selected == .ps1 && model.previewConsole == .ps1, "horizontal navigation changes preview to PS1")
        model.move(1)
        require(model.selected == .ps2 && model.previewConsole == .ps2, "horizontal navigation changes preview to PS2")
        model.moveVertical(-1)
        require(model.previewConsole == .ps1, "vertical navigation previews PS1")
        model.moveVertical(1)
        require(model.previewConsole == .ps2, "vertical navigation previews PS2")

        model.setConsoleHover(.ps1, inside: true)
        require(model.selected == .ps1 && model.previewConsole == .ps1, "mouse entry selects and previews PS1")
        model.setConsoleHover(.ps1, inside: false)
        require(model.selected == .ps1 && model.previewConsole == .ps1, "mouse exit preserves PS1 preview")
        model.setConsoleHover(.ps2, inside: true)
        model.setConsoleHover(.ps1, inside: false)
        require(model.selected == .ps2 && model.previewConsole == .ps2, "late exit of previous option cannot clear new preview")
        model.setConsoleHover(.ps2, inside: false)
        require(model.previewConsole == .ps2, "mouse exit preserves PS2 preview")
        require(model.launching == nil && model.launchID == nil, "selection and hover never initiate emulator launch")

        // A selection made from the keyboard/controller remains authoritative
        // even when the pointer has not emitted a hover-exit event yet.
        model.setConsoleHover(.ps1, inside: true)
        model.move(1)
        require(model.previewConsole == .ps2, "navigation overrides stationary pointer selection")
        model.setConsoleHover(.ps1, inside: false)
        require(model.previewConsole == .ps2, "subsequent mouse exit does not undo navigation")

        model.isForeground = false
        require(model.previewConsole == nil, "background or minimized app hides preview")
        model.setConsoleHover(.ps1, inside: true)
        require(model.selected == .ps2, "background hover cannot change selection")
        model.isForeground = true
        require(model.previewConsole == .ps2, "returning to foreground restores selected preview without hover")

        model.booting = true
        require(model.previewConsole == nil, "boot guard hides selected preview")
        model.setConsoleHover(.ps1, inside: true)
        require(model.selected == .ps2, "boot ignores hover selection")
        model.finishBoot()
        require(model.previewConsole == .ps2, "finishing boot restores selection preview")

        // Assign overlay state directly: this avoids scanning external games
        // or calling the actual emulator startup/termination paths.
        model.catalogConsole = .ps2
        require(model.previewConsole == nil, "catalog hides menu preview")
        model.setConsoleHover(.ps1, inside: true)
        require(model.selected == .ps2, "catalog ignores menu hover")
        model.back()
        require(model.catalogConsole == nil && model.previewConsole == .ps2, "leaving catalog restores selected preview")

        model.launching = .ps2
        require(model.previewConsole == nil, "startup overlay hides decorative preview")
        model.setConsoleHover(.ps1, inside: true)
        model.move(-1)
        require(model.selected == .ps2, "startup ignores hover and navigation")
        model.cancelLaunch()
        require(model.launching == nil && model.previewConsole == .ps2, "canceling startup restores selected preview")

        model.errorMessage = "Test-only error"
        require(model.previewConsole == nil, "error hides decorative preview")
        model.setConsoleHover(.ps1, inside: true)
        model.move(-1)
        require(model.selected == .ps2, "error ignores hover and navigation")
        model.errorMessage = nil
        require(model.previewConsole == .ps2, "dismissing error restores selected preview")

        model.select(.ps1)
        require(model.previewConsole == .ps1, "direct preselection updates preview without hover")
        model.refreshSessions()
        require(model.previewConsole == .ps1, "session polling does not change preview selection")
        require(model.launching == nil && model.launchID == nil, "all model preview checks leave emulators unlaunched")
        // Launch validation touches only the requested fixture, never starts an
        // emulator and never enumerates or rebuilds a catalog.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PS12-launch-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = root.appendingPathComponent("Games")
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let disc = library.appendingPathComponent("Game.iso")
        try Data([0x1]).write(to: disc)
        require(GameLaunchCheck.isAvailable(disc, library: library), "selected readable game may launch")
        let missing = library.appendingPathComponent("Removed.iso")
        require(!GameLaunchCheck.isAvailable(missing, library: library), "missing cached game cannot launch")
        let empty = library.appendingPathComponent("Empty.iso")
        try Data().write(to: empty)
        require(!GameLaunchCheck.isAvailable(empty, library: library), "empty game cannot launch")
        require(!GameLaunchCheck.isAvailable(library, library: library), "a folder is not a playable image")
        require(!GameLaunchCheck.isAvailable(URL(string: "https://example.com/Game.iso")!, library: library), "remote URL cannot launch")
        let outside = root.appendingPathComponent("Outside.iso")
        try Data([0x1]).write(to: outside)
        require(!GameLaunchCheck.isAvailable(outside, library: library), "out-of-library path cannot launch")
        let escape = library.appendingPathComponent("Escape.iso")
        try FileManager.default.createSymbolicLink(at: escape, withDestinationURL: outside)
        require(!GameLaunchCheck.isAvailable(escape, library: library), "symlink escaping the library cannot launch")
        try FileManager.default.removeItem(at: disc)
        require(!GameLaunchCheck.isAvailable(disc, library: library), "removal after catalog caching is caught on launch")
        var connected = false
        let offline = LauncherModel(librarySettings: GameLibrarySettings(defaults: defaults), storageProbe: { connected }, startServices: false)
        offline.finishBoot()
        require(!offline.storageMounted, "offline startup does not require the SSD")
        for console in Console.allCases {
            let absent = offline.gameFolder(for: console).appendingPathComponent("Offline-fixture-does-not-exist.iso")
            let game = CatalogGame(id: absent.path, consoleKey: console.rawValue, title: "Test game", fileURL: absent, coverURL: nil)
            offline.catalogConsole = console
            offline.launchGame(game)
            require(offline.storageNotice == StorageNotice(gameTitle: game.title, consoleName: console.badge), "missing SSD shows the console-styled notice")
            offline.reloadCatalog()
            require(offline.storageNotice != nil && !offline.catalog.loading.contains(console.rawValue),
                    "storage notice blocks catalog reload")
            require(offline.errorMessage == nil && offline.launching == nil && offline.launchID == nil, "offline play never starts an emulator or native error")
            let selected = offline.selected
            offline.select(selected == .ps1 ? .ps2 : .ps1)
            offline.move(1)
            offline.showCatalog()
            offline.launch(console)
            require(offline.selected == selected && offline.launching == nil, "dialog blocks underlying menu and emulator actions")
            offline.confirm()
            require(offline.storageNotice == nil && offline.catalogConsole == console, "X or Enter returns to the existing catalog")
            offline.launchGame(game)
            offline.back()
            require(offline.storageNotice == nil && offline.catalogConsole == console, "Circle or Escape closes only the notice")
            offline.launchGame(game)
            connected = true
            offline.refreshStorage()
            require(offline.storageMounted && offline.storageNotice != nil && offline.launching == nil, "reconnecting never auto-launches the game")
            offline.dismissStorageNotice()
            offline.launchGame(game)
            require(offline.storageNotice == nil && offline.errorMessage != nil && offline.launching == nil,
                    "connected SSD with missing game shows file error, not disconnected notice")
            offline.errorMessage = nil
            connected = false
        }
        // Exercise the production integration with private preferences/caches.
        // None of these actions launches an emulator or scans the real SSD.
        let settings = GameLibrarySettings(defaults: defaults)
        let cache = CatalogCache(directory: root.appendingPathComponent("Cache"))
        let catalog = GameCatalog(cache: cache, coverCache: CoverImageCache(directory: root.appendingPathComponent("Covers")))
        let configurable = LauncherModel(catalog: catalog, librarySettings: settings, startServices: false)
        configurable.finishBoot()
        configurable.catalogConsole = .ps2
        configurable.showLibrarySettings()
        require(configurable.showingLibrarySettings && configurable.settingsConsole == .ps2,
                "settings opens for the current catalog console")
        require(configurable.previewConsole == nil, "settings pauses the decorative preview")
        configurable.moveVertical(-1)
        require(configurable.settingsConsole == .ps1 && configurable.selected == .ps2,
                "settings navigation changes only the folder card")
        configurable.select(.ps1)
        configurable.setConsoleHover(.ps1, inside: true)
        configurable.showCatalog()
        configurable.launch(.ps1)
        require(configurable.selected == .ps2 && configurable.catalogConsole == .ps2 && configurable.launching == nil,
                "settings blocks underlying menu, catalog and launch actions")
        var requested: [Console] = []
        configurable.chooseLibraryFolder = { requested.append($0) }
        configurable.confirm()
        require(requested == [.ps1], "confirm requests the selected console folder, never a game")
        configurable.choosingLibraryFolder = true
        configurable.move(1)
        configurable.confirm()
        configurable.back()
        require(configurable.settingsConsole == .ps1 && requested.count == 1 && configurable.showingLibrarySettings,
                "native picker suspends background input and dismissal")
        configurable.choosingLibraryFolder = false
        configurable.back()
        require(!configurable.showingLibrarySettings && configurable.catalogConsole == .ps2,
                "back closes only settings and preserves the catalog")
        let oldPS1 = configurable.gameFolder(for: .ps1)
        let oldPS2 = configurable.gameFolder(for: .ps2)
        configurable.gameSelection = ["ps1": "previous-selection", "ps2": "untouched-selection"]
        configurable.setGameFolder(root.appendingPathComponent("DoesNotExist"), for: .ps1)
        require(configurable.librarySettingsError != nil && configurable.gameFolder(for: .ps1) == oldPS1,
                "invalid folder reports an inline error without changing preferences")
        // A directory containing only a zero-byte image and an escaping symlink
        // is deliberately not launched; it is used solely as a scan fixture.
        configurable.setGameFolder(library, for: .ps1)
        let chosen = library.resolvingSymlinksInPath().standardizedFileURL
        require(configurable.gameFolder(for: .ps1) == chosen && catalog.source(for: "ps1")?.root == chosen,
                "confirmed folder updates both persistence and catalog source")
        require(configurable.gameFolder(for: .ps2) == oldPS2 && catalog.source(for: "ps2")?.root == oldPS2,
                "PS1 selection leaves PS2 source unchanged")
        require(configurable.gameSelection["ps1"] == nil && configurable.gameSelection["ps2"] == "untouched-selection",
                "selection is cleared only for the changed library")
        require(configurable.isStorageAvailable(for: .ps1), "local library is not gated by external SSD availability")
        require(GameLibrarySettings(defaults: defaults).folder(for: "ps1") == chosen,
                "chosen folder survives settings reconstruction")
        for _ in 0..<500 where catalog.loading.contains("ps1") {
            try await Task.sleep(for: .milliseconds(10))
        }
        require(!catalog.loading.contains("ps1"), "explicit selection completes a full load")
        let scans = await cache.statistics().scans
        require(scans == 1, "only the selected console is scanned once")
        configurable.setGameFolder(library, for: .ps1)
        require(!catalog.loading.contains("ps1"), "selecting the identical folder does not rescan")
        configurable.showLibrarySettings()
        configurable.reloadCatalog()
        require(configurable.showingLibrarySettings && !catalog.loading.contains("ps1"), "settings block catalog reload")
        configurable.dismissLibrarySettings()
        configurable.catalogConsole = nil
        configurable.selected = .ps1
        configurable.errorMessage = "busy"
        configurable.reloadCatalog()
        require(configurable.catalogConsole == nil && configurable.errorMessage == "busy", "an error blocks catalog reload")
        configurable.errorMessage = nil
        configurable.reloadCatalog()
        require(configurable.catalogConsole == .ps1 && catalog.loading.contains("ps1") && configurable.launching == nil,
                "reload scans the selected console without launching an emulator")
        configurable.reloadCatalog()
        for _ in 0..<500 where catalog.loading.contains("ps1") {
            try await Task.sleep(for: .milliseconds(10))
        }
        require(!catalog.loading.contains("ps1"), "catalog reload finishes")
        let reloaded = await cache.statistics().scans
        require(reloaded == scans + 1, "a second reload during the scan does not stack another scan")
        try Data("later".utf8).write(to: library.appendingPathComponent("Added Later.iso"))
        configurable.back()
        require(configurable.catalogConsole == nil, "back returns to the console menu before reopening")
        configurable.selected = .ps1
        configurable.showCatalog()
        require(configurable.catalogConsole == .ps1 && !catalog.loading.contains("ps1"),
                "rapid catalog reopen reuses a fresh snapshot without another scan")
        configurable.reloadCatalog()
        for _ in 0..<500 where catalog.loading.contains("ps1") {
            try await Task.sleep(for: .milliseconds(10))
        }
        require(catalog.games["ps1"]?.contains { $0.title == "Added Later" } == true,
                "a PS1 game added after the last visit appears in the catalog")
        let opened = await cache.statistics().scans
        require(opened == reloaded + 1, "explicit refresh bypasses automatic throttle and scans once")
        configurable.catalogConsole = .ps1
        let staleGame = CatalogGame(id: oldPS1.path + "/Old.iso", consoleKey: "ps1", title: "Old library",
                                    fileURL: oldPS1.appendingPathComponent("Old.iso"), coverURL: nil)
        configurable.launchGame(staleGame)
        require(configurable.errorMessage != nil && configurable.storageNotice == nil && configurable.launching == nil,
                "stale old-library launch is rejected against the new local folder")
        configurable.errorMessage = nil
        configurable.resetGameFolder(for: .ps1)
        require(configurable.gameFolder(for: .ps1) == oldPS1 && catalog.source(for: "ps1")?.root == oldPS1,
                "reset restores original source without requiring SSD access")
        let resetStats = await cache.statistics()
        require(resetStats.scans == opened, "reset does not scan the disconnected default folder")
        require(configurable.launching == nil && configurable.launchID == nil, "folder integration never launches emulators")
        // Console experience regression tests use only the private fixture tree.
        let personal = PersonalLibrary(defaults: defaults)
        let uiSettings = GameLibrarySettings(defaults: defaults)
        _ = try uiSettings.setFolder(library, for: "ps1")
        _ = try uiSettings.setFolder(library, for: "ps2")
        let uiCatalog = GameCatalog(cache: cache, coverCache: CoverImageCache(directory: root.appendingPathComponent("UIcovers")))
        let ui = LauncherModel(catalog: uiCatalog, librarySettings: uiSettings,
                               organizer: CatalogOrganizer(defaults: defaults), personalLibrary: personal,
                               experience: ExperiencePreferences(defaults: defaults), startServices: false)
        ui.finishBoot()
        ui.setGameFolder(library, for: .ps2)
        // setFolder above already selected the root; explicitly give the fixture
        // source to the supplied catalog and scan without an installed library.
        for console in Console.allCases {
            uiCatalog.setSource(CatalogSource.installed(console.rawValue, root: library)!, restoreSaved: false)
            uiCatalog.refresh(console.rawValue, force: true)
        }
        for _ in 0..<500 where !uiCatalog.loading.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        ui.selected = .ps2
        ui.confirm()
        require(ui.catalogConsole == .ps2 && ui.launching == nil, "main X enters library, not emulator")
        guard let fixture = ui.listedGames.first else { fatalError("No fixture games") }
        ui.notice = "Earlier action"
        ui.reloadCatalog()
        require(ui.notice.isEmpty, "catalog reload does not leave a stale loading notice on the main menu")
        ui.selectGame(fixture)
        ui.toggleSelectedFavorite()
        require(ui.libraryState(for: .ps2).favoriteIDs.contains(fixture.id), "favorite stores current library game")
        ui.setCatalogFilter(.favorites)
        require(ui.listedGames.map(\.id) == [fixture.id], "favorites filter integrates with navigation")
        ui.setCatalogQuery("NO MATCH EXPECTED")
        require(ui.listedGames.isEmpty, "search filters without altering the snapshot")
        ui.catalogCommand = .clearSearch
        ui.setCatalogQuery("")
        require(ui.catalogCommand == .filter, "clearing search removes invisible toolbar focus")
        ui.setCatalogFilter(.all)
        ui.selectGame(fixture)
        let emptyFolder = ui.organizer.createFolder(named: "Empty", console: "ps2")!
        ui.selectCatalogSection(emptyFolder.id.uuidString)
        ui.confirm()
        require(ui.catalogSections(for: .ps2).first?.collapsed == true, "X collapses empty header")
        ui.confirm()
        require(ui.catalogSections(for: .ps2).first?.collapsed == false, "X reopens empty header without mouse")
        ui.selectGame(fixture)
        let selection = ui.gameSelection
        ui.launching = .ps2
        ui.moveVertical(1)
        ui.move(1)
        require(ui.gameSelection == selection, "launch overlay blocks vertical and horizontal movement")
        ui.launching = nil
        ui.errorMessage = "Fixture error"
        ui.moveVertical(-1)
        require(ui.gameSelection == selection, "error blocks underlying navigation")
        ui.confirm()
        require(ui.errorMessage == nil, "controller can dismiss launcher error")
        var accepted = false
        ui.dialog = LauncherDialog(title: "Fixture", message: "No external action", acceptTitle: "Accept") { accepted = true }
        ui.dialogAcceptSelected = false
        ui.confirm()
        require(!accepted && ui.dialog == nil, "confirmation defaults to safe cancel")
        ui.dialog = LauncherDialog(title: "Fixture", message: "No external action", acceptTitle: "Accept") { accepted = true }
        ui.move(1)
        ui.confirm()
        require(accepted, "controller can choose and confirm launcher dialog")
        ui.showSessionMenu()
        require(ui.showingSessionMenu && ui.previewConsole == nil, "session menu pauses previews")
        ui.back()
        ui.showExperienceSettings()
        ui.moveVertical(1)
        ui.confirm()
        require(ui.experience.soundsEnabled, "controller toggles sound preference")
        ui.back()
        require(!ui.showingExperienceSettings, "Circle dismisses experience settings")
        ui.experience.soundsEnabled = false
        ui.personalLibrary.rememberSelection(gameID: fixture.id, console: "ps2", root: library)
        let alternate = root.appendingPathComponent("Alternate")
        try FileManager.default.createDirectory(at: alternate, withIntermediateDirectories: true)
        ui.setGameFolder(alternate, for: .ps2)
        ui.setGameFolder(library, for: .ps2)
        require(ui.gameSelection["ps2"] == fixture.id, "switching back to a root restores remembered selection")
        for _ in 0..<500 where !uiCatalog.loading.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        // Rendering fixtures is opt-in. It never opens a real game or window.
        if ProcessInfo.processInfo.environment["PS12_RENDER_PREVIEWS"] == "1" {
            let output = FileManager.default.temporaryDirectory.appendingPathComponent("PS12-UI-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            for console in Console.allCases {
                ui.selected = console
                ui.catalogConsole = console
                ui.catalogCommand = nil
                ui.selectedCatalogFolderID = nil
                ui.setCatalogFilter(.all)
                ui.setCatalogQuery("")
                for size in [CGSize(width: 1000, height: 650), CGSize(width: 1512, height: 982)] {
                    let renderer = ImageRenderer(content: LauncherView(model: ui).frame(width: size.width, height: size.height))
                    renderer.scale = 1
                    guard let image = renderer.cgImage,
                          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                        fatalError("Could not render themed catalog")
                    }
                    let file = output.appendingPathComponent("\(console.rawValue)-\(Int(size.width)).png")
                    try png.write(to: file)
                    require(image.width == Int(size.width) && image.height == Int(size.height), "catalog renderer matches window size")
                }
            }
            print("UI previews: \(output.path)")
        }
        print("PASS: \(assertions) launcher-selection, folder integration, offline-storage dialog and on-demand file validation assertions")
    }
}
