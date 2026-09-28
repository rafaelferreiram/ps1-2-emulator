import AppKit
import SwiftUI
import ImageIO

@MainActor
final class NowPlayingArtwork: ObservableObject {
    @Published private(set) var image: NSImage?

    func load(path: String, source: CatalogSource?) async {
        image = nil
        guard let source else { return }
        let thumbnail = await Task.detached(priority: .utility) {
            guard let url = CatalogScanner.coverForLoadedGame(path: path, source: source),
                  let artwork = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil as CGImage? }
            return CGImageSourceCreateThumbnailAtIndex(artwork, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 108,
                kCGImageSourceCreateThumbnailWithTransform: true
            ] as CFDictionary)
        }.value
        // A late lookup must not put the previous game's cover back on screen.
        guard !Task.isCancelled, let thumbnail else { return }
        image = NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
    }
}

/// Resolve only a verified loaded disc, independently of the catalog selection.
/// The task runs once per game change, never once per uptime tick.
struct NowPlayingGameView: View {
    let consoleKey: String
    let title: String
    let gamePath: String
    @StateObject private var artwork = NowPlayingArtwork()

    private var identity: String { consoleKey + ":" + gamePath }

    var body: some View {
        NowPlayingGameLabel(consoleKey: consoleKey, title: title, image: artwork.image)
            .help(gamePath)
            .task(id: identity) {
                await artwork.load(path: gamePath, source: CatalogSource.installed(consoleKey))
            }
    }
}

/// Kept separate from loading so compact layout and missing-art states are testable.
struct NowPlayingGameLabel: View {
    let consoleKey: String
    let title: String
    let image: NSImage?

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 3).fill(.black.opacity(0.45))
                if let image {
                    Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                } else {
                    Image(systemName: "opticaldisc").font(.system(size: 15, weight: .light))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .frame(width: consoleKey == "ps2" ? 25 : 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white.opacity(0.16), lineWidth: 0.5))
            .accessibilityLabel("Capa de \(title)")
            .accessibilityValue(image == nil ? "Indisponível" : "Carregada")
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                    .lineLimit(1).truncationMode(.middle)
                Text("Jogo carregado · pode estar pausado").font(.system(size: 10))
                    .foregroundStyle(Color(red: 0.79, green: 0.84, blue: 0.95).opacity(0.6))
                    .lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(height: 36)
    }
}
