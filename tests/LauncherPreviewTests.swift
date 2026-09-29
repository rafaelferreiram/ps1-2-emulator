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

    static func main() throws {
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
        let model = LauncherModel(startServices: false)
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
        let offline = LauncherModel(storageProbe: { connected }, startServices: false)
        offline.finishBoot()
        require(!offline.storageMounted, "offline startup does not require the SSD")
        for console in Console.allCases {
            let absent = console.folder.appendingPathComponent("Offline-fixture-does-not-exist.iso")
            let game = CatalogGame(id: absent.path, consoleKey: console.rawValue, title: "Jogo de teste", fileURL: absent, coverURL: nil)
            offline.catalogConsole = console
            offline.launchGame(game)
            require(offline.storageNotice == StorageNotice(gameTitle: game.title, consoleName: console.badge), "missing SSD shows the console-styled notice")
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
        print("PASS: \(assertions) launcher-selection, offline-storage dialog and on-demand file validation assertions")
    }
}
