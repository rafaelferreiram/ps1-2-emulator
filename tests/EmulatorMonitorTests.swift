import Foundation

/// Run with tests/run-monitor-tests.sh. Uses synthetic paths and timestamps only;
/// does not launch emulators, open game images or change their configuration.
@main
struct EmulatorMonitorTests {
    @MainActor
    static func main() {
        let ps1 = "/Volumes/Extreme SSD/Emulacao/PS1/Jogos"
        let ps2 = "/Volumes/Extreme SSD/Emulacao/PS2/Jogos"
        var checks = 0
        func check(_ result: @autoclosure () -> Bool, _ description: String) {
            guard result() else { fatalError("FAIL: \(description)") }
            checks += 1
        }

        let tracks = ["Space Jam (USA) (Track 1).bin", "Space Jam (USA) (Track 2).BIN", "Space Jam (USA).cue"]
            .map { ps1 + "/Space Jam (USA)/" + $0 }
        let images = EmulatorMonitor.testImages(paths: tracks, library: ps1)
        check(images.count == 1, "PS1 tracks collapse into one disc")
        check(images.first?.title == "Space Jam (USA)", "Track suffix removed without losing region")
        check(images.first?.path.hasSuffix(".cue") == true, "CUE preferred to BIN tracks")
        let formats = EmulatorMonitor.testImages(paths: ["Hugo.cue", "Hugo.chd", "Hugo.iso", "Hugo.bin"]
            .map { ps1 + "/Hugo/" + $0 }, library: ps1)
        check(formats.count == 1 && formats.first?.path.hasSuffix(".chd") == true, "CHD preferred over same-name metadata/raw formats")
        let trackStyles = EmulatorMonitor.testImages(paths: ["Hugo [Track 01].bin", "Hugo_track_02.bin", "Hugo.track03.bin"]
            .map { ps1 + "/Hugo/" + $0 }, library: ps1)
        check(trackStyles.count == 1 && trackStyles.first?.title == "Hugo", "Alternative track naming normalized")

        let serials = [
            ("SLUS_215.72.Surf's Up.iso", "Surf's Up"),
            ("SCUS_974.81.God of War 2 DUB BR.iso", "God of War 2 DUB BR"),
            ("SLES-51234.FIFA 08.iso", "FIFA 08"),
            ("BETA_005.22 .GTA Generations 5.0.4 Brasil.iso", "GTA Generations 5.0.4 Brasil"),
            ("Bomba FC 27 V4 Setembro 2026.ISO", "Bomba FC 27 V4 Setembro 2026")
        ]
        for (file, title) in serials {
            check(EmulatorMonitor.testImages(paths: [ps2 + "/" + file], library: ps2).first?.title == title,
                  "PS2 title: \(file)")
        }
        for (file, title) in [("FIFA Street 2.gz", "FIFA Street 2"),
                              ("SLUS_215.72.Surf's Up.iso.gz", "Surf's Up"),
                              ("Tarzan (Track 1).BIN.GZ", "Tarzan")] {
            check(EmulatorMonitor.testImages(paths: [ps2 + "/" + file], library: ps2).first?.title == title,
                  "Compressed image title: \(file)")
        }
        let compressedDuplicate = EmulatorMonitor.testImages(paths: [ps2 + "/Game.iso", ps2 + "/Game.iso.gz"], library: ps2)
        check(compressedDuplicate.count == 1 && compressedDuplicate.first?.path.hasSuffix("Game.iso") == true,
              "Compressed and raw copies of one disc share identity")

        let rejected = [
            ps2 + "/FIFA Street 2.iso", // Wrong console's root.
            ps1 + "-Backup/Tarzan.bin", // Prefix boundary is significant.
            ps1 + "/../BIOS/BIOS.iso",
            ps1 + "/bios/Tarzan.bin",
            ps1 + "/CACHE/Tarzan.iso",
            ps1 + "/saves/Tarzan.bin",
            ps1 + "/savestates/Tarzan.bin",
            ps1 + "/memcards/Tarzan.bin",
            ps1 + "/covers/Tarzan.bin",
            ps1 + "/thumbnails/Tarzan.bin",
            ps1 + "/scph1001.bin",
            ps1 + "/SCPH-5501.bin",
            ps1 + "/ps2_bios.bin",
            ps1 + "/BIOS.iso",
            ps1 + "/._Tarzan.bin",
            ps1 + "/.hidden/Tarzan.bin",
            ps1 + "/Tarzan/.cache/Tarzan.iso",
            ps1 + "/Tarzan.zip",
            ps1 + "/Tarzan.7z",
            ps1 + "/Tarzan.png"
        ]
        for path in rejected {
            check(EmulatorMonitor.testImages(paths: [path], library: ps1).isEmpty, "Excluded: \(path)")
        }
        check(EmulatorMonitor.testImages(paths: [ps1 + "/Game A/Tarzan.iso", ps1 + "/Game B/Tarzan.iso"], library: ps1).count == 2,
              "Different directories are not falsely collapsed")
        check(EmulatorMonitor.testImages(paths: [tracks[0], tracks[0]], library: ps1).count == 1,
              "Multiple handles to same image deduplicated")

        let monitor = EmulatorMonitor()
        let launch = Date(timeIntervalSince1970: 1_000)
        let game = ps1 + "/Tarzan/Tarzan.bin"
        let secondGame = ps1 + "/Hugo/Hugo.chd"
        func observe(_ second: Double, paths: [String] = [], pid: Int32? = 42,
                     date: Date? = nil, available: Bool = true) -> EmulatorState {
            monitor.testObserve(library: ps1, pid: pid, launchedAt: date ?? launch, paths: paths,
                                available: available, now: launch.addingTimeInterval(second))
        }
        let initial = observe(0, paths: [game])
        check(initial.gameTitle == nil && initial.activityDescription == "Verificando jogo…", "First poll is provisional")
        check(observe(0.5, paths: [game]).gameTitle == nil, "Rapid second poll cannot prove stability")
        let loaded = observe(1, paths: [game])
        check(loaded.gameTitle == "Tarzan" && loaded.gamePath == game, "Stable game becomes loaded")
        check(loaded.pid == 42 && loaded.launchedAt == launch, "Uptime stays bound to process start")
        let closed = observe(2)
        check(closed.gameTitle == nil && closed.gamePath == nil && closed.activityDescription.contains("sem jogo detectado"),
              "Disc close immediately removes old title and path")
        check(observe(3, paths: [game]).gameTitle == nil, "Reopened disc must stabilize again")
        check(observe(4, paths: [game]).gameTitle == "Tarzan", "Reopened disc settles")
        let multiple = observe(5, paths: [game, secondGame])
        check(multiple.gameTitle == nil && multiple.activityDescription.contains("vários discos"), "Ambiguous scan clears title")
        check(observe(6, paths: [game]).gameTitle == nil, "After multiple candidates, stability resets")
        check(observe(7, paths: [game]).gameTitle == "Tarzan", "Single candidate recovers after ambiguity")
        check(observe(8, paths: [game], pid: 43).gameTitle == nil, "New PID cannot inherit game state")
        check(observe(9, paths: [game], pid: 43).gameTitle == "Tarzan", "New PID must stabilize")
        let newLaunch = launch.addingTimeInterval(10)
        check(observe(10, paths: [game], pid: 43, date: newLaunch).gameTitle == nil, "Reused PID with new launch date resets")
        check(observe(11, paths: [game], pid: 43, date: newLaunch).gameTitle == "Tarzan", "New launch date session stabilizes")
        check(observe(12, paths: [game], pid: nil) == .off, "Terminated app clears every session field")
        check(observe(13, paths: [game]).gameTitle == nil, "Reopened app starts clean")
        check(observe(14, paths: [game]).gameTitle == "Tarzan", "Reopened app stabilizes")
        let denied = observe(15, paths: [game], available: false)
        check(denied.gameTitle == nil && denied.activityDescription == "Jogo não identificado", "Denied/incomplete probe never reports old game")
        check(observe(16, paths: [game]).gameTitle == nil, "Recovered access starts fresh observation")
        check(observe(17, paths: [game]).gameTitle == "Tarzan", "Recovered access stabilizes")
        check(observe(18, paths: [secondGame]).gameTitle == nil, "Direct game change does not retain first title")
        check(observe(19, paths: [secondGame]).gameTitle == "Hugo", "New game stabilizes")

        let secondConsole = monitor.testObserve(key: "ps2", library: ps2, pid: 55, launchedAt: launch,
                                              paths: [ps2 + "/FIFA Street 2.iso"], now: launch.addingTimeInterval(20))
        check(secondConsole.gameTitle == nil, "Each console keeps separate observations")
        check(observe(20, paths: [secondGame]).gameTitle == "Hugo", "PS2 observation leaves PS1 state intact")
        let loadedPS2 = monitor.testObserve(key: "ps2", library: ps2, pid: 55, launchedAt: launch,
                                          paths: [ps2 + "/FIFA Street 2.iso"], now: launch.addingTimeInterval(21))
        check(loadedPS2.gameTitle == "FIFA Street 2", "Second console independently stabilizes")

        let externalMonitor = EmulatorMonitor()
        let outsideMessage = "Jogo não identificado · fora da biblioteca"
        let noGameMessage = "Emulador aberto · sem jogo detectado"
        func external(_ paths: [String], sizes: [String: Int64] = [:], second: Double = 0) -> EmulatorState {
            externalMonitor.testObserve(library: ps1, pid: 70, launchedAt: launch, paths: paths, sizes: sizes,
                                        now: launch.addingTimeInterval(second))
        }
        for extensionName in ["iso", "chd", "cue", "cso", "zso", "pbp", "img", "mdf", "gz"] {
            let externalState = external(["/Users/player/Downloads/External Game." + extensionName])
            check(externalState.isRunning && externalState.activityDescription == outsideMessage &&
                  externalState.gameTitle == nil && externalState.gamePath == nil,
                  "External \(extensionName) blocks disc swap without exposing or guessing title")
        }
        check(external([ps2 + "/Wrong Console.iso"]).activityDescription == outsideMessage,
              "Another console's folder is external to this monitored console")
        check(external(["/private/tmp/Extracted Game.iso"]).activityDescription == outsideMessage,
              "Obvious disc images in temporary folders are conservatively busy")
        let excludedOutside = [
            "/Users/player/Downloads/scph1001.bin",
            "/Users/player/Downloads/SCPH.bin",
            "/Users/player/Downloads/ps2_bios.bin",
            "/Users/player/Downloads/bios.iso.gz",
            "/Users/player/Downloads/BIOS/Unknown.bin",
            "/Users/player/Downloads/cache/Unknown.iso",
            "/Users/player/Downloads/caches/Unknown.iso",
            "/Users/player/Downloads/memcards/Unknown.bin",
            "/Users/player/Downloads/.hidden/Game.iso",
            "/Users/player/Downloads/._Game.iso",
            "/Users/player/Library/Emulator/Game.iso",
            "/Users/player/AppData/Emulator/Game.chd",
            "/Library/Application Support/Emulator/Game.iso",
            "/System/Library/Game.iso",
            "/Applications/PCSX2.app/Contents/Resources/Game.iso",
            "/Users/player/Downloads/Test.app/Contents/Game.iso",
            "/Volumes/External/Library/Emulator/Game.iso",
            "/private/var/folders/test/Caches/Emulator/Game.iso"
        ]
        for path in excludedOutside {
            check(external([path], sizes: [path: 100 * 1024 * 1024]).activityDescription == noGameMessage,
                  "External BIOS/cache/system/app-data excluded: \(path)")
        }
        let largeBIN = "/Volumes/Other Disk/Games/Space Jam (Track 1).bin"
        check(external([largeBIN], sizes: [largeBIN: 64 * 1024 * 1024]).activityDescription == outsideMessage,
              "Large external PS1 BIN in a user volume is busy")
        let smallBIN = "/Users/player/Downloads/dump.bin"
        check(external([smallBIN], sizes: [smallBIN: 4 * 1024 * 1024]).activityDescription == noGameMessage,
              "Small external BIN is too ambiguous to identify (may be a BIOS)")
        check(external(["/private/tmp/Unknown.bin"], sizes: ["/private/tmp/Unknown.bin": 64 * 1024 * 1024]).activityDescription == noGameMessage,
              "External generic BIN is limited to user directories and mounted volumes")
        check(external([largeBIN]).activityDescription == noGameMessage, "External BIN requires an observed size")
        check(external([game], second: 1).gameTitle == nil, "Library disc starts a fresh observation after an external image")
        check(external([game], second: 2).gameTitle == "Tarzan", "Library game recovers after external image closes")
        check(external(["/Users/player/Downloads/Other.iso"], second: 3).gameTitle == nil &&
              external(["/Users/player/Downloads/Other.iso"], second: 3).activityDescription == outsideMessage,
              "Switch to an external image immediately clears the previous library title")
        let compressed = ps1 + "/Tarzan/Tarzan.bin.gz"
        check(external([compressed], second: 4).gameTitle == nil, "GZ file follows stabilization rule")
        check(external([compressed], second: 5).gameTitle == "Tarzan", "Stable GZ file is identified")

        print("PASS: \(checks) emulator monitor checks")
    }
}
