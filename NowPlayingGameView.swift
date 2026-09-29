import AppKit
import SwiftUI

@MainActor
final class NowPlayingArtwork: ObservableObject {
    @Published private(set) var image: NSImage?
    private let catalogCache: CatalogCache
    private let coverCache: CoverImageCache
    private var requestID = UUID()

    init(catalogCache: CatalogCache = .shared, coverCache: CoverImageCache = .shared) {
        self.catalogCache = catalogCache
        self.coverCache = coverCache
    }

    func load(path: String, source: CatalogSource?) async {
        let request = UUID()
        requestID = request
        image = nil
        guard let source, !Task.isCancelled,
              let cover = await catalogCache.cachedArtworkForLoadedGame(path: path, source: source),
              requestID == request, !Task.isCancelled else { return }
        let thumbnail = await coverCache.image(at: cover.url, maxPixelSize: 108, snapshotID: cover.snapshotID)
        // A late lookup must not put the previous game's cover back on screen.
        guard requestID == request, !Task.isCancelled, let thumbnail else { return }
        let display = CatalogScanner.displayImage(thumbnail)
        image = NSImage(cgImage: display, size: NSSize(width: display.width, height: display.height))
    }
}

/// Resolve only a verified loaded disc, independently of the catalog selection.
/// The task runs on game/catalog revision changes, never once per uptime tick.
struct NowPlayingGameView: View {
    let consoleKey: String
    let title: String
    let gamePath: String
    var revision: Int = 0
    var source: CatalogSource? = nil
    @StateObject private var artwork = NowPlayingArtwork()

    private var identity: String {
        consoleKey + ":" + gamePath + ":" + String(revision) + ":" + (source?.root.path ?? "<none>")
    }

    var body: some View {
        NowPlayingGameLabel(consoleKey: consoleKey, title: title, image: artwork.image)
            .help(gamePath)
            .task(id: identity) {
                await artwork.load(path: gamePath, source: source)
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
