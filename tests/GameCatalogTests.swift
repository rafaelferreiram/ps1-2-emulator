import Foundation
import CoreGraphics
import ImageIO

@main
struct GameCatalogTests {
    static func main() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("PS12-catalog-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let games = temporary.appendingPathComponent("Jogos", isDirectory: true)
        let covers = temporary.appendingPathComponent("covers", isDirectory: true)
        try FileManager.default.createDirectory(at: games, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: covers, withIntermediateDirectories: true)
        func write(_ path: String, _ data: Data) throws {
            let target = games.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target)
        }
        func writeText(_ path: String, _ text: String) throws { try write(path, Data(text.utf8)) }
        let one = Data([1])
        try writeText("Space/Space Jam.cue", "FILE \"Space Jam (Track 1).bin\" BINARY\n  TRACK 01 MODE2/2352\nFILE \"Space Jam (Track 2).bin\" BINARY\n  TRACK 02 AUDIO\n")
        try write("Space/Space Jam (Track 1).bin", makeDisc(serial: "SLUS_002.43", raw: true))
        try write("Space/Space Jam (Track 2).bin", one)
        try writeText("Broken/Broken.cue", "FILE \"Present (Track 1).bin\" BINARY\nFILE \"Missing.bin\" BINARY\n")
        try write("Broken/Present (Track 1).bin", one)
        try write("Standalone.iso", makeDisc(serial: "SCUS_944.56"))
        try write("hidden/._Metadata.iso", one)
        try write(".hidden/Invisible.iso", one)
        try write("bios/scph1001.bin", one)
        try write("ps2_bios.bin", one)
        try write("Archive.7z", one)
        try write("Zero.iso", Data())
        try write("Loose (Track 3).bin", one)
        try write("Multi/Disc 1.iso", one)
        try write("Multi/Disc 2.iso", one)
        try writeText("Multi/Game.m3u", "#EXTM3U\nDisc 1.iso\nDisc 2.iso\n")
        try writeText("Multi/Cycle.m3u", "Cycle.m3u\n")
        try writeText("Escape.cue", "FILE \"../../outside.bin\" BINARY\n")
        let pixel = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/a1sAAAAASUVORK5CYII=")!
        try pixel.write(to: covers.appendingPathComponent("SLUS-00243.png"))
        try pixel.write(to: covers.appendingPathComponent("SCUS-94456.png"))
        // Matching artwork beside a ROM must not override the emulator's curated cover.
        try write("Space/Space Jam.png", pixel)
        try write("Standalone.png", pixel)
        // Nearby artwork is still useful if the emulator has no matching cover.
        try write("Multi/Game.png", pixel)
        let source = CatalogSource(consoleKey: "ps1", root: games, covers: covers, database: nil)
        let result = CatalogScanner.scan(source)
        require(result.games.count == 3, "three unique valid entries, got \(result.games.map(\.title))")
        require(result.games.contains { $0.title == "Space Jam" && $0.fileURL.pathExtension == "cue" && $0.coverURL?.lastPathComponent == "SLUS-00243.png" }, "multitrack CUE + raw BIN serial + cover")
        require(result.games.contains { $0.title == "Standalone" && $0.coverURL?.resolvingSymlinksInPath().path == covers.appendingPathComponent("SCUS-94456.png").resolvingSymlinksInPath().path }, "emulator cover wins over matching nearby image")
        require(result.games.contains { $0.title == "Game" && $0.fileURL.pathExtension == "m3u" && $0.coverURL?.resolvingSymlinksInPath().path == games.appendingPathComponent("Multi/Game.png").resolvingSymlinksInPath().path }, "playlist hides component discs and keeps nearby fallback cover")
        require(result.warning?.contains("3 incomplete CUE/CCD/playlist") == true, "broken/malicious/cyclic descriptors counted")
        let missing = CatalogScanner.scan(CatalogSource(consoleKey: "ps2", root: temporary.appendingPathComponent("missing"), covers: covers, database: nil))
        require(missing.games.isEmpty && missing.warning != nil, "missing SSD is explicit")
        try verifyPS2CoverSelection(temporary: temporary)
        try verifyLoadedGameCovers(temporary: temporary)
        try verifySharedSerialCover(temporary: temporary)
        try verifyLooseDiscAndParentCover(temporary: temporary)
        print("PASS: CUE validation, BIN track deduplication, hidden/archive/BIOS filtering, playlist deduplication, descriptor traversal guard, ISO/raw serial extraction, front-cover priority, PS2 portrait filtering across every fallback, unchanged PS1 artwork, distinct covers for discs that reuse a serial, missing SSD, exact loaded-game cover lookup, CUE/CCD/M3U ownership and ambiguity rejection.")
        if CommandLine.arguments.contains("--installed") {
            let frontOverride: URL? = CommandLine.arguments.firstIndex(of: "--front-covers").flatMap { index in
                guard CommandLine.arguments.indices.contains(index + 1) else { return nil }
                return URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
            }
            for key in ["ps1", "ps2"] {
                let start = Date()
                let installed = CatalogSource.installed(key)!
                let actual = CatalogScanner.scan(CatalogSource(consoleKey: key, root: installed.root,
                    covers: installed.covers, database: installed.database,
                    frontCovers: frontOverride?.appendingPathComponent(key.uppercased(), isDirectory: true) ?? installed.frontCovers))
                print("\n\(key.uppercased()): \(actual.games.count) games, \(actual.games.filter { $0.coverURL != nil }.count) covers, \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
                for game in actual.games { print("\(game.coverURL == nil ? "MISSING" : "OK")\t\(game.title)\t\(game.coverURL?.lastPathComponent ?? "—")\t\(game.fileURL.path)") }
                if let frontOverride {
                    let prefix = frontOverride.standardizedFileURL.resolvingSymlinksInPath().path + "/"
                    for game in actual.games {
                        if let cover = game.coverURL, cover.resolvingSymlinksInPath().path.hasPrefix(prefix) {
                            print("BUNDLED FRONT\t\(game.title)\t\(cover.path)")
                        }
                    }
                }
                if let warning = actual.warning { print("WARNING: \(warning)") }
            }
        }
    }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("FAIL: \(message)") }
    }

    static func verifyPS2CoverSelection(temporary: URL) throws {
        let fm = FileManager.default
        let root = temporary.appendingPathComponent("PS2Games", isDirectory: true)
        let emulatorCovers = temporary.appendingPathComponent("PS2Covers", isDirectory: true)
        let frontCovers = temporary.appendingPathComponent("FrontCovers", isDirectory: true)
        for directory in [root, emulatorCovers, frontCovers] {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        func game(_ name: String, serial: String? = nil) throws -> URL {
            let directory = root.appendingPathComponent(name, isDirectory: true)
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent(name + ".iso")
            try (serial.map { makeDisc(serial: $0) } ?? Data([1])).write(to: file)
            return file
        }
        @discardableResult
        func art(_ directory: URL, _ name: String, width: Int = 60, height: Int = 90, orientation: Int = 1) throws -> URL {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent(name)
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                fatalError("Image fixture context failed")
            }
            context.setFillColor(CGColor(gray: 0.5, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let type = file.pathExtension.lowercased() == "jpg" ? "public.jpeg" : "public.png"
            guard let image = context.makeImage(), let destination = CGImageDestinationCreateWithURL(file as CFURL, type as CFString, 1, nil) else {
                fatalError("Image fixture destination failed")
            }
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
            require(CGImageDestinationFinalize(destination), "image fixture saved")
            return file
        }
        func normalizedPath(_ url: URL?) -> String? { url?.resolvingSymlinksInPath().path }
        var expected: [String: URL] = [:]
        var expectedAbsent: [String] = []

        let bundledName = try game("Bundled Name")
        try art(emulatorCovers, "Bundled Name.png")
        expected[bundledName.lastPathComponent] = try art(frontCovers, "Bundled Name.jpg")

        let bundledSerial = try game("SLUS_203.12.Named Game")
        try art(emulatorCovers, "SLUS_203.12.Named Game.png")
        expected[bundledSerial.lastPathComponent] = try art(frontCovers, "SLUS-20312.jpg")

        let bundledTitle = try game("SLES_100.01.Title Front")
        try art(emulatorCovers, "SLES-10001.png")
        expected[bundledTitle.lastPathComponent] = try art(frontCovers, "Title Front.png")

        let databaseName = try game("Database Named Disc", serial: "SLUS_123.45")
        let database = temporary.appendingPathComponent("TestGameIndex.yaml")
        try Data("SLUS-12345:\n  name: Database Front Name\n".utf8).write(to: database)
        try art(emulatorCovers, "Database Named Disc.png")
        expected[databaseName.lastPathComponent] = try art(frontCovers, "Database Front Name.png")

        let bundledSpread = try game("Invalid Bundled Spread")
        try art(frontCovers, "Invalid Bundled Spread.jpg", width: 140, height: 90)
        expected[bundledSpread.lastPathComponent] = try art(emulatorCovers, "Invalid Bundled Spread.png")

        let emulatorSpread = try game("Emulator Spread")
        try art(emulatorCovers, "Emulator Spread.png", width: 140, height: 90)
        expected[emulatorSpread.lastPathComponent] = try art(emulatorSpread.deletingLastPathComponent(), "Emulator Spread.png")

        let emulatorSquare = try game("Emulator Square")
        try art(emulatorCovers, "Emulator Square.png", width: 90, height: 90)
        expected[emulatorSquare.lastPathComponent] = try art(emulatorCovers, "Emulator Square.jpg")

        let nearbySpread = try game("Nearby Spread")
        try art(nearbySpread.deletingLastPathComponent(), "Nearby Spread.jpg", width: 140, height: 90)
        expected[nearbySpread.lastPathComponent] = try art(nearbySpread.deletingLastPathComponent(), "front.jpg")

        let genericSpread = try game("Generic Spread")
        try art(genericSpread.deletingLastPathComponent(), "capa.png", width: 140, height: 90)
        try art(genericSpread.deletingLastPathComponent(), "cover.png", width: 90, height: 90)
        expected[genericSpread.lastPathComponent] = try art(genericSpread.deletingLastPathComponent(), "front.png")

        let folderSpread = try game("Folder Spread")
        let folder = folderSpread.deletingLastPathComponent().appendingPathComponent("Capa", isDirectory: true)
        try art(folder, "capa.png", width: 140, height: 90)
        try art(folder, "cover.png", width: 90, height: 90)
        expected[folderSpread.lastPathComponent] = try art(folder, "front.png")

        let allSpreads = try game("SLUS_777.77.All Spreads")
        try art(frontCovers, "SLUS-77777.jpg", width: 140, height: 90)
        try art(emulatorCovers, "SLUS-77777.png", width: 140, height: 90)
        try art(allSpreads.deletingLastPathComponent(), "SLUS_777.77.All Spreads.png", width: 140, height: 90)
        try art(allSpreads.deletingLastPathComponent(), "All Spreads.png", width: 140, height: 90)
        try art(allSpreads.deletingLastPathComponent(), "capa.png", width: 140, height: 90)
        try art(allSpreads.deletingLastPathComponent().appendingPathComponent("Capa"), "front.png", width: 140, height: 90)
        expectedAbsent.append(allSpreads.lastPathComponent)

        let caseScan = try game("JBGS_030.18.Street Fighter 30th")
        expected[caseScan.lastPathComponent] = try art(caseScan.deletingLastPathComponent(), "Street Fighter 30th - CAPA.png", width: 150, height: 100)

        let squareOnly = try game("Square Only")
        try art(frontCovers, "Square Only.png", width: 90, height: 90)
        try art(emulatorCovers, "Square Only.png", width: 90, height: 90)
        expectedAbsent.append(squareOnly.lastPathComponent)

        let rotated = try game("Rotated Portrait")
        expected[rotated.lastPathComponent] = try art(frontCovers, "Rotated Portrait.jpg", width: 90, height: 60, orientation: 6)
        for width in [55, 85] {
            let edge = try game("Ratio \(width)")
            expected[edge.lastPathComponent] = try art(frontCovers, "Ratio \(width).png", width: width, height: 100)
        }
        for width in [54, 86] {
            let outside = try game("Ratio \(width)")
            try art(frontCovers, "Ratio \(width).png", width: width, height: 100)
            expectedAbsent.append(outside.lastPathComponent)
        }

        let ps2Source = CatalogSource(consoleKey: "ps2", root: root, covers: emulatorCovers,
                                     database: database, frontCovers: frontCovers)
        let ps2 = CatalogScanner.scan(ps2Source)
        require(ps2.games.count == expected.count + expectedAbsent.count, "every portrait fixture is inventoried")
        require(ps2.games.first { $0.fileURL == caseScan }?.title == "Street Fighter 30th",
                "a custom four-letter serial is removed from the title")
        let panel = CGContext(data: nil, width: 150, height: 100, bitsPerComponent: 8, bytesPerRow: 150 * 4,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        panel.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        panel.fill(CGRect(x: 0, y: 0, width: 150, height: 100))
        panel.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        panel.fill(CGRect(x: 78, y: 0, width: 72, height: 100))
        let front = CatalogScanner.displayImage(panel.makeImage()!)
        require(front.width == 72 && front.height == 100, "an unfolded case keeps only the front panel")
        for (fileName, image) in expected {
            require(normalizedPath(ps2.games.first { $0.fileURL.lastPathComponent == fileName }?.coverURL) == normalizedPath(image),
                    "PS2 selected expected front cover for \(fileName)")
            let file = ps2.games.first { $0.fileURL.lastPathComponent == fileName }!.fileURL
            require(normalizedPath(CatalogScanner.coverForLoadedGame(path: file.path, source: ps2Source)) == normalizedPath(image),
                    "loaded PS2 game reuses catalog front-cover priority for \(fileName)")
        }
        for fileName in expectedAbsent {
            require(ps2.games.first { $0.fileURL.lastPathComponent == fileName }?.coverURL == nil,
                    "PS2 rejects square/spread across every source for \(fileName)")
            let file = ps2.games.first { $0.fileURL.lastPathComponent == fileName }!.fileURL
            require(CatalogScanner.coverForLoadedGame(path: file.path, source: ps2Source) == nil,
                    "loaded PS2 game never reintroduces a rejected spread for \(fileName)")
        }

        let ps1 = CatalogScanner.scan(CatalogSource(consoleKey: "ps1", root: root, covers: emulatorCovers,
                                                   database: database, frontCovers: frontCovers))
        require(normalizedPath(ps1.games.first { $0.fileURL == emulatorSpread }?.coverURL) == normalizedPath(emulatorCovers.appendingPathComponent("Emulator Spread.png")),
                "PS1 landscape behavior is unchanged")
        require(normalizedPath(ps1.games.first { $0.fileURL == squareOnly }?.coverURL) == normalizedPath(frontCovers.appendingPathComponent("Square Only.png")),
                "PS1 square cover remains valid and uses bundled priority")
        for key in ["ps1", "ps2"] {
            require(CatalogSource.installed(key)?.frontCovers?.path.hasSuffix("/Covers/\(key.uppercased())") == true,
                    "installed \(key) resolves bundled front-cover directory")
        }
    }

    static func verifyLoadedGameCovers(temporary: URL) throws {
        let fm = FileManager.default
        let root = temporary.appendingPathComponent("LoadedGames", isDirectory: true)
        let covers = temporary.appendingPathComponent("LoadedCovers", isDirectory: true)
        for directory in [root, covers] { try fm.createDirectory(at: directory, withIntermediateDirectories: true) }
        let pixel = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/a1sAAAAASUVORK5CYII=")!
        @discardableResult
        func file(_ path: String, _ text: String = "disc") throws -> URL {
            let file = root.appendingPathComponent(path)
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file)
            return file
        }
        func art(_ name: String) throws -> URL {
            let file = covers.appendingPathComponent(name + ".png")
            try pixel.write(to: file)
            return file
        }
        let source = CatalogSource(consoleKey: "ps1", root: root, covers: covers, database: nil)
        func expect(_ file: URL, _ image: URL?, _ message: String) {
            require(CatalogScanner.coverForLoadedGame(path: file.path, source: source)?.resolvingSymlinksInPath().path
                    == image?.resolvingSymlinksInPath().path, message)
        }
        let direct = try file("Direct.iso")
        let directArt = try art("Direct")
        expect(direct, directArt, "direct ISO finds its own cover")
        expect(root.appendingPathComponent("unused/../Direct.iso"), directArt, "loaded path is standardized before exact matching")
        require(CatalogScanner.coverForLoadedGame(path: "Direct.iso", source: source) == nil, "relative loaded paths are rejected")
        require(CatalogScanner.coverForLoadedGame(path: direct.absoluteString, source: source) == nil, "file URL strings are not confused with absolute paths")
        let similar = try file("Direct Edition.iso")
        expect(similar, nil, "a similar title never selects another game's artwork")
        expect(root.appendingPathComponent("Missing.iso"), nil, "missing loaded game never gets artwork")
        try Data("disc".utf8).write(to: temporary.appendingPathComponent("Direct.iso"))
        expect(temporary.appendingPathComponent("Direct.iso"), nil, "same-named file outside library never gets artwork")

        let cue = try file("Cue/Game.cue", "FILE \"data.bin\" BINARY\n  TRACK 01 MODE2/2352\nFILE \"audio.bin\" BINARY\n  TRACK 02 AUDIO\n")
        let cueData = try file("Cue/data.bin")
        let cueAudio = try file("Cue/audio.bin")
        let cueArt = try art("Game")
        expect(cue, cueArt, "CUE path resolves its catalog cover")
        expect(cueData, cueArt, "underlying CUE data BIN resolves descriptor cover")
        expect(cueAudio, cueArt, "underlying CUE audio track identifies the same descriptor")
        let ccd = try file("Clone/Clone Game.ccd", "[CloneCD]\nVersion=3\n")
        let img = try file("Clone/Clone Game.img")
        let ccdArt = try art("Clone Game")
        expect(ccd, ccdArt, "CCD path resolves its catalog cover")
        expect(img, ccdArt, "underlying CCD IMG resolves descriptor cover")

        let first = try file("Collection/Disc 1.cue", "FILE \"part1.bin\" BINARY\n  TRACK 01 MODE2/2352\n")
        let firstData = try file("Collection/part1.bin")
        let second = try file("Collection/Disc 2.iso")
        let playlist = try file("Collection/Collection.m3u", "#EXTM3U\nDisc 1.cue\nDisc 2.iso\n")
        let playlistArt = try art("Collection")
        for member in [playlist, first, firstData, second] {
            expect(member, playlistArt, "valid playlist resolves its own path, discs, and nested CUE tracks")
        }
        let shared = try file("Ambiguous/shared.bin")
        for name in ["Owner A", "Owner B"] {
            try file("Ambiguous/\(name).cue", "FILE \"shared.bin\" BINARY\n  TRACK 01 MODE2/2352\n")
            _ = try art(name)
        }
        expect(shared, nil, "BIN with two valid CUE owners has no guessed cover")
        let sharedDisc = try file("AmbiguousLists/shared.iso")
        for name in ["List A", "List B"] {
            try file("AmbiguousLists/\(name).m3u", "shared.iso\n")
            _ = try art(name)
        }
        expect(sharedDisc, nil, "disc in competing playlists has no guessed cover")
        let brokenData = try file("Broken/present.bin")
        try file("Broken/Broken.cue", "FILE \"present.bin\" BINARY\n  TRACK 01 MODE2/2352\nFILE \"missing.bin\" BINARY\n  TRACK 02 AUDIO\n")
        _ = try art("Broken")
        expect(brokenData, nil, "invalid CUE cannot provide a cover for an orphan track")
        try file("Invalid List.m3u", "Direct.iso\nmissing.iso\n")
        _ = try art("Invalid List")
        expect(direct, directArt, "invalid playlist does not take ownership of a valid disc")
        let hidden = try file(".hidden/Direct.iso")
        expect(hidden, nil, "hidden loaded file is not reintroduced")
        let bios = try file("bios/scph1001.bin")
        _ = try art("scph1001")
        expect(bios, nil, "BIOS never receives a game cover")
        let outsideLink = root.appendingPathComponent("Outside.iso")
        try fm.createSymbolicLink(at: outsideLink, withDestinationURL: temporary.appendingPathComponent("Direct.iso"))
        expect(outsideLink, nil, "symlink escaping the root never receives a game cover")
        let siblingRoot = temporary.appendingPathComponent("LoadedGames-other", isDirectory: true)
        try fm.createDirectory(at: siblingRoot, withIntermediateDirectories: true)
        let sibling = siblingRoot.appendingPathComponent("Direct.iso")
        try Data("disc".utf8).write(to: sibling)
        expect(sibling, nil, "root prefix alone does not authorize a sibling directory")
    }

    static func verifySharedSerialCover(temporary: URL) throws {
        let root = temporary.appendingPathComponent("SharedSerial", isDirectory: true)
        let covers = temporary.appendingPathComponent("SharedCovers", isDirectory: true)
        for directory in [root, covers] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let serial = "SLUS_111.11"
        let we = root.appendingPathComponent("WE2002 Traducao.iso")
        let modDirectory = root.appendingPathComponent("Brasileirao 2008", isDirectory: true)
        try FileManager.default.createDirectory(at: modDirectory, withIntermediateDirectories: true)
        let mod = modDirectory.appendingPathComponent("Brasileirao 2008.iso")
        try makeDisc(serial: serial).write(to: we)
        try makeDisc(serial: serial).write(to: mod)
        let pixel = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/a1sAAAAASUVORK5CYII=")!
        let official = covers.appendingPathComponent("SLUS-11111.png")
        try pixel.write(to: official)
        let own = modDirectory.appendingPathComponent("Capa.png")
        try pixel.write(to: own)
        let database = temporary.appendingPathComponent("SharedSerial.yaml")
        try Data("SLUS-11111:\n  name: \"World Soccer Winning Eleven 2002\"\n".utf8).write(to: database)
        let scanned = CatalogScanner.scan(CatalogSource(consoleKey: "ps1", root: root, covers: covers, database: database))
        let weGame = scanned.games.first { $0.fileURL == we }
        let modGame = scanned.games.first { $0.fileURL == mod }
        require(weGame?.coverURL?.resolvingSymlinksInPath().path == official.resolvingSymlinksInPath().path,
                "the disc closest to the official name keeps the serial cover")
        require(modGame?.coverURL?.resolvingSymlinksInPath().path == own.resolvingSymlinksInPath().path,
                "a different game that reuses the serial keeps its own cover")
    }

    static func verifyLooseDiscAndParentCover(temporary: URL) throws {
        let root = temporary.appendingPathComponent("LooseDiscs", isDirectory: true)
        let covers = temporary.appendingPathComponent("LooseCovers", isDirectory: true)
        for directory in [root, covers] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let ninja = root.appendingPathComponent("Ninja", isDirectory: true)
        try FileManager.default.createDirectory(at: ninja, withIntermediateDirectories: true)
        let first = ninja.appendingPathComponent("Ninja - Shadow of Darkness (Europe) (Track 01).bin")
        try makeDisc(serial: "SLES_015.54", raw: true).write(to: first)
        try Data([1]).write(to: ninja.appendingPathComponent("Ninja - Shadow of Darkness (Europe) (Track 02).bin"))
        let art = ninja.appendingPathComponent("capa.jpeg")
        try Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/a1sAAAAASUVORK5CYII=")!.write(to: art)
        let pride = root.appendingPathComponent("PRIDE FC/GAME", isDirectory: true)
        try FileManager.default.createDirectory(at: pride, withIntermediateDirectories: true)
        let iso = pride.appendingPathComponent("PRIDE FC.iso")
        try Data("disc".utf8).write(to: iso)
        let parentArt = root.appendingPathComponent("PRIDE FC/pride.png")
        try Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/a1sAAAAASUVORK5CYII=")!.write(to: parentArt)
        try Data([1]).write(to: root.appendingPathComponent("Loose (Track 3).bin"))
        let scanned = CatalogScanner.scan(CatalogSource(consoleKey: "ps1", root: root, covers: covers, database: nil))
        let ninjaGame = scanned.games.first { $0.fileURL == first }
        require(scanned.games.count == 2, "an uncued first track and a disc in GAME are games, later tracks are not")
        require(ninjaGame?.title == "Ninja - Shadow of Darkness (Europe)", "the track suffix is removed from the title")
        require(ninjaGame?.coverURL?.resolvingSymlinksInPath().path == art.resolvingSymlinksInPath().path,
                "capa.jpeg beside the tracks is the cover")
        require(scanned.games.first { $0.fileURL == iso }?.coverURL?.resolvingSymlinksInPath().path == parentArt.resolvingSymlinksInPath().path,
                "a single image above GAME/ is that disc's cover")
        require(scanned.games.contains { $0.fileURL.lastPathComponent == "Loose (Track 3).bin" } == false,
                "a lone later track is still not a game")
    }

    static func makeDisc(serial: String, raw: Bool = false) -> Data {
        var data = Data(repeating: 0, count: 40 * 2048)
        func uint32(_ value: UInt32, _ offset: Int) {
            for i in 0..<4 { data[offset + i] = UInt8((value >> (8 * i)) & 255) }
        }
        let pvd = 16 * 2048
        data[pvd] = 1
        data.replaceSubrange((pvd + 1)..<(pvd + 6), with: Data("CD001".utf8))
        data[pvd + 156] = 34
        uint32(20, pvd + 158)
        uint32(2048, pvd + 166)
        let directory = 20 * 2048
        let name = Data("SYSTEM.CNF;1".utf8)
        let boot = Data("BOOT2 = cdrom0:\\\(serial);1\n".utf8)
        data[directory] = UInt8(33 + name.count)
        uint32(22, directory + 2)
        uint32(UInt32(boot.count), directory + 10)
        data[directory + 32] = UInt8(name.count)
        data.replaceSubrange((directory + 33)..<(directory + 33 + name.count), with: name)
        data.replaceSubrange((22 * 2048)..<(22 * 2048 + boot.count), with: boot)
        if !raw { return data }
        var rawData = Data(repeating: 0, count: 40 * 2352)
        for sector in 0..<40 {
            rawData.replaceSubrange((sector * 2352 + 24)..<(sector * 2352 + 24 + 2048), with: data[(sector * 2048)..<((sector + 1) * 2048)])
        }
        return rawData
    }
}
