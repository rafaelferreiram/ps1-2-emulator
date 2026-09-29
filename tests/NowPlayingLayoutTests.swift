import AppKit
import SwiftUI

@main
@MainActor
struct NowPlayingLayoutTests {
    static func main() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("PS12-now-playing-layout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let square = artwork(width: 120, height: 120)
        let portrait = artwork(width: 120, height: 172)
        try await verifyLoader(output: output, image: portrait)
        let examples: [(String, String, NSImage?)] = [
            ("ps1", "Space Jam", square),
            ("ps2", "Need for Speed Underground 2", portrait),
            ("ps2", "Um título muito longo que não deve aumentar a altura do menu principal", nil)
        ]
        for (index, example) in examples.enumerated() {
            for width in [285.0, 320.0] {
                let label = NowPlayingGameLabel(consoleKey: example.0, title: example.1, image: example.2)
                    .frame(width: width)
                let renderer = ImageRenderer(content: label)
                renderer.scale = 2
                guard let image = renderer.nsImage else { fatalError("Could not render label") }
                precondition(image.size == NSSize(width: width, height: 36), "Labels must fit the original session row")
                guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Missing PNG") }
                try png.write(to: output.appendingPathComponent("label-\(index)-\(Int(width)).png"))
            }
        }
        let preview = VStack(alignment: .leading, spacing: 20) {
            Text("PS1/2 · prévia de layout (dados de teste)").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
            ForEach(Array(examples.enumerated()), id: \.offset) { _, example in
                VStack(alignment: .leading, spacing: 6) {
                    Text(example.0.uppercased() + "  ·  LIGADO  ·  00:12:34").font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.cyan)
                    NowPlayingGameLabel(consoleKey: example.0, title: example.1, image: example.2)
                }
            }
        }.frame(width: 320).padding(24).background(Color(red: 0.012, green: 0.021, blue: 0.055))
        let renderer = ImageRenderer(content: preview)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { fatalError("Missing preview") }
        let previewURL = output.appendingPathComponent("preview.png")
        try png.write(to: previewURL)
        print("PASS: 6 compact now-playing layouts (PS1, PS2, missing cover/long title), all 36 pt high.")
        print("Preview: \(previewURL.path)")
    }

    private static func verifyLoader(output: URL, image: NSImage) async throws {
        let root = output.appendingPathComponent("fixtures/games")
        let covers = output.appendingPathComponent("fixtures/covers")
        for folder in [root, covers] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let disc = root.appendingPathComponent("Example.iso")
        try Data([1]).write(to: disc)
        let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        try png.write(to: covers.appendingPathComponent("Example.png"))
        let source = CatalogSource(consoleKey: "ps2", root: root, covers: covers, database: nil)
        let catalogCache = CatalogCache(directory: output.appendingPathComponent("catalog-cache"))
        let loader = NowPlayingArtwork(catalogCache: catalogCache,
                                       coverCache: CoverImageCache(directory: output.appendingPathComponent("cover-cache")))
        await loader.load(path: disc.path, source: source)
        precondition(loader.image == nil, "Now-playing must not scan the library when no snapshot exists")
        _ = await catalogCache.load(source, force: true)
        await loader.load(path: disc.path, source: source)
        precondition(loader.image != nil, "Matching artwork must decode")
        precondition(max(loader.image!.size.width, loader.image!.size.height) <= 108, "Thumbnail must be bounded")
        await loader.load(path: root.appendingPathComponent("Missing.iso").path, source: source)
        precondition(loader.image == nil, "A missing game must clear the previous artwork")
        let pending = Task { @MainActor in await loader.load(path: disc.path, source: source) }
        pending.cancel()
        await pending.value
        precondition(loader.image == nil, "Canceled lookup must not restore stale artwork")
        print("PASS: artwork decoding, 108 px bound, missing-game clearing and canceled lookup.")
    }

    private static func artwork(width: Int, height: Int) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSColor.systemTeal.setFill()
        NSRect(x: 12, y: 12, width: width - 24, height: height - 24).fill()
        image.unlockFocus()
        return image
    }
}
