import AppKit
import SwiftUI
import ImageIO

@MainActor
private final class CatalogCover: ObservableObject {
    @Published var image: NSImage?
    private static let cache = NSCache<NSURL, NSImage>()
    private var task: Task<Void, Never>?

    init(url: URL?) {
        guard let url else { return }
        if let cached = Self.cache.object(forKey: url as NSURL) { image = cached; return }
        task = Task { [weak self] in
            let thumbnail = await Task.detached(priority: .utility) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil as CGImage? }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 480,
                    kCGImageSourceCreateThumbnailWithTransform: true
                ] as CFDictionary)
            }.value
            guard let self, !Task.isCancelled, let thumbnail else { return }
            let image = NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
            Self.cache.setObject(image, forKey: url as NSURL, cost: thumbnail.width * thumbnail.height * 4)
            Self.cache.totalCostLimit = 32 * 1024 * 1024
            self.image = image
        }
    }
    deinit { task?.cancel() }
}

private struct GameCard: View {
    let game: CatalogGame
    let selected: Bool
    let action: () -> Void
    @StateObject private var cover: CatalogCover

    init(game: CatalogGame, selected: Bool, action: @escaping () -> Void) {
        self.game = game
        self.selected = selected
        self.action = action
        _cover = StateObject(wrappedValue: CatalogCover(url: game.coverURL))
    }
    private var cardHelp: String {
        let coverName = game.coverURL?.lastPathComponent ?? "não disponível"
        return "\(game.title)\n\(game.fileURL.lastPathComponent)\nCapa: \(coverName)"
    }
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.65))
                    if let image = cover.image {
                        Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "opticaldisc").font(.system(size: 35, weight: .ultraLight))
                            Text(game.consoleKey.uppercased()).font(.system(size: 13)).tracking(3)
                        }.foregroundStyle(Theme.ice.opacity(0.5))
                    }
                }
                // Keep one front cover, at a stable size and its console's format.
                // Fit (never stretch or crop) preserves titles and edge artwork.
                .frame(width: game.consoleKey == "ps2" ? 101.5 : 145, height: 145)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.10), lineWidth: 0.5))
                .frame(maxWidth: .infinity)
                Text(game.title).font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .white : Theme.pale.opacity(0.88))
                    .lineLimit(2).frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
            }
            .padding(9)
            .background(selected ? Theme.blue.opacity(0.18) : Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Theme.ice.opacity(0.85) : .white.opacity(0.06), lineWidth: selected ? 1.5 : 1))
            .shadow(color: Theme.blue.opacity(selected ? 0.14 : 0), radius: 6)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
         .accessibilityLabel("Selecionar \(game.title)")
         .accessibilityValue(selected ? "Selecionado" : "")
         .help(cardHelp)
    }
}

struct GameCatalogView: View {
    let console: Console
    @ObservedObject var model: LauncherModel
    @ObservedObject var catalog: GameCatalog
    private var games: [CatalogGame] { catalog.games[console.rawValue] ?? [] }
    private var loading: Bool { catalog.loading.contains(console.rawValue) }
    private var selection: CatalogGame? { model.selectedGame }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: Theme.catalogColumns)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 15) {
                if let logo = Theme.images["Logo"] {
                    Image(nsImage: logo).resizable().scaledToFit().frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityLabel("Logo PlayStation")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("PS1/2  /  \(console.badge)").font(.system(size: 10, weight: .medium)).tracking(2).foregroundStyle(Theme.ice.opacity(0.65))
                    Text("Jogos \(console.badge)").font(.system(size: 25, weight: .regular, design: .rounded)).foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text("\(games.count) jogos · \(console.emulator)").font(.system(size: 13)).foregroundStyle(Theme.pale)
                    Text("Catálogo do Extreme SSD").font(.system(size: 10)).tracking(0.3).foregroundStyle(Theme.pale.opacity(0.65))
                }
            }.padding(.top, 35).padding(.bottom, 22)
            if let error = catalog.errors[console.rawValue] {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(2).padding(.bottom, 10)
            }
            if loading && games.isEmpty {
                VStack(spacing: 15) {
                    ProgressView()
                    Text("Lendo jogos e capas de \(console.badge)…").foregroundStyle(Theme.pale)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if games.isEmpty {
                VStack(spacing: 15) {
                    Image(systemName: "externaldrive").font(.system(size: 38, weight: .ultraLight)).foregroundStyle(Theme.ice)
                    Text("Nenhum jogo disponível neste console").font(.system(size: 20, weight: .light))
                    Text("Conecte o Extreme SSD e use △ ou T para atualizar.\nApenas imagens prontas para abrir entram no catálogo; arquivos ZIP, RAR e 7z ficam de fora.")
                        .font(.system(size: 12)).multilineTextAlignment(.center).foregroundStyle(Theme.pale.opacity(0.6))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(games) { game in
                                GameCard(game: game, selected: selection?.id == game.id) { model.selectGame(game) }
                                    .id(game.coverURL)
                                    .id(game.id)
                            }
                        }.padding(5)
                    }.scrollIndicators(.visible)
                     .onChange(of: selection?.id) { _, id in
                         if let id {
                             withAnimation(.easeOut(duration: model.reduceMotion ? 0 : 0.18)) { proxy.scrollTo(id, anchor: .center) }
                         }
                     }
                }.frame(maxHeight: .infinity)
            }
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selection?.title ?? "Selecione um jogo")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                    Text(selection.map { $0.fileURL.pathExtension.uppercased() + " · " + console.emulator } ?? "X / Enter abre o jogo selecionado")
                        .font(.system(size: 11)).foregroundStyle(Theme.pale.opacity(0.65))
                }
                Spacer()
                if loading { ProgressView().controlSize(.small) }
                Button { model.confirm() } label: {
                    Label("Abrir no \(console.emulator)", systemImage: "play.fill").font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Theme.blue.opacity(0.32), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.ice.opacity(0.4)))
                }.buttonStyle(.plain).foregroundStyle(.white).disabled(selection == nil || loading)
                 .accessibilityLabel("Abrir jogo selecionado no \(console.emulator)")
            }.padding(.vertical, 16)
            Rectangle().fill(Theme.ice.opacity(0.15)).frame(height: 1)
            HStack(spacing: 26) {
                Button { model.confirm() } label: { hint("×", "Abrir jogo", "Enter", Theme.ice) }.disabled(selection == nil || loading)
                Button { model.back() } label: { hint("○", "Consoles", "Esc", Color(red: 0.92, green: 0.49, blue: 0.51)) }
                Button { model.toggleFullscreen?() } label: { hint("□", model.fullscreen ? "Janela" : "Tela cheia", "F", Color(red: 0.83, green: 0.58, blue: 0.80)) }
                Button { model.showCatalog() } label: { hint("△", "Atualizar \(console.badge)", "T", Color(red: 0.4, green: 0.9, blue: 0.68)) }.disabled(loading)
                Spacer()
                Label("Selecionar", systemImage: "arrow.up.and.down.and.arrow.left.and.right").font(.system(size: 11)).foregroundStyle(Theme.pale.opacity(0.5))
            }.buttonStyle(.plain).padding(.top, 15).padding(.bottom, 24)
        }.padding(.horizontal, 63).frame(width: 1100, height: 700)
         .background(Theme.background.opacity(0.92))
    }
    private func hint(_ symbol: String, _ text: String, _ key: String, _ color: Color) -> some View {
        HStack(spacing: 7) {
            Text(symbol).font(.system(size: 21, weight: .regular)).foregroundStyle(color)
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.pale)
            Text(key).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.pale.opacity(0.55))
        }.contentShape(Rectangle())
    }
}
