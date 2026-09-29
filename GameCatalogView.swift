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
                Text(loading ? "Reloading" : "Reload")
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
        .help("Reloads games and covers for \(console.badge). R key, △ in the catalog, or R2 + L2.")
        .accessibilityLabel(loading ? "Reloading \(console.badge) catalog" : "Reload \(console.badge) catalog")
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
        let coverName = game.coverURL?.lastPathComponent ?? "unavailable"
        return "\(game.title)\n\(game.fileURL.lastPathComponent)\nCover: \(coverName)"
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
         .accessibilityLabel("Select \(game.title)")
         .accessibilityValue(selected ? "Selected" : "")
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
                        .clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityLabel("PlayStation logo")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("PS1/2  /  \(console.badge)").font(.system(size: 10, weight: .medium)).tracking(2).foregroundStyle(Theme.ice.opacity(0.65))
                    Text("\(console.badge) games").font(.system(size: 25, weight: .regular, design: .rounded)).foregroundStyle(.white)
                }
                Spacer()
                CatalogReloadButton(model: model, catalog: catalog)
                Button { model.showLibrarySettings() } label: {
                    Label("Game folders", systemImage: "folder.badge.gearshape")
                        .font(.system(size: 11)).foregroundStyle(Theme.ice)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Theme.blue.opacity(model.catalogCommand == .library ? 0.4 : 0), in: Capsule())
                        .overlay(Capsule().stroke(Theme.ice.opacity(model.catalogCommand == .library ? 0.95 : 0), lineWidth: 1.6))
                }.buttonStyle(.plain)
                 .help("Game folder on the Mac or on a disk. On the controller, ↑ to Disk and ×.")
                VStack(alignment: .trailing, spacing: 5) {
                    Text("\(games.count) games · \(console.emulator)").font(.system(size: 13)).foregroundStyle(Theme.pale)
                    Text(loading ? "Reloading games and covers…" : model.isStorageAvailable(for: console) ? "Last full load · R reloads" : "Offline catalog · Connect the disk to play")
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
                    Text("Loading the \(console.badge) catalog…").foregroundStyle(Theme.pale)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if games.isEmpty {
                VStack(spacing: 15) {
                    Image(systemName: "externaldrive").font(.system(size: 38, weight: .ultraLight)).foregroundStyle(Theme.ice)
                    Text("No saved games in this catalog").font(.system(size: 20, weight: .light))
                    Text("Choose a folder in Game folders, or connect the configured disk and use Reload, R or R2+L2.\nThe catalog shows the last saved list; files are checked when you open a game.")
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
                                            Text("Empty folder. Open Folders and place a game here.")
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
                    Text(selection?.title ?? "Select a game")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                    Text(selection.map { $0.fileURL.pathExtension.uppercased() + " · " + console.emulator } ?? "X / Enter opens the selected game")
                        .font(.system(size: 11)).foregroundStyle(Theme.pale.opacity(0.65))
                }
                Spacer()
                if loading { ProgressView().controlSize(.small) }
                Button { model.confirm() } label: {
                    Label("Open in \(console.emulator)", systemImage: "play.fill").font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Theme.blue.opacity(0.32), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.ice.opacity(0.4)))
                }.buttonStyle(.plain).foregroundStyle(.white).disabled(selection == nil || loading)
                 .accessibilityLabel("Open the selected game in \(console.emulator)")
            }.padding(.vertical, 16)
            Rectangle().fill(Theme.ice.opacity(0.15)).frame(height: 1)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 22) {
                    Button { model.confirm() } label: { hint("×", model.catalogCommand == nil ? "Open game" : "Confirm", "Enter", Theme.ice) }.disabled(model.catalogCommand == nil && (selection == nil || loading))
                    Button { model.back() } label: { hint("○", "Consoles", "Esc", Color(red: 0.92, green: 0.49, blue: 0.51)) }
                    Button { model.toggleFullscreen?() } label: { hint("□", model.fullscreen ? "Window" : "Full screen", "F", Color(red: 0.83, green: 0.58, blue: 0.80)) }
                    Button { model.reloadCatalog() } label: { hint("△", "Reload", "R", Color(red: 0.4, green: 0.9, blue: 0.68)) }
                        .disabled(loading)
                        .help("Reloads games and covers. Also R2 + L2, or the R key.")
                    Spacer(minLength: 0)
                }
                HStack(spacing: 22) {
                    legend("L1", "A–Z", Theme.ice)
                    legend("R1", "Z–A", Theme.ice)
                    legend("OPTIONS", "Folders", Theme.pale)
                    legend("↑", "Options", Theme.ice)
                    legend("↓", "Games", Theme.ice)
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
            commandChip(.folders, "Folders", "OPTIONS", sorting: false) { model.toggleCatalogFolders() }
            if model.availableCatalogCommands.contains(.minimize) {
                commandChip(.minimize, "Collapse", "C", sorting: false) { model.toggleSectionOfSelection() }
            }
            commandChip(.reload, "Reload", "△", sorting: false) { model.reloadCatalog() }
            commandChip(.library, "Disk", "×", sorting: false) { model.showLibrarySettings() }
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
        .accessibilityLabel(focused ? "\(title), marked" : title)
    }
    private func commandHelp(_ command: CatalogCommand) -> String {
        switch command {
        case .sortAZ: return "Sort A to Z. L1, the A key, or ↑ and ×."
        case .sortZA: return "Sort Z to A. R1, the Z key, or ↑ and ×."
        case .folders: return "Catalog folders. OPTIONS, the P key, or ↑ and ×. Files stay on the disk."
        case .minimize: return "Collapses or shows the marked game's folder. The C key, or ↑ and ×."
        case .reload: return "Reloads games and covers. △, R, R2 + L2, or ↑ and ×."
        case .library: return "Game folder on the Mac or on a disk. ↑ and ×."
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
        .accessibilityLabel(section.collapsed ? "Show \(section.title)" : "Collapse \(section.title)")
        .help(section.collapsed ? "Shows the games in this folder" : "Hides the games in this folder")
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
        guard let id = model.selectedGame?.id else { return "Library" }
        return folders.first { $0.gameIDs.contains(id) }?.name ?? "Library"
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
                        Text("Catalog folders").font(.system(size: 22, weight: .light, design: .rounded))
                        Text("They only organize this screen. Files stay on the disk.")
                            .font(.system(size: 12)).foregroundStyle(Theme.pale)
                    }
                    Spacer()
                    Button("Close · Esc") { model.dismissCatalogFolders() }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.ice)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.selectedGame?.title ?? "No game marked")
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                    Text("Now in \(currentFolderName)")
                        .font(.system(size: 11)).foregroundStyle(Theme.pale.opacity(0.75))
                }
                if folders.isEmpty {
                    Text("Create a folder, such as Football, Cars or Fighting. Without folders, the catalog stays one list.")
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
                    TextField("Folder name", text: draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.ice.opacity(0.28), lineWidth: 1))
                        .focused($nameFocused)
                        .onSubmit { model.confirmCatalogFolder() }
                    Button(model.renamingFolderID == nil ? "Create" : "Save") { model.confirmCatalogFolder() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.blue.opacity(CatalogNames.cleaned(model.folderDraft) == nil ? 0.16 : 0.4), in: RoundedRectangle(cornerRadius: 6))
                        .disabled(CatalogNames.cleaned(model.folderDraft) == nil)
                    if model.renamingFolderID != nil {
                        Button("Cancel") {
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
                    Text("↑↓ folder    ←→ action    × confirms    ○ closes")
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
        .accessibilityLabel("Catalog folders")
        .onAppear { nameFocused = true }
        .onChange(of: model.renamingFolderID) { _, id in
            if id != nil { nameFocused = true }
        }
    }

    private func folderActionTitle(_ action: CatalogFolderAction) -> String {
        switch action {
        case .place: return "Place"
        case .rename: return "Rename"
        case .delete: return "Delete"
        case .remove: return "Remove"
        case .create: return model.renamingFolderID == nil ? "Create" : "Save"
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
                    Text(holdsGame ? "Marked game is in this folder" : (count == 1 ? "1 game" : "\(count) games"))
                        .font(.system(size: 11)).foregroundStyle(Theme.pale.opacity(0.7))
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            Button(holdsGame ? "In this folder" : "Place") {
                model.catalogFolderIndex = index
                if !holdsGame { model.placeSelectedGame(in: folder.id) }
            }
            .disabled(holdsGame || model.selectedGame == nil)
            Button("Rename") { model.beginRenameCatalogFolder(folder.id) }
            Button("Delete") { model.deleteCatalogFolder(folder.id) }
                .help("The folder leaves the catalog. Games return to Library and no file is deleted.")
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
