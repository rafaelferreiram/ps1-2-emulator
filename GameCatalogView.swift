import AppKit
import SwiftUI

struct CatalogReloadButton: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var catalog: GameCatalog

    private var console: Console { model.catalogConsole ?? model.selected }
    private var loading: Bool { catalog.loading.contains(console.rawValue) }

    var body: some View {
        Button { model.reloadCatalog() } label: {
            HStack(spacing: 6) {
                if loading {
                    ProgressView().controlSize(.small).tint(Theme.ice)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
                Text(loading ? "Atualizando" : "Atualizar")
                Text("△").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(red: 0.4, green: 0.9, blue: 0.68).opacity(loading ? 0.35 : 0.9))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.ice.opacity(loading ? 0.75 : 1))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Theme.blue.opacity(loading ? 0.28 : model.catalogCommand == .reload ? 0.45 : 0.18), in: Capsule())
            .overlay(Capsule().stroke(Theme.ice.opacity(model.catalogCommand == .reload ? 0.95 : loading ? 0.5 : 0.34), lineWidth: model.catalogCommand == .reload ? 1.6 : 1))
        }
        .buttonStyle(.plain)
        .disabled(loading)
        .help("Atualizar jogos e capas do \(console.badge). R, △ no catálogo ou R2 + L2.")
        .accessibilityLabel(loading ? "Atualizando catálogo do \(console.badge)" : "Atualizar catálogo do \(console.badge)")
    }
}

@MainActor
private final class CatalogCover: ObservableObject {
    @Published var image: NSImage?
    private var requestID = UUID()

    func load(_ url: URL?, snapshotID: String?, pixels: Int) async {
        let request = UUID()
        requestID = request
        guard let url, let snapshotID, !Task.isCancelled else {
            image = nil
            return
        }
        // Keep the current cover on screen until the reloaded thumbnail arrives.
        let thumbnail = await CoverImageCache.shared.image(at: url, maxPixelSize: pixels, snapshotID: snapshotID)
        guard requestID == request, !Task.isCancelled else { return }
        if let thumbnail {
            let display = CatalogScanner.displayImage(thumbnail)
            image = NSImage(cgImage: display, size: NSSize(width: display.width, height: display.height))
        } else {
            image = nil
        }
    }
}

private struct CoverRequest: Hashable {
    let url: URL?
    let snapshotID: String?
    let pixels: Int
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
    let scale: CGFloat
    let favorite: Bool
    let recent: Bool
    let action: () -> Void
    @StateObject private var cover = CatalogCover()
    @Environment(\.displayScale) private var displayScale

    init(game: CatalogGame, selected: Bool, snapshotID: String?, coverHeight: CGFloat, scale: CGFloat,
         favorite: Bool, recent: Bool, action: @escaping () -> Void) {
        self.game = game
        self.selected = selected
        self.snapshotID = snapshotID
        self.coverHeight = coverHeight
        self.scale = scale
        self.favorite = favorite
        self.recent = recent
        self.action = action
    }
    private var console: Console { Console(rawValue: game.consoleKey) ?? .ps2 }
    private var palette: ConsolePalette { .forConsole(console) }
    private var pixels: Int {
        let needed = Int(ceil(coverHeight * max(1, displayScale) * scale))
        return [320, 480, 640, 1024].first { $0 >= needed } ?? 1024
    }
    private var cardHelp: String {
        let coverName = game.coverURL?.lastPathComponent ?? "indisponível"
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
                        }.foregroundStyle(palette.highlight.opacity(0.5))
                    }
                }
                // Keep one front cover, at the responsive size and its console's format.
                // Fit (never stretch or crop) preserves titles and edge artwork.
                .frame(width: game.consoleKey == "ps2" ? coverHeight * 0.7 : coverHeight, height: coverHeight)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(console == .ps1 ? 0.24 : 0.10), lineWidth: console == .ps1 ? 2 : 0.5))
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(console == .ps1 ? 0.12 : 0.04)).frame(width: console == .ps1 ? 4 : 2)
                }
                .frame(maxWidth: .infinity)
                HStack(alignment: .top, spacing: 5) {
                    Text(game.title).font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? .white : palette.text.opacity(0.88))
                        .lineLimit(2).frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
                    if favorite {
                        Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(palette.highlight)
                            .accessibilityLabel("Favorito")
                    } else if recent {
                        Image(systemName: "clock").font(.system(size: 10)).foregroundStyle(palette.text.opacity(0.55))
                            .accessibilityLabel("Aberto recentemente")
                    }
                }
            }
            .padding(9)
            .background(selected ? palette.accent.opacity(0.18) : Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? palette.highlight.opacity(0.85) : .white.opacity(0.06), lineWidth: selected ? 1.5 : 1))
            .overlay(alignment: .topLeading) {
                if selected {
                    Text("P1").font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(palette.background).padding(.horizontal, 5).padding(.vertical, 3)
                        .background(palette.highlight, in: RoundedRectangle(cornerRadius: 3)).offset(x: 5, y: 5)
                }
            }
            .shadow(color: palette.accent.opacity(selected ? 0.14 : 0), radius: 6)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
         .accessibilityLabel("Selecionar \(game.title)")
         .accessibilityValue(selected ? "Selecionado" : "")
         .help(cardHelp)
         .task(id: CoverRequest(url: game.coverURL, snapshotID: snapshotID, pixels: pixels)) {
             await cover.load(game.coverURL, snapshotID: snapshotID, pixels: pixels)
         }
    }
}

struct GameCatalogView: View {
    let console: Console
    let layout: LauncherLayout
    @ObservedObject var model: LauncherModel
    @ObservedObject var catalog: GameCatalog
    @FocusState private var searchFocused: Bool
    private var palette: ConsolePalette { .forConsole(console) }
    private var preferences: PersonalLibraryState { model.libraryState(for: console) }
    private var games: [CatalogGame] { catalog.games[console.rawValue] ?? [] }
    private var filteredGames: [CatalogGame] { model.filteredCatalogGames(for: console) }
    private var loading: Bool { catalog.loading.contains(console.rawValue) }
    private var selection: CatalogGame? { model.selectedGame }
    private var columnCount: Int {
        preferences.density == .compact ? min(12, layout.catalogColumns + 1) : layout.catalogColumns
    }
    private var coverHeight: CGFloat {
        let cardWidth = (layout.contentWidth - 10 - CGFloat(columnCount - 1) * 16) / CGFloat(columnCount)
        return max(90, cardWidth - 18)
    }
    private var query: Binding<String> {
        Binding(get: { preferences.query }, set: { model.setCatalogQuery($0) })
    }
    private var canPlay: Bool { selection != nil && model.selectedCatalogFolderID == nil && model.launching == nil }
    private var playTitle: String { model.isSelectedGameRunning ? "Voltar ao jogo" : "Jogar" }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 16), count: columnCount)
    }
    private var viewport: CatalogViewport {
        CatalogViewport(width: layout.canvasSize.width, height: layout.canvasSize.height,
                        columns: columnCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 15) {
                if let logo = Theme.images["Logo"] {
                    Image(nsImage: logo).resizable().scaledToFit().frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityLabel("PlayStation logo")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("PLAYSTATION RETRO  /  \(console.badge)").font(.system(size: 10, weight: .medium)).tracking(2).foregroundStyle(palette.highlight.opacity(0.65))
                    Text("Biblioteca \(console.badge)").font(.system(size: 25, weight: .regular, design: .rounded)).foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text(filteredGames.count == games.count ? "\(games.count) jogos" : "\(filteredGames.count) de \(games.count) jogos")
                        .font(.system(size: 13)).foregroundStyle(palette.text)
                    HStack(spacing: 5) {
                        if loading { ProgressView().controlSize(.mini).tint(palette.highlight) }
                        Text(loading ? "Buscando novidades…" : model.isStorageAvailable(for: console) ? "Sua coleção está pronta" : "Catálogo offline · conecte o disco para jogar")
                            .font(.system(size: 10)).tracking(0.3).foregroundStyle(palette.text.opacity(0.65))
                    }
                }
            }.padding(.top, 27).padding(.bottom, 17)
            if let error = catalog.errors[console.rawValue] {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(2).padding(.bottom, 10)
            }
            catalogToolbar.padding(.bottom, 12)
            if loading && games.isEmpty {
                VStack(spacing: 15) {
                    ProgressView()
                    Text("Carregando a biblioteca \(console.badge)…").foregroundStyle(palette.text)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if games.isEmpty {
                VStack(spacing: 15) {
                    Image(systemName: "externaldrive").font(.system(size: 38, weight: .ultraLight)).foregroundStyle(palette.highlight)
                    Text("Sua biblioteca começa aqui").font(.system(size: 20, weight: .light))
                    Text("Escolha uma pasta em Local dos jogos ou conecte o disco configurado e atualize com △.\nA coleção fica disponível offline; o arquivo do jogo é verificado ao jogar.")
                        .font(.system(size: 12)).multilineTextAlignment(.center).foregroundStyle(palette.text.opacity(0.7))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredGames.isEmpty {
                VStack(spacing: 13) {
                    Image(systemName: preferences.filter == .favorites ? "star" : preferences.filter == .recent ? "clock" : "magnifyingglass")
                        .font(.system(size: 35, weight: .ultraLight)).foregroundStyle(palette.highlight)
                    Text(preferences.query.isEmpty ? (preferences.filter == .favorites ? "Seus favoritos aparecem aqui" : "Seus jogos recentes aparecem aqui") : "Nenhum jogo encontrado")
                        .font(.system(size: 19, weight: .light))
                    Text(preferences.filter == .recent && preferences.query.isEmpty ? "Jogos abertos pela central entram nesta lista. Isso não indica progresso ou saves." : "Altere o filtro ou a busca. Sua coleção continua salva.")
                        .font(.system(size: 12)).foregroundStyle(palette.text.opacity(0.7))
                    Button("Mostrar todos os jogos") { model.setCatalogQuery(""); model.setCatalogFilter(.all) }
                        .buttonStyle(.plain).foregroundStyle(palette.highlight)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(sections) { section in
                                VStack(alignment: .leading, spacing: 10) {
                                    if section.collapsible { sectionHeader(section).id("section:" + section.id) }
                                    if !section.collapsed {
                                        let cards = cards(in: section)
                                        if cards.isEmpty {
                                            Text("Pasta vazia. Organize seus jogos em Pastas.")
                                                .font(.system(size: 12)).foregroundStyle(palette.text.opacity(0.55))
                                                .padding(.leading, 28).padding(.bottom, 4)
                                        } else {
                                            LazyVGrid(columns: columns, spacing: 16) {
                                                ForEach(cards) { game in
                                                    GameCard(game: game, selected: selection?.id == game.id && model.selectedCatalogFolderID == nil && model.catalogCommand == nil,
                                                             snapshotID: catalog.snapshotIDs[console.rawValue],
                                                             coverHeight: coverHeight, scale: layout.scale,
                                                             favorite: preferences.favoriteIDs.contains(game.id),
                                                             recent: preferences.lastLaunched[game.id] != nil) {
                                                        searchFocused = false
                                                        model.selectGame(game)
                                                    }
                                                        .id(game.id)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }.padding(5).padding(.bottom, 8)
                    }.scrollIndicators(.visible)
                     .onChange(of: selection?.id) { _, id in
                         if let id {
                             withAnimation(.easeOut(duration: model.reduceMotion ? 0 : 0.18)) { proxy.scrollTo(id, anchor: .center) }
                         }
                     }
                     .onChange(of: model.selectedCatalogFolderID) { _, id in
                         if let id {
                             withAnimation(.easeOut(duration: model.reduceMotion ? 0 : 0.18)) { proxy.scrollTo("section:" + id, anchor: .center) }
                         }
                     }
                     .task(id: viewport) {
                         // Wait for the new grid geometry before scrolling. The
                         // task is cancelled if another resize supersedes it.
                         await Task.yield()
                         guard !Task.isCancelled else { return }
                         if let id = model.selectedCatalogFolderID { proxy.scrollTo("section:" + id, anchor: .center) }
                         else if let id = selection?.id { proxy.scrollTo(id, anchor: .center) }
                     }
                }.frame(maxHeight: .infinity)
            }
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.selectedCatalogFolderID.flatMap { id in sections.first { $0.id == id }?.title } ?? selection?.title ?? "Selecione um jogo")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                    Text(selectionDetail)
                        .font(.system(size: 11)).foregroundStyle(palette.text.opacity(0.65))
                }
                Spacer()
                Button {
                    searchFocused = false
                    if let game = selection { model.launchGame(game) }
                } label: {
                    Label(playTitle, systemImage: model.isSelectedGameRunning ? "arrow.uturn.forward" : "play.fill").font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(palette.accent.opacity(0.32), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.highlight.opacity(0.4)))
                }.buttonStyle(.plain).foregroundStyle(.white).disabled(!canPlay)
                 .accessibilityLabel("\(playTitle): \(selection?.title ?? "nenhum jogo selecionado")")
            }.padding(.vertical, 13)
            Rectangle().fill(palette.highlight.opacity(0.15)).frame(height: 1)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 22) {
                    Button { model.confirm() } label: { hint("×", model.catalogCommand == nil && model.selectedCatalogFolderID == nil ? playTitle : "Confirmar", "Enter", palette.highlight) }.disabled(model.catalogCommand == nil && model.selectedCatalogFolderID == nil && !canPlay)
                    Button { model.back() } label: { hint("○", model.catalogCommand == nil && model.selectedCatalogFolderID == nil ? "Consoles" : "Voltar", "Esc", Color(red: 0.92, green: 0.49, blue: 0.51)) }
                    Button { model.toggleFullscreen?() } label: { hint("□", model.fullscreen ? "Janela" : "Tela cheia", "F", Color(red: 0.83, green: 0.58, blue: 0.80)) }
                    Button { model.reloadCatalog() } label: { hint("△", "Atualizar", "R", Color(red: 0.4, green: 0.9, blue: 0.68)) }
                        .disabled(loading)
                        .help("Atualizar jogos e capas. Também R2 + L2 ou R.")
                    Spacer(minLength: 0)
                }
                HStack(spacing: 22) {
                    legend("L1", "A–Z", palette.highlight)
                    legend("R1", "Z–A", palette.highlight)
                    legend("OPTIONS", "Pastas", palette.text)
                    legend("↑", "Opções", palette.highlight)
                    legend("↓", "Jogos", palette.highlight)
                    Spacer(minLength: 0)
                }
            }.buttonStyle(.plain).padding(.top, 12).padding(.bottom, 18)
        }.padding(.horizontal, layout.horizontalPadding)
         .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
         .background(palette.background.opacity(0.35))
         .overlay {
             if model.showingCatalogFolders {
                 CatalogFoldersPanel(console: console, model: model)
             }
         }
         .onAppear {
             model.catalogColumns = columnCount
             model.alignCatalogSelection()
         }
         .onChange(of: columnCount) { _, count in model.catalogColumns = count }
         .onChange(of: model.catalogOrganizationToken) { _, _ in model.alignCatalogSelection() }
    }
    private var selectionDetail: String {
        if model.selectedCatalogFolderID != nil { return "× abre ou recolhe esta pasta · ↓ navega pela coleção" }
        guard let game = selection else { return "Use o direcional ou o analógico para escolher" }
        if model.isSelectedGameRunning { return "Sessão aberta no \(console.emulator)" }
        if let date = preferences.lastLaunched[game.id] {
            return "Aberto pela central em " + date.formatted(date: .abbreviated, time: .shortened)
        }
        return console.name + " · " + game.fileURL.pathExtension.uppercased()
    }
    private var sections: [CatalogSection] { model.catalogSections(for: console) }
    private var gamesByID: [String: CatalogGame] {
        Dictionary(games.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
    private func cards(in section: CatalogSection) -> [CatalogGame] {
        section.games.compactMap { gamesByID[$0.id] }
    }
    private var catalogToolbar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if !preferences.query.isEmpty {
                    commandChip(.clearSearch, "Limpar busca", "", sorting: false) { model.setCatalogQuery("") }
                }
                commandChip(.filter, preferences.filter.title, "↔", sorting: preferences.filter != .all) {
                    model.setCatalogFilter(preferences.filter.next)
                }
                commandChip(.favorite, selection.map { preferences.favoriteIDs.contains($0.id) } == true ? "Favoritado" : "Favoritar", "☆", sorting: selection.map { preferences.favoriteIDs.contains($0.id) } == true) {
                    model.toggleSelectedFavorite()
                }.disabled(selection == nil || model.selectedCatalogFolderID != nil)
                commandChip(.density, preferences.density.title, "▦", sorting: preferences.density == .compact) {
                    model.toggleCatalogDensity()
                }
                Spacer(minLength: 12)
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(palette.text.opacity(0.6))
                    TextField("Buscar jogos", text: query)
                        .textFieldStyle(.plain).focused($searchFocused)
                        .onSubmit { searchFocused = false; model.alignCatalogSelection() }
                        .accessibilityLabel("Buscar jogos do \(console.badge)")
                    if !preferences.query.isEmpty {
                        Button { model.setCatalogQuery("") } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(palette.text.opacity(0.6))
                        }.buttonStyle(.plain).accessibilityLabel("Limpar busca")
                    }
                }
                .font(.system(size: 12)).foregroundStyle(palette.text)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .frame(width: 230)
                .background(Color.black.opacity(0.25), in: Capsule())
                .overlay(Capsule().stroke(palette.highlight.opacity(searchFocused ? 0.8 : 0.2), lineWidth: 1))
            }
            HStack(spacing: 6) {
                commandChip(.sortAZ, "A–Z", "L1", sorting: model.catalogSortAscending && preferences.filter != .recent) { model.setCatalogSort(ascending: true) }
                commandChip(.sortZA, "Z–A", "R1", sorting: !model.catalogSortAscending && preferences.filter != .recent) { model.setCatalogSort(ascending: false) }
                commandChip(.folders, "Pastas", "OPTIONS", sorting: false) { model.toggleCatalogFolders() }
                if model.availableCatalogCommands.contains(.minimize) {
                    commandChip(.minimize, "Recolher/abrir", "C", sorting: false) { model.toggleSectionOfSelection() }
                }
                commandChip(.reload, loading ? "Atualizando…" : "Atualizar", "△", sorting: false) { model.reloadCatalog() }.disabled(loading)
                commandChip(.library, "Local dos jogos", "", sorting: false) { model.showLibrarySettings() }
                if model.availableCatalogCommands.contains(.session) {
                    commandChip(.session, "Sessão", "", sorting: false) { model.showSessionMenu() }
                }
                commandChip(.experience, "Experiência", "", sorting: false) { model.showExperienceSettings() }
                Spacer(minLength: 0)
            }
        }
    }
    private func commandChip(_ command: CatalogCommand, _ title: String, _ key: String, sorting: Bool, action: @escaping () -> Void) -> some View {
        let focused = model.catalogCommand == command
        return Button {
            searchFocused = false
            model.catalogCommand = command
            action()
        } label: {
            HStack(spacing: 6) {
                Text(title)
                if !key.isEmpty {
                    Text(key).font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.text.opacity(focused || sorting ? 0.9 : 0.45))
                }
            }
            .font(.system(size: 11, weight: focused || sorting ? .semibold : .regular))
            .foregroundStyle(focused || sorting ? .white : palette.text.opacity(0.8))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(palette.accent.opacity(focused ? 0.55 : sorting ? 0.32 : 0.08), in: Capsule())
            .overlay(Capsule().stroke(palette.highlight.opacity(focused ? 1 : sorting ? 0.45 : 0.22), lineWidth: focused ? 1.6 : 1))
        }
        .buttonStyle(.plain)
        .help(commandHelp(command))
        .accessibilityLabel(focused ? "\(title), selecionado" : title)
    }
    private func commandHelp(_ command: CatalogCommand) -> String {
        switch command {
        case .sortAZ: return "Ordem A–Z. L1, A ou ↑ e ×. Recentes mantém a ordem de abertura."
        case .sortZA: return "Ordem Z–A. R1, Z ou ↑ e ×. Recentes mantém a ordem de abertura."
        case .folders: return "Pastas virtuais. OPTIONS, P ou ↑ e ×. Os arquivos não são movidos."
        case .minimize: return "Abre ou recolhe a pasta selecionada. C ou ↑ e ×."
        case .reload: return "Atualiza jogos e capas. △, R, R2 + L2 ou ↑ e ×."
        case .library: return "Escolha onde estão os jogos, no Mac ou em um disco. ↑ e ×."
        case .clearSearch: return "Limpa a busca atual, inclusive pelo controle: ↑ e ×."
        case .filter: return "Alterna Todos, Favoritos e Recentes. ↑ e ×. A busca também se aplica ao filtro."
        case .favorite: return "Marca ou desmarca o jogo selecionado como favorito nesta biblioteca. ↑ e ×."
        case .density: return "Alterna capas confortáveis ou compactas. ↑ e ×."
        case .session: return "Opções da sessão aberta no emulador. ↑ e ×."
        case .experience: return "Animação de início, sons e preferências da experiência. ↑ e ×."
        }
    }
    private func legend(_ symbol: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Text(symbol).font(.system(size: symbol.count > 2 ? 10 : 13, weight: .bold, design: .monospaced)).foregroundStyle(color)
            Text(text).font(.system(size: 12)).foregroundStyle(palette.text)
        }
    }
    private func sectionHeader(_ section: CatalogSection) -> some View {
        let active = model.selectedCatalogFolderID == section.id
        return Button {
            searchFocused = false
            model.selectCatalogSection(section.id)
            model.toggleCatalogSection(section.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.highlight)
                    .frame(width: 14)
                Image(systemName: section.isLibrary ? "square.stack" : "folder.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.highlight.opacity(active ? 1 : 0.8))
                Text(section.isLibrary ? "Biblioteca" : section.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                Text("\(section.games.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.text.opacity(0.65))
                if active { Text("P1").font(.system(size: 10, weight: .black, design: .monospaced)).foregroundStyle(palette.highlight) }
                Rectangle().fill(palette.highlight.opacity(active ? 0.75 : 0.22)).frame(height: 1)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.collapsed ? "Abrir \(section.title)" : "Recolher \(section.title)")
        .help(section.collapsed ? "Mostra os jogos desta pasta" : "Recolhe os jogos desta pasta")
    }
    private func hint(_ symbol: String, _ text: String, _ key: String, _ color: Color) -> some View {
        HStack(spacing: 7) {
            Text(symbol).font(.system(size: 21, weight: .regular)).foregroundStyle(color)
            Text(text).font(.system(size: 12)).foregroundStyle(palette.text)
            Text(key).font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.text.opacity(0.55))
        }.contentShape(Rectangle())
    }
}

private struct CatalogFoldersPanel: View {
    let console: Console
    @ObservedObject var model: LauncherModel
    @FocusState private var nameFocused: Bool
    private var palette: ConsolePalette { .forConsole(console) }

    private var folders: [CatalogFolder] { model.catalogFolders(for: console) }
    private var highlighted: Int {
        guard !folders.isEmpty else { return 0 }
        return min(max(0, model.catalogFolderIndex), folders.count - 1)
    }
    private var knownIDs: Set<String> {
        Set((model.catalog.games[console.rawValue] ?? []).map(\.id))
    }
    private var currentFolderName: String {
        guard let id = model.selectedGame?.id else { return "Biblioteca" }
        return folders.first { $0.gameIDs.contains(id) }?.name ?? "Biblioteca"
    }
    private var draft: Binding<String> {
        Binding(get: { model.folderDraft }, set: { model.folderDraft = String($0.prefix(24)) })
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.58)
                .contentShape(Rectangle())
                .onTapGesture { model.dismissCatalogFolders() }
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill").font(.system(size: 22)).foregroundStyle(palette.highlight)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Pastas da biblioteca").font(.system(size: 22, weight: .light, design: .rounded))
                        Text("Organizam apenas esta tela. Os arquivos continuam no mesmo local.")
                            .font(.system(size: 12)).foregroundStyle(palette.text)
                    }
                    Spacer()
                    Button("Fechar · Esc") { model.dismissCatalogFolders() }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(palette.highlight)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.selectedGame?.title ?? "Nenhum jogo selecionado")
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                    Text("Em \(currentFolderName)")
                        .font(.system(size: 11)).foregroundStyle(palette.text.opacity(0.75))
                }
                if folders.isEmpty {
                    Text("Crie uma pasta, como Futebol, Corrida ou Luta. Sem pastas, os jogos ficam em uma lista única.")
                        .font(.system(size: 12)).foregroundStyle(palette.text.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(Array(folders.enumerated()), id: \.element.id) { index, folder in
                                folderRow(folder, index: index)
                            }
                        }
                    }.frame(maxHeight: 220)
                }
                if let message = model.catalogFolderMessage {
                    Text(message).font(.system(size: 12)).foregroundStyle(palette.highlight).lineLimit(2)
                }
                HStack(spacing: 10) {
                    TextField("Nome da pasta", text: draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.highlight.opacity(0.28), lineWidth: 1))
                        .focused($nameFocused)
                        .onSubmit { model.confirmCatalogFolder() }
                    Button(model.renamingFolderID == nil ? "Criar" : "Salvar") { model.confirmCatalogFolder() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(palette.accent.opacity(CatalogNames.cleaned(model.folderDraft) == nil ? 0.16 : 0.4), in: RoundedRectangle(cornerRadius: 6))
                        .disabled(CatalogNames.cleaned(model.folderDraft) == nil)
                    if model.renamingFolderID != nil {
                        Button("Cancelar") {
                            model.renamingFolderID = nil
                            model.folderDraft = ""
                        }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(palette.text)
                    }
                }
                HStack(spacing: 8) {
                    ForEach(model.availableFolderActions()) { action in
                        let marked = model.catalogFolderAction == action
                        Button { model.performFolderAction(action) } label: {
                            Text(folderActionTitle(action))
                                .font(.system(size: 12, weight: marked ? .semibold : .regular))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(palette.accent.opacity(marked ? 0.5 : 0.16), in: Capsule())
                                .overlay(Capsule().stroke(palette.highlight.opacity(marked ? 1 : 0.25), lineWidth: marked ? 1.6 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    Text("↑↓ pasta    ←→ ação    × confirma    ○ fecha")
                        .font(.system(size: 10)).foregroundStyle(palette.highlight.opacity(0.7))
                    Spacer()
                }
            }
            .padding(24)
            .frame(width: 680)
            .background(palette.background.opacity(0.96), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(palette.highlight.opacity(0.28), lineWidth: 1))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pastas da biblioteca")
        .onAppear { nameFocused = true }
        .onChange(of: model.renamingFolderID) { _, id in
            if id != nil { nameFocused = true }
        }
    }

    private func folderActionTitle(_ action: CatalogFolderAction) -> String {
        switch action {
        case .place: return "Colocar"
        case .rename: return "Renomear"
        case .delete: return "Excluir pasta"
        case .remove: return "Retirar da pasta"
        case .create: return model.renamingFolderID == nil ? "Criar" : "Salvar"
        }
    }

    private func folderRow(_ folder: CatalogFolder, index: Int) -> some View {
        let marked = index == highlighted
        let holdsGame = model.selectedGame.map { folder.gameIDs.contains($0.id) } ?? false
        let count = folder.gameIDs.filter { knownIDs.contains($0) }.count
        return HStack(spacing: 10) {
            Rectangle().fill(marked ? palette.highlight : Color.clear).frame(width: 3)
            Button { model.catalogFolderIndex = index } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name).font(.system(size: 14, weight: marked ? .semibold : .regular))
                        .foregroundStyle(.white).lineLimit(1)
                    Text(holdsGame ? "O jogo selecionado está nesta pasta" : (count == 1 ? "1 jogo" : "\(count) jogos"))
                        .font(.system(size: 11)).foregroundStyle(palette.text.opacity(0.7))
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            Button(holdsGame ? "Nesta pasta" : "Colocar") {
                model.catalogFolderIndex = index
                if !holdsGame { model.placeSelectedGame(in: folder.id) }
            }
            .disabled(holdsGame || model.selectedGame == nil)
            Button("Renomear") { model.beginRenameCatalogFolder(folder.id) }
            Button("Excluir") { model.deleteCatalogFolder(folder.id) }
                .help("Exclui apenas a pasta virtual. Os jogos voltam à biblioteca e nenhum arquivo é apagado.")
        }
        .buttonStyle(.plain)
        .font(.system(size: 11))
        .foregroundStyle(palette.highlight)
        .padding(.vertical, 8)
        .padding(.trailing, 10)
        .background(marked ? palette.accent.opacity(0.22) : Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(marked ? palette.highlight.opacity(0.7) : Color.white.opacity(0.06), lineWidth: 1))
    }
}
