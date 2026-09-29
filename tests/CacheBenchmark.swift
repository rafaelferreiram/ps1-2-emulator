import Foundation

/// Read-only benchmark of installed libraries. Cache output stays in a temporary directory.
@main
struct CacheBenchmark {
    static func main() async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("PS12-cache-benchmark-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let catalogDirectory = temporary.appendingPathComponent("Catalog")
        let coverDirectory = temporary.appendingPathComponent("Thumbnails")
        let catalog = CatalogCache(directory: catalogDirectory)
        let covers = CoverImageCache(directory: coverDirectory)
        for console in ["ps1", "ps2"] {
            let installed = CatalogSource.installed(console)!
            let source = CatalogSource(consoleKey: console, root: installed.root, covers: installed.covers,
                database: installed.database, frontCovers: CommandLine.arguments.dropFirst().first.map {
                    URL(fileURLWithPath: $0).appendingPathComponent(console.uppercased())
                } ?? installed.frontCovers)
            let baselineStart = Date()
            let baseline = await Task.detached { CatalogScanner.scan(source) }.value
            let baselineTime = Date().timeIntervalSince(baselineStart)
            guard baseline.warning == nil, !baseline.games.isEmpty else {
                print("\(console.uppercased()): library unavailable; benchmark skipped.")
                continue
            }
            let coldStart = Date()
            let cold = await catalog.load(source)
            let coldTime = Date().timeIntervalSince(coldStart)
            precondition(cold.games == baseline.games, "Cold cache must preserve catalog contents")
            precondition(cold.snapshotID != nil, "Full load must expose a saved snapshot ID")
            let beforeWarm = await catalog.statistics()
            var warmTimes: [Double] = []
            for _ in 0..<5 {
                let start = Date()
                let warm = await catalog.load(source)
                warmTimes.append(Date().timeIntervalSince(start))
                precondition(warm.games == baseline.games, "Warm cache must preserve catalog contents")
            }
            let warmMean = warmTimes.reduce(0, +) / Double(warmTimes.count)
            let afterWarm = await catalog.statistics()
            precondition(afterWarm.scans == beforeWarm.scans && afterWarm.fingerprintChecks == beforeWarm.fingerprintChecks,
                         "Repeated catalog opening must not scan or fingerprint any source")
            let freshProcess = CatalogCache(directory: catalogDirectory)
            let diskStart = Date()
            let disk = await freshProcess.load(source)
            let diskTime = Date().timeIntervalSince(diskStart)
            precondition(disk.games == baseline.games, "Persistent cache must preserve catalog contents")
            let diskStats = await freshProcess.statistics()
            precondition(diskStats.scans == 0 && diskStats.fingerprintChecks == 0,
                         "Reopening from disk must not touch library metadata")
            let artworkURLs = Array(Set(baseline.games.compactMap(\.coverURL)))
            let artworkStart = Date()
            for url in artworkURLs {
                let image = await covers.image(at: url, maxPixelSize: 320, snapshotID: cold.snapshotID)
                precondition(image != nil, "Existing cover must decode")
                let small = await covers.image(at: url, maxPixelSize: 108, snapshotID: cold.snapshotID)
                precondition(small != nil, "Menu thumbnail must decode")
            }
            let artworkCold = Date().timeIntervalSince(artworkStart)
            let artworkWarmStart = Date()
            for url in artworkURLs {
                let image = await covers.image(at: url, maxPixelSize: 320, snapshotID: cold.snapshotID)
                precondition(image != nil, "Cached cover must decode")
                let small = await covers.image(at: url, maxPixelSize: 108, snapshotID: cold.snapshotID)
                precondition(small != nil, "Cached menu thumbnail must decode")
            }
            let artworkWarm = Date().timeIntervalSince(artworkWarmStart)
            print(String(format: "%@: %d games / %d covers | scan %.1f ms | cache cold %.1f ms | warm mean %.1f ms | reopened disk %.1f ms | warm vs scan %.1fx",
                console.uppercased(), baseline.games.count, artworkURLs.count, baselineTime * 1000,
                coldTime * 1000, warmMean * 1000, diskTime * 1000, baselineTime / max(0.000001, warmMean)))
            print(String(format: "%@ thumbnails: first pass %.1f ms | memory reuse %.1f ms", console.uppercased(), artworkCold * 1000, artworkWarm * 1000))
            print("Disk catalog statistics: \(await freshProcess.statistics())")
        }
        print("Shared catalog statistics: \(await catalog.statistics())")
        print("Shared artwork statistics: \(await covers.statistics())")
    }
}
