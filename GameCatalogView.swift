import AppKit
import SwiftUI

@MainActor
private final class CatalogCover: ObservableObject {
    @Published var image: NSImage?
    private var requestID = UUID()

    func load(_ url: URL?, snapshotID: String?) async {
        let request = UUID()
        requestID = request
        image = nil
        guard let url, let snapshotID, !Task.isCancelled else { return }
        // Bounded thumbnails stay shared between catalog and menu at any window size.
        let thumbnail = await CoverImageCache.shared.image(at: url, maxPixelSize: 320, snapshotID: snapshotID)
        guard requestID == request, !Task.isCancelled, let thumbnail else { return }
        image = NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
    }
}

private struct CoverRequest: Hashable {
    let url: URL?
    let snapshotID: String?
}

private struct CatalogViewport: Hashable {
    let width: CGFloat
    let height: CGFloat
    let columns: Int
}

private struct GameCard: View {
    let game: CatalogGame
    let selected: Bool
    let snapshotID: String?
    let coverHeight: CGFloat
    let action: () -> Void
    @StateObject private var cover = CatalogCover()

    init(game: CatalogGame, selected: Bool, snapshotID: String?, coverHeight: CGFloat, action: @escaping () -> Void) {
        self.game = game
        self.selected = selected
        self.snapshotID = snapshotID
        self.coverHeight = coverHeight
        self.action = action
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
                // Keep one front cover, at the responsive size and its console's format.
                // Fit (never stretch or crop) preserves titles and edge artwork.
                .frame(width: game.consoleKey == "ps2" ? coverHeight * 0.7 : coverHeight, height: coverHeight)
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
         .task(id: CoverRequest(url: game.coverURL, snapshotID: snapshotID)) {
             await cover.load(game.coverURL, snapshotID: snapshotID)
         }
    }
}

struct GameCatalogView: View {
    let console: Console
    let layout: LauncherLayout
    @ObservedObject var model: LauncherModel
    @ObservedObject var catalog: GameCatalog
    private var games: [CatalogGame] { catalog.games[console.rawValue] ?? [] }
    private var loading: Bool { catalog.loading.contains(console.rawValue) }
    private var selection: CatalogGame? { model.selectedGame }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 16), count: layout.catalogColumns)
    }
    private var viewport: CatalogViewport {
        CatalogViewport(width: layout.canvasSize.width, height: layout.canvasSize.height,
                        columns: layout.catalogColumns)
    }

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
                Button { model.showLibrarySettings() } label: {
                    Label("Pastas de jogos", systemImage: "folder.badge.gearshape")
                        .font(.system(size: 11)).foregroundStyle(Theme.ice)
                }.buttonStyle(.plain)
                VStack(alignment: .trailing, spacing: 5) {
                    Text("\(games.count) jogos · \(console.emulator)").font(.system(size: 13)).foregroundStyle(Theme.pale)
                    Text(model.isStorageAvailable(for: console) ? "Última carga completa · △/T atualiza" : "Catálogo offline · Conecte o disco para jogar")
                        .font(.system(size: 10)).tracking(0.3).foregroundStyle(Theme.pale.opacity(0.65))
                }
            }.padding(.top, 35).padding(.bottom, 22)
            if let error = catalog.errors[console.rawValue] {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(2).padding(.bottom, 10)
            }
            if loading && games.isEmpty {
                VStack(spacing: 15) {
                    ProgressView()
                    Text("Carregando catálogo de \(console.badge)…").foregroundStyle(Theme.pale)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if games.isEmpty {
                VStack(spacing: 15) {
                    Image(systemName: "externaldrive").font(.system(size: 38, weight: .ultraLight)).foregroundStyle(Theme.ice)
                    Text("Nenhum jogo salvo neste catálogo").font(.system(size: 20, weight: .light))
                    Text("Escolha uma pasta em Pastas de jogos, ou conecte o disco configurado e use △/T.\nO catálogo mostra a última lista salva; os arquivos são verificados ao abrir o jogo.")
                        .font(.system(size: 12)).multilineTextAlignment(.center).foregroundStyle(Theme.pale.opacity(0.6))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(games) { game in
                                GameCard(game: game, selected: selection?.id == game.id,
                                         snapshotID: catalog.snapshotIDs[console.rawValue],
                                         coverHeight: layout.catalogCoverHeight) { model.selectGame(game) }
                                    .id(game.id)
                            }
                        }.padding(5)
                    }.scrollIndicators(.visible)
                     .onChange(of: selection?.id) { _, id in
                         if let id {
                             withAnimation(.easeOut(duration: model.reduceMotion ? 0 : 0.18)) { proxy.scrollTo(id, anchor: .center) }
                         }
                     }
                     .task(id: viewport) {
                         // Wait for the new grid geometry before scrolling. The
                         // task is cancelled if another resize supersedes it.
                         await Task.yield()
                         guard !Task.isCancelled, let id = selection?.id else { return }
                         proxy.scrollTo(id, anchor: .center)
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
                HStack(spacing: 8) {
                    Text("PS").font(.system(size: 12, weight: .black)).foregroundStyle(Theme.ice)
                    Text("Início").font(.system(size: 12)).foregroundStyle(Theme.pale.opacity(0.9))
                }.help("Botão PlayStation do DualSense volta ao menu da central, mesmo com o emulador na frente")
                Spacer()
                Label("Selecionar", systemImage: "arrow.up.and.down.and.arrow.left.and.right").font(.system(size: 11)).foregroundStyle(Theme.pale.opacity(0.5))
                    .help("Setas, direcional ou analógico esquerdo; segure o analógico para percorrer os jogos")
            }.buttonStyle(.plain).padding(.top, 15).padding(.bottom, 24)
        }.padding(.horizontal, layout.horizontalPadding)
         .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
         .background(Theme.background.opacity(0.92))
         .onAppear { model.catalogColumns = layout.catalogColumns }
         .onChange(of: layout.catalogColumns) { _, count in model.catalogColumns = count }
    }
    private func hint(_ symbol: String, _ text: String, _ key: String, _ color: Color) -> some View {
        HStack(spacing: 7) {
            Text(symbol).font(.system(size: 21, weight: .regular)).foregroundStyle(color)
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.pale)
            Text(key).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.pale.opacity(0.55))
        }.contentShape(Rectangle())
    }
}
