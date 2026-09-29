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
        .help("Recarrega jogos e capas de \(console.badge). Tecla R, △ no catálogo, ou R2 + L2.")
        .accessibilityLabel(loading ? "Atualizando catálogo de \(console.badge)" : "Atualizar catálogo de \(console.badge)")
    }
}

@MainActor
private final class CatalogCover: ObservableObject {
    @Published var image: NSImage?
    private var requestID = UUID()

    func load(_ url: URL?, snapshotID: String?) async {
        let request = UUID()
        requestID = request
        guard let url, let snapshotID, !Task.isCancelled else {
            image = nil
            return
        }
        // Keep the current cover on screen until the reloaded thumbnail arrives.
        let thumbnail = await CoverImageCache.shared.image(at: url, maxPixelSize: 320, snapshotID: snapshotID)
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
                CatalogReloadButton(model: model, catalog: catalog)
                Button { model.showLibrarySettings() } label: {
                    Label("Pastas de jogos", systemImage: "folder.badge.gearshape")
                        .font(.system(size: 11)).foregroundStyle(Theme.ice)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Theme.blue.opacity(model.catalogCommand == .library ? 0.4 : 0), in: Capsule())
                        .overlay(Capsule().stroke(Theme.ice.opacity(model.catalogCommand == .library ? 0.95 : 0), lineWidth: 1.6))
                }.buttonStyle(.plain)
                 .help("Pasta dos jogos no Mac ou no disco. No controle, ↑ até Disco e ×.")
                VStack(alignment: .trailing, spacing: 5) {
                    Text("\(games.count) jogos · \(console.emulator)").font(.system(size: 13)).foregroundStyle(Theme.pale)
                    Text(loading ? "Atualizando jogos e capas…" : model.isStorageAvailable(for: console) ? "Última carga completa · R atualiza" : "Catálogo offline · Conecte o disco para jogar")
                        .font(.system(size: 10)).tracking(0.3).foregroundStyle(Theme.pale.opacity(0.65))
                }
            }.padding(.top, 35).padding(.bottom, 22)
            if let error = catalog.errors[console.rawValue] {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(2).padding(.bottom, 10)
            }
            catalogToolbar.padding(.bottom, 12)
            if loading && games.isEmpty {
                VStack(spacing: 15) {
                    ProgressView()
                    Text("Carregando catálogo de \(console.badge)…").foregroundStyle(Theme.pale)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if games.isEmpty {
                VStack(spacing: 15) {
                    Image(systemName: "externaldrive").font(.system(size: 38, weight: .ultraLight)).foregroundStyle(Theme.ice)
                    Text("Nenhum jogo salvo neste catálogo").font(.system(size: 20, weight: .light))
                    Text("Escolha uma pasta em Pastas de jogos, ou conecte o disco configurado e use Atualizar, R ou R2+L2.\nO catálogo mostra a última lista salva; os arquivos são verificados ao abrir o jogo.")
                        .font(.system(size: 12)).multilineTextAlignment(.center).foregroundStyle(Theme.pale.opacity(0.6))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(sections) { section in
                                VStack(alignment: .leading, spacing: 10) {
                                    if section.collapsible { sectionHeader(section) }
                                    if !section.collapsed {
                                        let cards = cards(in: section)
                                        if cards.isEmpty {
                                            Text("Pasta vazia. Abra Pastas e coloque um jogo aqui.")
                                                .font(.system(size: 12)).foregroundStyle(Theme.pale.opacity(0.55))
                                                .padding(.leading, 28).padding(.bottom, 4)
                                        } else {
                                            LazyVGrid(columns: columns, spacing: 16) {
                                                ForEach(cards) { game in
                                                    GameCard(game: game, selected: selection?.id == game.id,
                                                             snapshotID: catalog.snapshotIDs[console.rawValue],
                                                             coverHeight: layout.catalogCoverHeight) { model.selectGame(game) }
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
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 22) {
                    Button { model.confirm() } label: { hint("×", model.catalogCommand == nil ? "Abrir jogo" : "Confirmar", "Enter", Theme.ice) }.disabled(model.catalogCommand == nil && (selection == nil || loading))
                    Button { model.back() } label: { hint("○", "Consoles", "Esc", Color(red: 0.92, green: 0.49, blue: 0.51)) }
                    Button { model.toggleFullscreen?() } label: { hint("□", model.fullscreen ? "Janela" : "Tela cheia", "F", Color(red: 0.83, green: 0.58, blue: 0.80)) }
                    Button { model.reloadCatalog() } label: { hint("△", "Atualizar", "R", Color(red: 0.4, green: 0.9, blue: 0.68)) }
                        .disabled(loading)
                        .help("Recarrega jogos e capas. Também R2 + L2, ou a tecla R.")
                    Spacer(minLength: 0)
                }
                HStack(spacing: 22) {
                    legend("L1", "A–Z", Theme.ice)
                    legend("R1", "Z–A", Theme.ice)
                    legend("OPTIONS", "Pastas", Theme.pale)
                    legend("↑", "Opções", Theme.ice)
                    legend("↓", "Jogos", Theme.ice)
                    Spacer(minLength: 0)
                }
            }.buttonStyle(.plain).padding(.top, 15).padding(.bottom, 24)
        }.padding(.horizontal, layout.horizontalPadding)
         .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
         .background(Theme.background.opacity(0.92))
         .overlay {
             if model.showingCatalogFolders {
                 CatalogFoldersPanel(console: console, model: model)
             }
         }
         .onAppear {
             model.catalogColumns = layout.catalogColumns
             model.alignCatalogSelection()
         }
         .onChange(of: layout.catalogColumns) { _, count in model.catalogColumns = count }
         .onChange(of: model.catalogOrganizationToken) { _, _ in model.alignCatalogSelection() }
    }
    private var sections: [CatalogSection] { model.catalogSections(for: console) }
    private var gamesByID: [String: CatalogGame] {
        Dictionary(games.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
    private func cards(in section: CatalogSection) -> [CatalogGame] {
        section.games.compactMap { gamesByID[$0.id] }
    }
    private var catalogToolbar: some View {
        HStack(spacing: 8) {
            commandChip(.sortAZ, "A–Z", "L1", sorting: model.catalogSortAscending) { model.setCatalogSort(ascending: true) }
            commandChip(.sortZA, "Z–A", "R1", sorting: !model.catalogSortAscending) { model.setCatalogSort(ascending: false) }
            commandChip(.folders, "Pastas", "OPTIONS", sorting: false) { model.toggleCatalogFolders() }
            if model.availableCatalogCommands.contains(.minimize) {
                commandChip(.minimize, "Minimizar", "C", sorting: false) { model.toggleSectionOfSelection() }
            }
            commandChip(.reload, "Atualizar", "△", sorting: false) { model.reloadCatalog() }
            commandChip(.library, "Disco", "×", sorting: false) { model.showLibrarySettings() }
            Spacer(minLength: 0)
        }
    }
    private func commandChip(_ command: CatalogCommand, _ title: String, _ key: String, sorting: Bool, action: @escaping () -> Void) -> some View {
        let focused = model.catalogCommand == command
        return Button {
            model.catalogCommand = command
            action()
        } label: {
            HStack(spacing: 6) {
                Text(title)
                Text(key).font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.pale.opacity(focused || sorting ? 0.9 : 0.45))
            }
            .font(.system(size: 12, weight: focused || sorting ? .semibold : .regular))
            .foregroundStyle(focused || sorting ? .white : Theme.pale.opacity(0.8))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Theme.blue.opacity(focused ? 0.55 : sorting ? 0.32 : 0.08), in: Capsule())
            .overlay(Capsule().stroke(Theme.ice.opacity(focused ? 1 : sorting ? 0.45 : 0.22), lineWidth: focused ? 1.6 : 1))
        }
        .buttonStyle(.plain)
        .help(commandHelp(command))
        .accessibilityLabel(focused ? "\(title), marcado" : title)
    }
    private func commandHelp(_ command: CatalogCommand) -> String {
        switch command {
        case .sortAZ: return "Ordem de A a Z. L1, tecla A, ou ↑ e ×."
        case .sortZA: return "Ordem de Z a A. R1, tecla Z, ou ↑ e ×."
        case .folders: return "Pastas do catálogo. OPTIONS, tecla P, ou ↑ e ×. Os arquivos não saem do disco."
        case .minimize: return "Minimiza ou mostra a pasta do jogo marcado. Tecla C, ou ↑ e ×."
        case .reload: return "Atualiza jogos e capas. △, R, R2 + L2, ou ↑ e ×."
        case .library: return "Pasta dos jogos no Mac ou no disco. ↑ e ×."
        }
    }
    private func legend(_ symbol: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Text(symbol).font(.system(size: symbol.count > 2 ? 10 : 13, weight: .bold, design: .monospaced)).foregroundStyle(color)
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.pale)
        }
    }
    private func sectionHeader(_ section: CatalogSection) -> some View {
        let active = section.games.contains { $0.id == selection?.id }
        return Button { model.toggleCatalogSection(section.id) } label: {
            HStack(spacing: 10) {
                Image(systemName: section.collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.ice)
                    .frame(width: 14)
                Image(systemName: section.isLibrary ? "square.stack" : "folder.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ice.opacity(active ? 1 : 0.8))
                Text(section.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                Text("\(section.games.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.pale.opacity(0.65))
                Rectangle().fill(Theme.ice.opacity(active ? 0.55 : 0.22)).frame(height: 1)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.collapsed ? "Mostrar \(section.title)" : "Minimizar \(section.title)")
        .help(section.collapsed ? "Mostra os jogos desta pasta" : "Esconde os jogos desta pasta")
    }
    private func hint(_ symbol: String, _ text: String, _ key: String, _ color: Color) -> some View {
        HStack(spacing: 7) {
            Text(symbol).font(.system(size: 21, weight: .regular)).foregroundStyle(color)
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.pale)
            Text(key).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.pale.opacity(0.55))
        }.contentShape(Rectangle())
    }
}

private struct CatalogFoldersPanel: View {
    let console: Console
    @ObservedObject var model: LauncherModel
    @FocusState private var nameFocused: Bool

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
                    Image(systemName: "folder.fill").font(.system(size: 22)).foregroundStyle(Theme.ice)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Pastas do catálogo").font(.system(size: 22, weight: .light, design: .rounded))
                        Text("Só organizam esta tela. Os arquivos continuam no disco.")
                            .font(.system(size: 12)).foregroundStyle(Theme.pale)
                    }
                    Spacer()
                    Button("Fechar · Esc") { model.dismissCatalogFolders() }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.ice)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.selectedGame?.title ?? "Nenhum jogo marcado")
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                    Text("Agora em \(currentFolderName)")
                        .font(.system(size: 11)).foregroundStyle(Theme.pale.opacity(0.75))
                }
                if folders.isEmpty {
                    Text("Crie uma pasta, como Futebol, Carros ou Luta. Sem pastas, o catálogo continua uma lista só.")
                        .font(.system(size: 12)).foregroundStyle(Theme.pale.opacity(0.75))
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
                    Text(message).font(.system(size: 12)).foregroundStyle(Theme.ice).lineLimit(2)
                }
                HStack(spacing: 10) {
                    TextField("Nome da pasta", text: draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.ice.opacity(0.28), lineWidth: 1))
                        .focused($nameFocused)
                        .onSubmit { model.confirmCatalogFolder() }
                    Button(model.renamingFolderID == nil ? "Criar" : "Salvar") { model.confirmCatalogFolder() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.blue.opacity(CatalogNames.cleaned(model.folderDraft) == nil ? 0.16 : 0.4), in: RoundedRectangle(cornerRadius: 6))
                        .disabled(CatalogNames.cleaned(model.folderDraft) == nil)
                    if model.renamingFolderID != nil {
                        Button("Cancelar") {
                            model.renamingFolderID = nil
                            model.folderDraft = ""
                        }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.pale)
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
                                .background(Theme.blue.opacity(marked ? 0.5 : 0.16), in: Capsule())
                                .overlay(Capsule().stroke(Theme.ice.opacity(marked ? 1 : 0.25), lineWidth: marked ? 1.6 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    Text("↑↓ pasta    ←→ ação    × confirma    ○ fecha")
                        .font(.system(size: 10)).foregroundStyle(Theme.ice.opacity(0.7))
                    Spacer()
                }
            }
            .padding(24)
            .frame(width: 680)
            .background(Theme.background.opacity(0.96), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Theme.ice.opacity(0.28), lineWidth: 1))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pastas do catálogo")
        .onAppear { nameFocused = true }
        .onChange(of: model.renamingFolderID) { _, id in
            if id != nil { nameFocused = true }
        }
    }

    private func folderActionTitle(_ action: CatalogFolderAction) -> String {
        switch action {
        case .place: return "Colocar"
        case .rename: return "Renomear"
        case .delete: return "Apagar"
        case .remove: return "Tirar"
        case .create: return model.renamingFolderID == nil ? "Criar" : "Salvar"
        }
    }

    private func folderRow(_ folder: CatalogFolder, index: Int) -> some View {
        let marked = index == highlighted
        let holdsGame = model.selectedGame.map { folder.gameIDs.contains($0.id) } ?? false
        let count = folder.gameIDs.filter { knownIDs.contains($0) }.count
        return HStack(spacing: 10) {
            Rectangle().fill(marked ? Theme.ice : Color.clear).frame(width: 3)
            Button { model.catalogFolderIndex = index } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name).font(.system(size: 14, weight: marked ? .semibold : .regular))
                        .foregroundStyle(.white).lineLimit(1)
                    Text(holdsGame ? "Jogo marcado nesta pasta" : (count == 1 ? "1 jogo" : "\(count) jogos"))
                        .font(.system(size: 11)).foregroundStyle(Theme.pale.opacity(0.7))
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
            Button("Apagar") { model.deleteCatalogFolder(folder.id) }
                .help("A pasta some do catálogo. Os jogos voltam para Biblioteca e nenhum arquivo é apagado.")
        }
        .buttonStyle(.plain)
        .font(.system(size: 11))
        .foregroundStyle(Theme.ice)
        .padding(.vertical, 8)
        .padding(.trailing, 10)
        .background(marked ? Theme.blue.opacity(0.22) : Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(marked ? Theme.ice.opacity(0.7) : Color.white.opacity(0.06), lineWidth: 1))
    }
}
