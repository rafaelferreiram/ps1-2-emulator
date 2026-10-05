import AppKit
import SwiftUI
import Combine

enum CatalogCommand: String, CaseIterable, Identifiable {
    case sortAZ, sortZA, folders, minimize, reload, library, filter, favorite, density, session, experience, clearSearch
    var id: String { rawValue }
}

enum CatalogFolderAction: String, CaseIterable, Identifiable {
    case place, rename, delete, remove, create
    var id: String { rawValue }
}

enum Console: String, CaseIterable, Identifiable {
    case ps1, ps2
    var id: String { rawValue }
    var name: String { self == .ps1 ? "PlayStation 1" : "PlayStation 2" }
    var badge: String { self == .ps1 ? "PS1" : "PS2" }
    var emulator: String { self == .ps1 ? "DuckStation" : "PCSX2" }
    var controller: String { self == .ps1 ? "Controle original" : "DualShock 2" }
    var asset: String { self == .ps1 ? "PS1Controller" : "PS2Controller" }
    var bundleID: String { self == .ps1 ? "com.github.stenzek.duckstation" : "net.pcsx2.pcsx2" }
    var applicationURL: URL? {
        EmulatorApplicationLookup.find(for: self)
    }
}

enum EmulatorApplicationLookup {
    static func find(for console: Console,
                     launcherBundleURL: URL = Bundle.main.bundleURL,
                     systemApplicationsDirectory: URL = URL(fileURLWithPath: "/Applications", isDirectory: true),
                     homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
                     registeredApplication: (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }) -> URL? {
        let appName = "\(console.emulator).app"
        var directories: [URL] = []
        // The installer can place all three apps in a user-selected folder.
        if launcherBundleURL.isFileURL && launcherBundleURL.pathExtension.lowercased() == "app" {
            directories.append(launcherBundleURL.deletingLastPathComponent())
        }
        directories.append(systemApplicationsDirectory)
        directories.append(homeDirectory.appendingPathComponent("Applications", isDirectory: true))
        for directory in directories {
            let candidate = directory.appendingPathComponent(appName, isDirectory: true)
            if isValid(candidate, for: console) { return candidate }
        }
        guard let registered = registeredApplication(console.bundleID), isValid(registered, for: console) else { return nil }
        return registered
    }

    private static func isValid(_ url: URL, for console: Console) -> Bool {
        guard url.isFileURL, url.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: url), bundle.bundleIdentifier == console.bundleID,
              let executable = bundle.executableURL else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: executable.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: executable.path)
    }
}

enum Theme {
    static let ice = Color(red: 0.65, green: 0.85, blue: 1)
    static let blue = Color(red: 0.17, green: 0.44, blue: 1)
    static let pale = Color(red: 0.79, green: 0.84, blue: 0.95)
    static let background = Color(red: 0.012, green: 0.021, blue: 0.055)
    static let catalogColumns = 5
    static let images: [String: NSImage] = {
        var images = [String: NSImage]()
        for name in ["Logo", "PS1Controller", "PS2Controller"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "png"), let image = NSImage(contentsOf: url) {
                images[name] = image
            }
        }
        return images
    }()
}

@MainActor
final class LauncherModel: ObservableObject {
    @Published var showingExperienceSettings = false
    @Published var showingSessionMenu = false
    @Published var sessionMenuIndex = 0
    @Published var dialog: LauncherDialog?
    @Published var dialogAcceptSelected = false
    @Published var selectedCatalogFolderID: String?
    @Published private(set) var resolvedSessionGameIDs: [String: String] = [:]
    @Published private(set) var storageAvailability: [String: Bool] = [:]
    @Published var showingLibrarySettings = false
    @Published var choosingLibraryFolder = false
    @Published var settingsConsole: Console = .ps2
    @Published var librarySettingsError: String?
    @Published var selected: Console = .ps2
    @Published var launching: Console?
    @Published var notice = ""
    @Published var errorMessage: String?
    @Published var storageNotice: StorageNotice?
    @Published var booting = true
    @Published var isForeground = true
    @Published var fullscreen = false
    @Published var controllerName: String?
    @Published var sessions: [String: EmulatorState] = [:]
    @Published var now = Date()
    @Published var launchID: UUID?
    @Published var isOpening = false
    @Published var stopping: Set<Console> = []
    @Published var catalogConsole: Console?
    @Published var catalogColumns = Theme.catalogColumns
    @Published var gameSelection: [String: String] = [:]
    @Published var showingCatalogFolders = false
    @Published var folderDraft = ""
    @Published var catalogFolderIndex = 0
    @Published var renamingFolderID: UUID?
    @Published var catalogFolderMessage: String?
    @Published var catalogCommand: CatalogCommand?
    @Published var catalogFolderAction: CatalogFolderAction?
    @Published var launchGameTitle: String?
    @Published var openingText = ""
    @Published var waitingForRestart = false
    let catalog: GameCatalog
    let librarySettings: GameLibrarySettings
    let organizer: CatalogOrganizer
    let personalLibrary: PersonalLibrary
    let experience: ExperiencePreferences
    let sounds = ConsoleSoundPlayer()
    var reduceMotion: Bool { experience.reduceMotion(system: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) }
    var hasOverlay: Bool { showingExperienceSettings || showingSessionMenu || dialog != nil || errorMessage != nil || storageNotice != nil || showingLibrarySettings || showingCatalogFolders }
    var activeConsole: Console { catalogConsole ?? selected }
    var toggleFullscreen: (() -> Void)?
    var returnToLauncher: (() -> Void)?
    var chooseLibraryFolder: ((Console) -> Void)?
    private var timer: Timer?
    private var libraryObserver: AnyCancellable?
    private var organizerObserver: AnyCancellable?
    private var personalObserver: AnyCancellable?
    private var experienceObserver: AnyCancellable?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var ownedSessions: [String: OwnedGameSession] = [:]
    private var pendingHistory: Set<String> = []
    private var lastFrontmostPID: Int32?
    private var lastFrontmostApplication: NSRunningApplication?
    private var sessionResolutionTokens: [String: String] = [:]
    private var serviceTick = 0
    private var lastCatalogCommand: CatalogCommand = .sortAZ
    private let storageProbe: (() -> Bool)?
    private let monitor: EmulatorMonitor
    private var launchURL: URL?
    private var launchGameURL: URL?
    private var launchGameID: String?
    private var restartEmulator: (pid: Int32, launchedAt: Date?)?
    private var stopDeadlines: [Console: Date] = [:]
    let startedAt = Date()

    init(catalog: GameCatalog? = nil, librarySettings: GameLibrarySettings? = nil,
         organizer: CatalogOrganizer? = nil,
         personalLibrary: PersonalLibrary? = nil, experience: ExperiencePreferences? = nil,
         storageProbe: (() -> Bool)? = nil, startServices: Bool = true) {
        let settings = librarySettings ?? GameLibrarySettings()
        self.librarySettings = settings
        let storedOrganizer = organizer ?? CatalogOrganizer()
        self.organizer = storedOrganizer
        self.personalLibrary = personalLibrary ?? PersonalLibrary(defaults: startServices ? .standard : UserDefaults(suiteName: "PS12.Test.Personal.\(UUID().uuidString)")!)
        self.experience = experience ?? ExperiencePreferences(defaults: startServices ? .standard : UserDefaults(suiteName: "PS12.Test.Experience.\(UUID().uuidString)")!)
        let sources = Dictionary(uniqueKeysWithValues: Console.allCases.compactMap { console -> (String, CatalogSource)? in
            guard let source = CatalogSource.installed(console.rawValue, root: settings.folder(for: console.rawValue)) else { return nil }
            return (console.rawValue, source)
        })
        self.catalog = catalog ?? GameCatalog(sources: sources)
        self.monitor = EmulatorMonitor(libraries: sources.mapValues { $0.root.path })
        self.storageProbe = storageProbe
        libraryObserver = settings.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        organizerObserver = storedOrganizer.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        personalObserver = self.personalLibrary.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        experienceObserver = self.experience.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        for console in Console.allCases {
            gameSelection[console.rawValue] = self.personalLibrary.state(console: console.rawValue, root: settings.folder(for: console.rawValue)).selectedGameID
        }
        refreshStorage()
        guard startServices else { return }
        self.catalog.restoreSavedCatalogs()
        refreshSessions()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.serviceTick += 1
                // Poll loaded-disc descriptors less often while another app is
                // foreground. Workspace notifications handle process exit promptly.
                if self.isForeground || self.serviceTick % 5 == 0 {
                    self.refreshStorage()
                    self.refreshSessions()
                }
            }
        }
        timer?.tolerance = 0.15
        let center = NSWorkspace.shared.notificationCenter
        lastFrontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        lastFrontmostApplication = NSWorkspace.shared.frontmostApplication
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                // On some macOS versions activation of the previous window is
                // delivered before didTerminate. Observe the old app's actual
                // termination, not a timeout that might steal focus after Cmd-Tab.
                if let previous = self.lastFrontmostApplication, previous.isTerminated {
                    self.sessionTerminated(previous)
                }
                self.lastFrontmostPID = app.processIdentifier
                self.lastFrontmostApplication = app
            }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.sessionTerminated(app) }
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 1.7)) { [weak self] in self?.finishBoot() }
    }
    func refreshSessions() {
        monitor.refresh()
        if sessions != monitor.states { sessions = monitor.states }
        catalog.setArtworkPrefetchSuspended(!isForeground && sessions.values.contains(where: \.isRunning))
        if sessions.values.contains(where: \.isRunning) || !stopping.isEmpty { now = Date() }
        resolveLoadedGames()
        recordObservedLaunches()
        for console in Array(stopping) {
            if !state(console).isRunning {
                stopping.remove(console)
                stopDeadlines.removeValue(forKey: console)
                notice = "\(console.badge) desligado."
            } else if let deadline = stopDeadlines[console], now >= deadline {
                stopping.remove(console)
                stopDeadlines.removeValue(forKey: console)
                notice = "\(console.emulator) continua aberto. Confirme ou cancele a saída na janela dele."
            }
        }
    }
    private func resolveLoadedGames() {
        for console in Console.allCases {
            let key = console.rawValue
            let current = state(console)
            guard current.isRunning, let path = current.gamePath else {
                if resolvedSessionGameIDs[key] != nil { resolvedSessionGameIDs.removeValue(forKey: key) }
                sessionResolutionTokens.removeValue(forKey: key)
                continue
            }
            let token = "\(current.pid ?? 0)|\(current.launchedAt?.timeIntervalSince1970 ?? 0)|\(path)|\(gameFolder(for: console).path)|\(catalog.snapshotIDs[key] ?? "")"
            guard sessionResolutionTokens[key] != token else { continue }
            sessionResolutionTokens[key] = token
            resolvedSessionGameIDs.removeValue(forKey: key)
            Task { @MainActor [weak self] in
                guard let self else { return }
                let owner = await self.catalog.cachedGameForLoadedGame(path: path, consoleKey: key)
                guard self.sessionResolutionTokens[key] == token else { return }
                self.resolvedSessionGameIDs[key] = owner?.id
                self.recordObservedLaunches()
            }
        }
    }
    private func recordObservedLaunches() {
        for key in Array(pendingHistory) {
            guard let owned = ownedSessions[key], let console = Console(rawValue: key) else { continue }
            let current = state(console)
            let game = CatalogGame(id: owned.gameID, consoleKey: key, title: "", fileURL: owned.gameURL, coverURL: nil)
            if current.pid == owned.pid, current.launchedAt == owned.launchedAt, sameLoadedGame(game, path: current.gamePath) {
                personalLibrary.recordLaunch(owned.gameID, console: key, root: owned.libraryRoot)
                pendingHistory.remove(key)
            }
        }
    }
    func state(_ console: Console) -> EmulatorState { sessions[console.rawValue] ?? .off }
    func playSound(_ cue: ConsoleSoundPlayer.Cue) {
        guard isForeground else { return }
        sounds.play(cue, console: activeConsole, preferences: experience)
    }
    func showExperienceSettings() {
        guard launching == nil, !hasOverlay, NSApp.modalWindow == nil else { return }
        finishBoot()
        experience.focusedSetting = .startup
        showingExperienceSettings = true
    }
    var sessionActions: [SessionMenuAction] {
        (state(activeConsole).isRunning ? [.resume, .stop] : [.openEmulator]) + [.appearance, .libraries, .close]
    }
    func showSessionMenu() {
        guard launching == nil, !hasOverlay, NSApp.modalWindow == nil else { return }
        finishBoot()
        sessionMenuIndex = 0
        showingSessionMenu = true
    }
    private func moveSessionMenu(_ direction: Int) {
        let count = sessionActions.count
        sessionMenuIndex = (sessionMenuIndex + direction + count) % count
        playSound(.navigate)
    }
    func activateSessionAction() {
        let actions = sessionActions
        guard actions.indices.contains(sessionMenuIndex) else { sessionMenuIndex = 0; return }
        let action = actions[sessionMenuIndex]
        showingSessionMenu = false
        switch action {
        case .resume: returnToGame(activeConsole)
        case .stop: requestStop(activeConsole)
        case .openEmulator: launch(activeConsole)
        case .appearance: showExperienceSettings()
        case .libraries: showLibrarySettings()
        case .close: break
        }
    }
    func openConsoleCatalog(_ console: Console) {
        guard !hasOverlay, launching == nil else { return }
        rememberCatalogSelection()
        select(console)
        guard selected == console else { return }
        catalogConsole = nil
        showCatalog()
    }
    func uptime(_ console: Console) -> String {
        guard let date = state(console).launchedAt else { return "--:--:--" }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
    func refreshStorage() {
        // Read only the mounted-volume list, not game folders or descriptors.
        // An unplugged SSD does not erase the last complete catalog snapshot.
        let volumes = Set(FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [])?
            .map { $0.standardizedFileURL.path } ?? [])
        let next = Dictionary(uniqueKeysWithValues: Console.allCases.map { console in
            let volume = librarySettings.location(for: console.rawValue).volumePath
            return (console.rawValue, storageProbe?() ?? volume.map { volumes.contains($0) } ?? true)
        })
        if storageAvailability != next { storageAvailability = next }
    }
    var storageMounted: Bool { isStorageAvailable(for: catalogConsole ?? selected) }
    func isStorageAvailable(for console: Console) -> Bool { storageAvailability[console.rawValue] ?? false }
    func gameFolder(for console: Console) -> URL { librarySettings.folder(for: console.rawValue) }
    func showLibrarySettings() {
        guard !showingExperienceSettings, !showingSessionMenu, dialog == nil else { return }
        guard launching == nil, storageNotice == nil, errorMessage == nil, NSApp.modalWindow == nil,
              !choosingLibraryFolder else { return }
        dismissCatalogFolders()
        finishBoot()
        settingsConsole = catalogConsole ?? selected
        librarySettingsError = nil
        showingLibrarySettings = true
    }
    func dismissLibrarySettings() {
        guard !choosingLibraryFolder else { return }
        showingLibrarySettings = false
        librarySettingsError = nil
    }
    func setGameFolder(_ folder: URL, for console: Console) {
        guard launching == nil else { return }
        librarySettingsError = nil
        do {
            guard try librarySettings.setFolder(folder, for: console.rawValue) else { return }
            applyLibraryChange(for: console, fullLoad: true)
        } catch { librarySettingsError = error.localizedDescription }
    }
    func resetGameFolder(for console: Console) {
        guard launching == nil, !choosingLibraryFolder else { return }
        guard librarySettings.reset(for: console.rawValue) else { return }
        applyLibraryChange(for: console, fullLoad: false)
    }
    private func applyLibraryChange(for console: Console, fullLoad: Bool) {
        librarySettingsError = nil
        gameSelection.removeValue(forKey: console.rawValue)
        selectedCatalogFolderID = nil
        let folder = gameFolder(for: console)
        let saved = personalLibrary.state(console: console.rawValue, root: folder)
        gameSelection[console.rawValue] = saved.selectedGameID
        if catalogConsole == console { selectedCatalogFolderID = saved.selectedSectionID }
        monitor.setLibrary(folder.path, for: console.rawValue)
        if let source = CatalogSource.installed(console.rawValue, root: folder) {
            catalog.setSource(source, restoreSaved: !fullLoad)
            if fullLoad { catalog.refresh(console.rawValue, force: true) }
        }
        notice = "Pasta do \(console.badge) atualizada."
        refreshStorage()
        refreshSessions()
    }
    func finishBoot() {
        guard booting else { return }
        withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.65)) { booting = false }
    }
    func select(_ console: Console) {
        guard !hasOverlay else { return }
        guard launching == nil, !booting, errorMessage == nil, storageNotice == nil,
              !showingLibrarySettings, !showingCatalogFolders else { return }
        if selected != console { playSound(.navigate) }
        withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.2)) { selected = console }
    }
    var previewConsole: Console? {
        guard !hasOverlay else { return nil }
        guard !booting, isForeground, launching == nil, catalogConsole == nil, errorMessage == nil,
              storageNotice == nil, !showingLibrarySettings else { return nil }
        return selected
    }
    func setConsoleHover(_ console: Console, inside: Bool) {
        guard !hasOverlay else { return }
        guard inside, !booting, isForeground, launching == nil,
              catalogConsole == nil, errorMessage == nil, storageNotice == nil, !showingLibrarySettings else { return }
        select(console)
    }
    func move(_ direction: Int) {
        if dialog != nil { dialogAcceptSelected.toggle(); return }
        if showingExperienceSettings { experience.adjust(direction); return }
        if showingSessionMenu { moveSessionMenu(direction); return }
        guard errorMessage == nil, storageNotice == nil, NSApp.modalWindow == nil else { return }
        if showingCatalogFolders { moveFolderActions(direction); return }
        if showingLibrarySettings {
            guard !choosingLibraryFolder else { return }
            settingsConsole = settingsConsole == .ps1 ? .ps2 : .ps1
            return
        }
        guard !booting, launching == nil else { finishBoot(); return }
        if catalogConsole != nil { moveInsideCatalog(horizontal: direction, vertical: 0); return }
        select(selected == .ps1 ? .ps2 : .ps1)
    }
    func moveVertical(_ direction: Int) {
        if dialog != nil { dialogAcceptSelected.toggle(); return }
        if showingExperienceSettings { experience.moveFocus(direction); return }
        if showingSessionMenu { moveSessionMenu(direction); return }
        guard errorMessage == nil, storageNotice == nil, NSApp.modalWindow == nil, launching == nil else { return }
        if booting { finishBoot(); return }
        if showingCatalogFolders { moveFolderList(direction); return }
        if showingLibrarySettings { move(direction); return }
        if catalogConsole != nil { moveInsideCatalog(horizontal: 0, vertical: direction) } else { move(direction) }
    }
    var catalogSortAscending: Bool {
        organizer.layout(for: (catalogConsole ?? selected).rawValue).ascending
    }
    var catalogOrganizationToken: String {
        let key = (catalogConsole ?? selected).rawValue
        let layout = organizer.layout(for: key)
        let folders = layout.folders.map { "\($0.id.uuidString)#\($0.name)#\($0.gameIDs.joined(separator: ","))" }.joined(separator: "|")
        let collapsed = layout.collapsed.sorted().joined(separator: ",")
        let count = catalog.games[key]?.count ?? 0
        let personal = libraryState(for: catalogConsole ?? selected)
        return "\(layout.ascending)#\(folders)#\(collapsed)#\(count)#\(personal.filter)#\(personal.query)#\(personal.favoriteIDs.sorted())#\(personal.lastLaunched)#\(personal.density)"
    }
    func libraryState(for console: Console) -> PersonalLibraryState {
        personalLibrary.state(console: console.rawValue, root: gameFolder(for: console))
    }
    func filteredCatalogGames(for console: Console) -> [CatalogGame] {
        let all = catalog.games[console.rawValue] ?? []
        let entries = all.map { CatalogEntry(id: $0.id, title: $0.title) }
        return resolved(personalLibrary.filteredEntries(entries, console: console.rawValue, root: gameFolder(for: console)), console: console)
    }
    func setCatalogFilter(_ filter: LibraryFilter) {
        guard let console = catalogConsole else { return }
        personalLibrary.setFilter(filter, console: console.rawValue, root: gameFolder(for: console))
        selectedCatalogFolderID = nil
        alignCatalogSelection()
    }
    func setCatalogQuery(_ query: String) {
        guard let console = catalogConsole else { return }
        personalLibrary.setQuery(query, console: console.rawValue, root: gameFolder(for: console))
        selectedCatalogFolderID = nil
        alignCatalogSelection()
    }
    func toggleSelectedFavorite() {
        guard let console = catalogConsole, let game = selectedGame else { return }
        personalLibrary.toggleFavorite(game.id, console: console.rawValue, root: gameFolder(for: console))
        playSound(.confirm)
        alignCatalogSelection()
    }
    func toggleCatalogDensity() {
        guard let console = catalogConsole else { return }
        personalLibrary.setDensity(libraryState(for: console).density == .comfortable ? .compact : .comfortable,
                                   console: console.rawValue, root: gameFolder(for: console))
    }
    func catalogSections(for console: Console) -> [CatalogSection] {
        let stored = filteredCatalogGames(for: console)
        let entries = stored.map { CatalogEntry(id: $0.id, title: $0.title) }
        let personal = libraryState(for: console)
        if personal.filter == .recent {
            return [CatalogSection(id: "recent", title: "Recentes", games: entries, collapsible: false, collapsed: false)]
        }
        // Search/favorites must not hide matches inside a collapsed folder.
        if personal.filter == .favorites || !personal.query.isEmpty {
            return [CatalogSection(id: "results", title: "Resultados", games: entries.sorted {
                let order = $0.title.localizedStandardCompare($1.title)
                return catalogSortAscending ? order == .orderedAscending : order == .orderedDescending
            }, collapsible: false, collapsed: false)]
        }
        return CatalogGrouping.sections(entries: entries, layout: organizer.layout(for: console.rawValue))
    }
    func catalogFolders(for console: Console) -> [CatalogFolder] {
        organizer.layout(for: console.rawValue).folders
    }
    var listedGames: [CatalogGame] {
        guard let console = catalogConsole else { return [] }
        return resolved(CatalogGrouping.visible(catalogSections(for: console)), console: console)
    }
    var selectedGame: CatalogGame? {
        guard selectedCatalogFolderID == nil else { return nil }
        guard let console = catalogConsole else { return nil }
        let visible = listedGames
        if let id = gameSelection[console.rawValue], let game = visible.first(where: { $0.id == id }) { return game }
        return visible.first
    }
    func alignCatalogSelection() {
        guard let console = catalogConsole else { return }
        if let command = catalogCommand, !availableCatalogCommands.contains(command) { catalogCommand = .filter }
        if let header = selectedCatalogFolderID,
           catalogSections(for: console).contains(where: { $0.id == header && $0.collapsible }) { return }
        selectedCatalogFolderID = nil
        let visible = listedGames
        guard !visible.isEmpty else { return }
        if let id = gameSelection[console.rawValue], visible.contains(where: { $0.id == id }) { return }
        gameSelection[console.rawValue] = visible[0].id
        rememberCatalogSelection()
    }
    func selectGame(_ game: CatalogGame) {
        guard launching == nil, storageNotice == nil, !showingLibrarySettings, !showingCatalogFolders,
              game.consoleKey == catalogConsole?.rawValue else { return }
        catalogCommand = nil
        selectedCatalogFolderID = nil
        if gameSelection[game.consoleKey] != game.id { playSound(.navigate) }
        gameSelection[game.consoleKey] = game.id
        rememberCatalogSelection()
    }
    func selectCatalogSection(_ id: String) {
        guard let console = catalogConsole, catalogSections(for: console).contains(where: { $0.id == id && $0.collapsible }) else { return }
        catalogCommand = nil
        selectedCatalogFolderID = id
        rememberCatalogSelection()
    }
    private func rememberCatalogSelection() {
        guard let console = catalogConsole else { return }
        personalLibrary.rememberSelection(gameID: gameSelection[console.rawValue], sectionID: selectedCatalogFolderID,
                                          console: console.rawValue, root: gameFolder(for: console))
    }
    private func resolved(_ entries: [CatalogEntry], console: Console) -> [CatalogGame] {
        let stored = catalog.games[console.rawValue] ?? []
        let byID = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return entries.compactMap { byID[$0.id] }
    }
    private func moveGame(horizontal: Int, vertical: Int) {
        guard launching == nil, !showingCatalogFolders, !showingLibrarySettings,
              errorMessage == nil, storageNotice == nil, NSApp.modalWindow == nil,
              let console = catalogConsole else { return }
        let visible = listedGames
        guard !visible.isEmpty else { return }
        let board = CatalogBoard(sections: catalogSections(for: console))
        let currentID = gameSelection[console.rawValue]
        let start = currentID.flatMap { board.contains($0) ? $0 : nil } ?? visible[0].id
        guard let nextID = board.move(from: start, columns: max(1, catalogColumns), horizontal: horizontal, vertical: vertical),
              let game = visible.first(where: { $0.id == nextID }) else { return }
        selectGame(game)
    }
    var availableCatalogCommands: [CatalogCommand] {
        guard let console = catalogConsole else { return [] }
        var commands: [CatalogCommand] = [.filter, .favorite, .density, .sortAZ, .sortZA, .folders]
        if !libraryState(for: console).query.isEmpty { commands.insert(.clearSearch, at: 0) }
        if catalogSections(for: console).contains(where: \.collapsible) { commands.append(.minimize) }
        commands.append(contentsOf: [.reload, .library, .session, .experience])
        return commands
    }
    func focusCatalogCommands() {
        let commands = availableCatalogCommands
        guard !commands.isEmpty else { return }
        if let current = catalogCommand, commands.contains(current) { return }
        catalogCommand = commands.contains(lastCatalogCommand) ? lastCatalogCommand : commands[0]
    }
    private func shiftCatalogCommand(_ direction: Int) {
        let commands = availableCatalogCommands
        guard !commands.isEmpty else { return }
        let current = catalogCommand.flatMap { commands.firstIndex(of: $0) } ?? 0
        let next = commands[(current + direction + commands.count) % commands.count]
        catalogCommand = next
        lastCatalogCommand = next
    }
    private func moveInsideCatalog(horizontal: Int, vertical: Int) {
        guard let console = catalogConsole else { return }
        let board = ConsoleCatalogNavigation(sections: catalogSections(for: console), columns: catalogColumns)
        if catalogCommand != nil {
            if horizontal != 0 { shiftCatalogCommand(horizontal) }
            else if vertical > 0, let first = board.first { catalogCommand = nil; focusCatalogItem(first) }
            return
        }
        let current = selectedCatalogFolderID.map { ConsoleCatalogNavigation.headerPrefix + $0 } ?? selectedGame?.id
        guard let first = board.first else { focusCatalogCommands(); return }
        let start = current.flatMap { board.contains($0) ? $0 : nil } ?? first
        if let next = board.move(from: start, horizontal: horizontal, vertical: vertical) {
            focusCatalogItem(next)
        } else if vertical < 0 {
            focusCatalogCommands()
        }
    }
    private func focusCatalogItem(_ id: String) {
        if id.hasPrefix(ConsoleCatalogNavigation.headerPrefix) {
            selectCatalogSection(String(id.dropFirst(ConsoleCatalogNavigation.headerPrefix.count)))
        } else if let game = listedGames.first(where: { $0.id == id }) { selectGame(game) }
    }
    func activateCatalogCommand() {
        guard let command = catalogCommand else { return }
        switch command {
        case .sortAZ: setCatalogSort(ascending: true)
        case .sortZA: setCatalogSort(ascending: false)
        case .folders: showCatalogFolders()
        case .minimize: toggleSectionOfSelection()
        case .reload: reloadCatalog()
        case .library: showLibrarySettings()
        case .filter:
            let current = libraryState(for: activeConsole).filter
            setCatalogFilter(current == .all ? .favorites : current == .favorites ? .recent : .all)
        case .favorite: toggleSelectedFavorite()
        case .density: toggleCatalogDensity()
        case .session: showSessionMenu()
        case .experience: showExperienceSettings()
        case .clearSearch: setCatalogQuery("")
        }
    }
    func availableFolderActions() -> [CatalogFolderAction] {
        guard let console = catalogConsole else { return [.create] }
        let folders = catalogFolders(for: console)
        var actions: [CatalogFolderAction] = []
        if !folders.isEmpty { actions.append(contentsOf: [.place, .rename, .delete]) }
        if let game = selectedGame, folders.contains(where: { $0.gameIDs.contains(game.id) }) {
            actions.append(.remove)
        }
        actions.append(.create)
        return actions
    }
    func performFolderAction(_ action: CatalogFolderAction) {
        catalogFolderAction = action
        guard let console = catalogConsole else { return }
        let folders = catalogFolders(for: console)
        let folder = folders.indices.contains(catalogFolderIndex) ? folders[catalogFolderIndex] : nil
        switch action {
        case .place:
            guard let folder else { catalogFolderMessage = "Create a folder to organize the games."; return }
            placeSelectedGame(in: folder.id)
        case .rename:
            guard let folder else { return }
            beginRenameCatalogFolder(folder.id)
        case .delete:
            guard let folder else { return }
            deleteCatalogFolder(folder.id)
        case .remove:
            clearSelectedGameFolder()
        case .create:
            if renamingFolderID != nil {
                confirmCatalogFolder()
                return
            }
            if CatalogNames.cleaned(folderDraft) != nil, let created = organizer.createFolder(named: folderDraft, console: console.rawValue) {
                folderDraft = ""
                renamingFolderID = nil
                catalogFolderMessage = "Folder \(created.name) created."
                catalogFolderIndex = max(0, organizer.layout(for: console.rawValue).folders.count - 1)
            } else if CatalogNames.cleaned(folderDraft) == nil {
                catalogFolderMessage = "Type the folder name."
            } else {
                catalogFolderMessage = "That folder already exists, or the limit of 20 was reached."
            }
        }
    }
    private func moveFolderList(_ direction: Int) {
        if catalogFolderAction != nil {
            if direction < 0 { catalogFolderAction = nil }
            return
        }
        guard let console = catalogConsole else { return }
        let folders = organizer.layout(for: console.rawValue).folders
        if folders.isEmpty {
            catalogFolderAction = .create
            return
        }
        let next = catalogFolderIndex + direction
        if next < 0 { return }
        if next >= folders.count {
            catalogFolderAction = availableFolderActions().first
            return
        }
        if renamingFolderID != nil {
            renamingFolderID = nil
            folderDraft = ""
        }
        catalogFolderIndex = next
    }
    private func moveFolderActions(_ direction: Int) {
        let actions = availableFolderActions()
        guard !actions.isEmpty else { return }
        guard let current = catalogFolderAction, let index = actions.firstIndex(of: current) else {
            catalogFolderAction = direction >= 0 ? actions.first : actions.last
            return
        }
        catalogFolderAction = actions[(index + direction + actions.count) % actions.count]
    }
    func setCatalogSort(ascending: Bool) {
        guard !showingExperienceSettings, !showingSessionMenu, dialog == nil else { return }
        guard let console = catalogConsole, !showingLibrarySettings, launching == nil,
              errorMessage == nil, storageNotice == nil else { return }
        withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.18)) {
            organizer.setAscending(ascending, console: console.rawValue)
        }
    }
    func toggleCatalogSection(_ sectionID: String) {
        guard let console = catalogConsole, !showingCatalogFolders else { return }
        withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.18)) {
            organizer.toggleCollapsed(sectionID, console: console.rawValue)
        }
        alignCatalogSelection()
    }
    func toggleSectionOfSelection() {
        if let id = selectedCatalogFolderID { toggleCatalogSection(id); return }
        guard let console = catalogConsole, let id = selectedGame?.id else { return }
        guard let section = catalogSections(for: console).first(where: { section in
            section.collapsible && section.games.contains { $0.id == id }
        }) else { return }
        toggleCatalogSection(section.id)
    }
    func showCatalogFolders() {
        guard !showingExperienceSettings, !showingSessionMenu, dialog == nil else { return }
        guard catalogConsole != nil, launching == nil, !booting, !showingLibrarySettings,
              errorMessage == nil, storageNotice == nil, NSApp.modalWindow == nil else { return }
        folderDraft = ""
        renamingFolderID = nil
        catalogFolderMessage = nil
        catalogFolderIndex = 0
        catalogFolderAction = nil
        showingCatalogFolders = true
    }
    func toggleCatalogFolders() {
        if catalogConsole == nil { showSessionMenu(); return }
        if showingCatalogFolders { dismissCatalogFolders() }
        else { showCatalogFolders() }
    }
    func dismissCatalogFolders() {
        showingCatalogFolders = false
        folderDraft = ""
        renamingFolderID = nil
        catalogFolderMessage = nil
        catalogFolderAction = nil
    }
    func beginRenameCatalogFolder(_ id: UUID) {
        guard let console = catalogConsole,
              let index = organizer.layout(for: console.rawValue).folders.firstIndex(where: { $0.id == id }) else { return }
        catalogFolderIndex = index
        renamingFolderID = id
        folderDraft = organizer.layout(for: console.rawValue).folders[index].name
        catalogFolderMessage = nil
    }
    func deleteCatalogFolder(_ id: UUID) {
        guard let console = catalogConsole else { return }
        let layout = organizer.layout(for: console.rawValue)
        let name = layout.folders.first { $0.id == id }?.name ?? "Folder"
        if renamingFolderID == id {
            renamingFolderID = nil
            folderDraft = ""
        }
        organizer.deleteFolder(id, console: console.rawValue)
        revealSection(CatalogGrouping.libraryID, console: console)
        let count = organizer.layout(for: console.rawValue).folders.count
        catalogFolderIndex = count == 0 ? 0 : min(catalogFolderIndex, count - 1)
        catalogFolderMessage = "\(name) deleted. The games stay in Library."
        alignCatalogSelection()
    }
    func placeSelectedGame(in folderID: UUID) {
        guard let console = catalogConsole, let game = selectedGame,
              let folder = organizer.layout(for: console.rawValue).folders.first(where: { $0.id == folderID }) else { return }
        organizer.place(gameID: game.id, in: folderID, console: console.rawValue)
        revealSection(folderID.uuidString, console: console)
        if let index = organizer.layout(for: console.rawValue).folders.firstIndex(where: { $0.id == folderID }) {
            catalogFolderIndex = index
        }
        catalogFolderMessage = "\(game.title) is in \(folder.name)."
    }
    func clearSelectedGameFolder() {
        guard let console = catalogConsole, let game = selectedGame else { return }
        organizer.place(gameID: game.id, in: nil, console: console.rawValue)
        revealSection(CatalogGrouping.libraryID, console: console)
        catalogFolderMessage = "\(game.title) returned to Library."
    }
    private func revealSection(_ sectionID: String, console: Console) {
        guard organizer.layout(for: console.rawValue).collapsed.contains(sectionID) else { return }
        organizer.toggleCollapsed(sectionID, console: console.rawValue)
    }
    func confirmCatalogFolder() {
        guard let console = catalogConsole else { return }
        let key = console.rawValue
        if let renaming = renamingFolderID {
            if organizer.renameFolder(renaming, to: folderDraft, console: key) {
                renamingFolderID = nil
                folderDraft = ""
                catalogFolderMessage = nil
            } else {
                catalogFolderMessage = "Use a new name, from 1 to 24 characters."
            }
            return
        }
        if CatalogNames.cleaned(folderDraft) != nil {
            if let folder = organizer.createFolder(named: folderDraft, console: key) {
                folderDraft = ""
                catalogFolderMessage = "Folder \(folder.name) created."
                catalogFolderIndex = max(0, organizer.layout(for: key).folders.count - 1)
            } else {
                catalogFolderMessage = "That folder already exists, or the limit of 20 was reached."
            }
            return
        }
        if !folderDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            catalogFolderMessage = "Use a name from 1 to 24 characters."
            return
        }
        let folders = organizer.layout(for: key).folders
        guard folders.indices.contains(catalogFolderIndex) else {
            catalogFolderMessage = "Create a folder to organize the games."
            return
        }
        placeSelectedGame(in: folders[catalogFolderIndex].id)
    }
    func showCatalog() {
        guard !showingExperienceSettings, !showingSessionMenu, dialog == nil else { return }
        guard launching == nil, errorMessage == nil, storageNotice == nil, NSApp.modalWindow == nil,
              !showingLibrarySettings, !showingCatalogFolders else { return }
        if catalogConsole != nil { reloadCatalog(); return }
        finishBoot()
        let console = catalogConsole ?? selected
        let entering = catalogConsole == nil
        catalogConsole = console
        if entering {
            catalogCommand = nil
            selectedCatalogFolderID = libraryState(for: console).selectedSectionID
            playSound(.confirm)
        }
        if isStorageAvailable(for: console) { catalog.refreshInBackground(console.rawValue) }
        else { catalog.refresh(console.rawValue, force: false) }
    }
    /// Full rescan of the visible console, including covers. From the menu it
    /// opens that console's catalog. A scan already in progress is left alone.
    func reloadCatalog() {
        guard !showingExperienceSettings, !showingSessionMenu, dialog == nil else { return }
        guard launching == nil, !booting, errorMessage == nil, storageNotice == nil,
              NSApp.modalWindow == nil, !showingLibrarySettings, !showingCatalogFolders else { return }
        let console = catalogConsole ?? selected
        guard !catalog.loading.contains(console.rawValue) else { return }
        catalogConsole = console
        catalog.refresh(console.rawValue, force: true)
        // The catalog derives progress from `loading`; a persistent menu notice
        // would outlive the scan and misleadingly claim it is still running.
        notice = ""
    }
    func confirm() {
        guard NSApp.modalWindow == nil else { return }
        if errorMessage != nil { errorMessage = nil; return }
        if let prompt = dialog {
            dialog = nil
            if dialogAcceptSelected { prompt.accept() }
            return
        }
        if showingExperienceSettings {
            if experience.confirmSelection() { showingExperienceSettings = false }
            return
        }
        if showingSessionMenu { activateSessionAction(); return }
        if storageNotice != nil { dismissStorageNotice(); return }
        if showingCatalogFolders {
            if renamingFolderID != nil { confirmCatalogFolder() }
            else if let action = catalogFolderAction { performFolderAction(action) }
            else { confirmCatalogFolder() }
            return
        }
        if showingLibrarySettings {
            if !choosingLibraryFolder { chooseLibraryFolder?(settingsConsole) }
            return
        }
        if booting { finishBoot() }
        else if launching != nil { skipStartup() }
        else if catalogConsole != nil {
            if catalogCommand != nil { activateCatalogCommand() }
            else if let folder = selectedCatalogFolderID { toggleCatalogSection(folder) }
            else if let game = selectedGame { launchGame(game) }
        }
        else { showCatalog() }
    }
    func back() {
        guard NSApp.modalWindow == nil else { return }
        if errorMessage != nil { errorMessage = nil; return }
        if dialog != nil { dialog = nil; return }
        if showingExperienceSettings { showingExperienceSettings = false; return }
        if showingSessionMenu { showingSessionMenu = false; return }
        if storageNotice != nil { dismissStorageNotice(); return }
        if showingCatalogFolders {
            if catalogFolderAction != nil { catalogFolderAction = nil; return }
            dismissCatalogFolders()
            return
        }
        if showingLibrarySettings { dismissLibrarySettings(); return }
        if booting { finishBoot() }
        else if launching != nil { cancelLaunch() }
        else if catalogConsole != nil {
            if catalogCommand != nil { catalogCommand = nil; return }
            rememberCatalogSelection()
            catalogConsole = nil
            selectedCatalogFolderID = nil
            playSound(.back)
        }
        else if fullscreen { toggleFullscreen?() }
    }
    func launch(_ console: Console) {
        guard !showingExperienceSettings, !showingSessionMenu, dialog == nil else { return }
        guard launching == nil, !booting, errorMessage == nil, storageNotice == nil,
              !showingLibrarySettings, !showingCatalogFolders, !stopping.contains(console) else { return }
        select(console)
        guard let url = console.applicationURL else {
            errorMessage = "Não encontramos \(console.emulator). Instale o emulador na pasta Aplicativos e tente novamente."
            return
        }
        launching = console
        launchID = UUID()
        launchURL = url
        launchGameURL = nil
        launchGameTitle = nil
        restartEmulator = nil
        isOpening = false
        notice = "Iniciando \(console.badge)…"
        playSound(.confirm)
        if let id = launchID, experience.startupMode != .full {
            let delay = UInt64((experience.startupMode.durationLimit ?? 0) * 1_000_000_000)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: delay)
                guard let self, self.launchID == id else { return }
                self.animationFinished(id)
            }
        }
    }
    func skipStartup() {
        guard let id = launchID, !isOpening else { return }
        animationFinished(id)
    }
    func cancelLaunch() {
        guard launching != nil, !isOpening || waitingForRestart else { return }
        let exitRequested = waitingForRestart
        clearLaunchState()
        notice = exitRequested ? "Inicialização cancelada; o encerramento do emulador já foi solicitado." : "Inicialização cancelada."
    }
    private func clearLaunchState() {
        launching = nil
        launchID = nil
        launchURL = nil
        launchGameURL = nil
        launchGameID = nil
        launchGameTitle = nil
        restartEmulator = nil
        waitingForRestart = false
        isOpening = false
    }
    func dismissStorageNotice() {
        storageNotice = nil
        refreshStorage()
        // Reconnecting never starts a game automatically; the user confirms again.
    }
    private func checkGameAccess(_ file: URL, title: String, console: Console) -> Bool {
        refreshStorage()
        guard isStorageAvailable(for: console) else {
            storageNotice = StorageNotice(gameTitle: title, consoleName: console.badge,
                volumeName: librarySettings.location(for: console.rawValue).volumeName)
            return false
        }
        guard GameLaunchCheck.isAvailable(file, library: gameFolder(for: console)) else {
            errorMessage = "Não foi possível acessar \(title). Confira os arquivos e as permissões na pasta do \(console.badge):\n\(gameFolder(for: console).path)\n\nUse Local dos jogos para corrigir a pasta ou Atualizar / R / R2+L2 para atualizar a biblioteca."
            return false
        }
        return true
    }
    func launchGame(_ game: CatalogGame) {
        guard !showingExperienceSettings, !showingSessionMenu, dialog == nil else { return }
        guard let console = Console(rawValue: game.consoleKey), launching == nil, !booting,
              errorMessage == nil, storageNotice == nil, !showingLibrarySettings, !showingCatalogFolders,
              !stopping.contains(console), NSApp.modalWindow == nil else { return }
        refreshSessions()
        let current = state(console)
        if current.isRunning && sameLoadedGame(game, path: current.gamePath) {
            returnToGame(console)
            return
        }
        guard checkGameAccess(game.fileURL, title: game.title, console: console) else { return }
        guard canOpenGame(console) else { return }
        if current.isRunning, let pid = current.pid {
            dialogAcceptSelected = false
            dialog = LauncherDialog(title: "Abrir \(game.title)?", message: "Para iniciar em tela cheia, precisamos fechar e reabrir \(console.emulator). Salve antes de continuar. O encerramento é normal e respeita as confirmações do emulador.", acceptTitle: "Abrir jogo") { [weak self] in
                guard let self else { return }
                self.refreshSessions()
                guard self.state(console).pid == pid, self.state(console).launchedAt == current.launchedAt,
                      self.canOpenGame(console) else { return }
                self.prepareGame(game, console: console, restart: (pid, current.launchedAt))
            }
            return
        }
        prepareGame(game, console: console, restart: nil)
    }
    private func prepareGame(_ game: CatalogGame, console: Console, restart: (pid: Int32, launchedAt: Date?)?) {
        launch(console)
        guard launching == console else { return }
        launchGameURL = game.fileURL
        launchGameID = game.id
        launchGameTitle = game.title
        restartEmulator = restart
        gameSelection[console.rawValue] = game.id
        rememberCatalogSelection()
    }
    var isSelectedGameRunning: Bool {
        guard let game = selectedGame, let console = Console(rawValue: game.consoleKey) else { return false }
        return state(console).isRunning && sameLoadedGame(game, path: state(console).gamePath)
    }
    func returnToGame(_ console: Console) {
        guard let pid = state(console).pid, let app = NSRunningApplication(processIdentifier: pid),
              app.bundleIdentifier == console.bundleID, !app.isTerminated else { return }
        app.activate(options: [])
    }
    private func sameLoadedGame(_ game: CatalogGame, path: String?) -> Bool {
        guard let path else { return false }
        let loaded = URL(fileURLWithPath: path).standardizedFileURL
        let requested = game.fileURL.standardizedFileURL
        if loaded.path == requested.path { return true }
        // Playlist/track ownership comes from the saved exact-member inventory,
        // never a filename resemblance or a scan of an unplugged drive.
        return resolvedSessionGameIDs[game.consoleKey] == game.id
    }
    private func canOpenGame(_ console: Console) -> Bool {
        let current = state(console)
        if current.isRunning && (current.gamePath != nil || current.activityDescription != "Emulator open · no game detected") {
            errorMessage = "\(console.emulator) já tem uma sessão aberta ou ainda não foi possível confirmar seu estado. Encerre o jogo atual no emulador e tente novamente. A central não trocará o disco nem interromperá seu jogo."
            return false
        }
        return true
    }
    func animationFinished(_ id: UUID) {
        guard launchID == id, let console = launching, let url = launchURL, !isOpening else { return }
        refreshSessions()
        if let gameURL = launchGameURL {
            guard checkGameAccess(gameURL, title: launchGameTitle ?? gameURL.deletingPathExtension().lastPathComponent, console: console), canOpenGame(console) else {
                cancelLaunch()
                return
            }
        }
        isOpening = true
        notice = "Abrindo \(console.emulator)…"
        openingText = notice
        if launchGameURL != nil, state(console).isRunning {
            guard let accepted = restartEmulator, accepted.pid == state(console).pid,
                  accepted.launchedAt == state(console).launchedAt, let pid = state(console).pid,
                  let app = NSRunningApplication(processIdentifier: pid), app.bundleIdentifier == console.bundleID else {
                finishLaunch(id, console: console, app: nil, error: nil)
                errorMessage = "A sessão de \(console.emulator) mudou durante a animação. Nenhuma outra sessão foi encerrada. Tente novamente."
                return
            }
            openingText = "Reabrindo \(console.emulator)…"
            waitingForRestart = true
            app.activate(options: [])
            guard app.terminate() else {
                finishLaunch(id, console: console, app: nil, error: nil)
                return
            }
            Task { @MainActor [weak self] in
                for _ in 0..<60 {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard let self, self.launchID == id else { return }
                    if app.isTerminated {
                        self.openRequestedApplication(id, console: console, url: url)
                        return
                    }
                }
                guard let self, self.launchID == id else { return }
                self.finishLaunch(id, console: console, app: nil, error: nil)
                self.errorMessage = "\(console.emulator) continua aberto. Confirme ou cancele a saída no emulador e tente novamente. Nada foi encerrado à força."
            }
            return
        }
        openRequestedApplication(id, console: console, url: url)
    }
    private func openRequestedApplication(_ id: UUID, console: Console, url: URL) {
        guard launchID == id else { return }
        waitingForRestart = false
        openingText = "Abrindo \(console.emulator)…"
        if let gameURL = launchGameURL,
           !checkGameAccess(gameURL, title: launchGameTitle ?? gameURL.deletingPathExtension().lastPathComponent, console: console) {
            clearLaunchState()
            notice = ""
            return
        }
        if launchGameURL != nil {
            refreshSessions()
            guard canOpenGame(console), !state(console).isRunning else {
                let explanation = errorMessage
                finishLaunch(id, console: console, app: nil, error: nil)
                errorMessage = explanation ?? "\(console.emulator) abriu antes de enviarmos o jogo. Encerre essa sessão e tente novamente."
                return
            }
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        configuration.allowsRunningApplicationSubstitution = false
        let completion: @Sendable (NSRunningApplication?, Error?) -> Void = { [weak self] app, error in
            Task { @MainActor in
                self?.finishLaunch(id, console: console, app: app, error: error)
            }
        }
        if let game = launchGameURL {
            configuration.arguments = EmulatorLaunchArguments.game(game)
            NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: completion)
        } else {
            NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: completion)
        }
    }
    private func finishLaunch(_ id: UUID, console: Console, app: NSRunningApplication?, error: Error?) {
        guard launchID == id else { return }
        let title = launchGameTitle
        let validApp = app.flatMap { !$0.isTerminated && $0.bundleIdentifier == console.bundleID ? $0 : nil }
        if error == nil, let app = validApp, let gameURL = launchGameURL {
            let record = OwnedGameSession(consoleKey: console.rawValue, pid: app.processIdentifier, launchedAt: app.launchDate,
                                          gameID: launchGameID ?? gameURL.path, gameURL: gameURL,
                                          libraryRoot: gameFolder(for: console))
            ownedSessions[console.rawValue] = record
            pendingHistory.insert(console.rawValue)
        }
        clearLaunchState()
        refreshSessions()
        if let error {
            notice = ""
            errorMessage = "Não foi possível abrir \(console.emulator). \(error.localizedDescription)"
        } else if validApp != nil {
            notice = title.map { "\($0) enviado para \(console.emulator)." } ?? "\(console.emulator) está aberto. Bom jogo!"
        } else {
            notice = ""
            errorMessage = "Não foi possível concluir a abertura de \(console.emulator). Confira a janela dele e tente novamente."
        }
    }
    func requestStop(_ console: Console) {
        guard !hasOverlay else { return }
        guard launching == nil, storageNotice == nil, !stopping.contains(console), NSApp.modalWindow == nil else { return }
        refreshSessions()
        guard let pid = state(console).pid else { return }
        let launchedAt = state(console).launchedAt
        dialogAcceptSelected = false
        dialog = LauncherDialog(title: "Desligar \(console.badge)?", message: "Salve seu jogo antes de continuar. Vamos solicitar a saída normal de \(console.emulator), sem forçar o encerramento. Uma confirmação adicional pode aparecer no emulador.", acceptTitle: "Desligar") { [weak self] in
            self?.stopConfirmed(console, pid: pid, launchedAt: launchedAt)
        }
    }
    private func stopConfirmed(_ console: Console, pid: Int32, launchedAt: Date?) {
        guard let app = NSRunningApplication(processIdentifier: pid), app.launchDate == launchedAt,
              app.bundleIdentifier == console.bundleID, !app.isTerminated else { return }
        stopping.insert(console)
        stopDeadlines[console] = Date().addingTimeInterval(15)
        notice = "Solicitando saída de \(console.emulator)…"
        app.activate(options: [])
        if !app.terminate() {
            stopping.remove(console)
            stopDeadlines.removeValue(forKey: console)
            errorMessage = "\(console.emulator) não aceitou o pedido de saída. Salve o jogo e saia pelo menu do próprio emulador."
        }
        refreshSessions()
    }
    private func sessionTerminated(_ app: NSRunningApplication) {
        guard let pair = ownedSessions.first(where: { $0.value.matches(pid: app.processIdentifier, launchedAt: app.launchDate) }) else { return }
        ownedSessions.removeValue(forKey: pair.key)
        pendingHistory.remove(pair.key)
        refreshSessions()
        guard launching == nil, let console = Console(rawValue: pair.key) else { return }
        notice = "Sessão encerrada · \(console.badge)"
        // Do not steal focus from a different foreground app or overwrite a dialog.
        guard !hasOverlay, lastFrontmostPID == app.processIdentifier || NSApp.isActive else { return }
        selected = console
        catalogConsole = console
        catalogCommand = nil
        selectedCatalogFolderID = nil
        gameSelection[pair.key] = pair.value.gameID
        returnToLauncher?()
    }
    var storageText: String {
        let console = catalogConsole ?? selected
        let location = librarySettings.location(for: console.rawValue)
        if storageMounted { return notice.isEmpty ? "\(location.volumeName) · \(console.badge)" : notice }
        return "\(location.volumeName) desconectado · Biblioteca salva disponível"
    }
}

// Native vector animation. No video, BIOS resources or network requests.
struct SystemScene: View {
    let active: Bool
    let reduceMotion: Bool
    let booting: Bool
    let startedAt: Date
    let showOrbs: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !active || reduceMotion)) { timeline in
            Canvas { context, size in
                let t = reduceMotion ? 0.0 : timeline.date.timeIntervalSince(startedAt)
                let sx = size.width / 1100
                let sy = size.height / 700
                let center = CGPoint(x: size.width * (booting ? 0.5 : 0.285), y: size.height * 0.49)
                let radius = 122.0 * min(sx, sy)
                let entire = Path(CGRect(origin: .zero, size: size))
                // Match the full-window backdrop when the menu stops growing;
                // a separate gradient here would expose a rectangular edge.
                context.fill(entire, with: .color(Theme.background))
                if showOrbs {
                    context.fill(entire, with: .radialGradient(Gradient(colors: [Theme.blue.opacity(0.15), .clear]),
                                 center: center, startRadius: 10, endRadius: radius * 3))
                }
                for index in 0..<18 {
                    let x = Double((index * 193 + 43) % 1100) * sx
                    let width = Double(18 + (index * 13) % 42) * sx
                    let height = Double(55 + (index * 61) % 180) * sy
                    let y = size.height * 0.84 + sin(t * 0.17 + Double(index)) * 6
                    let rect = CGRect(x: x, y: y - height, width: width, height: height)
                    let opacity = booting ? 0.10 : 0.028
                    context.fill(Path(rect), with: .linearGradient(Gradient(colors: [Theme.ice.opacity(opacity), .clear]),
                                 startPoint: CGPoint(x: x, y: rect.minY), endPoint: CGPoint(x: x, y: y)))
                    var cap = Path()
                    cap.move(to: CGPoint(x: x, y: rect.minY))
                    cap.addLine(to: CGPoint(x: x + width * 0.25, y: rect.minY - 9 * sy))
                    cap.addLine(to: CGPoint(x: x + width * 1.25, y: rect.minY - 9 * sy))
                    cap.addLine(to: CGPoint(x: x + width, y: rect.minY))
                    cap.closeSubpath()
                    context.fill(cap, with: .color(Theme.ice.opacity(opacity * 0.6)))
                }
                for index in 0..<44 {
                    let x = Double((index * 223 + 67) % 1100) * sx
                    let y = Double((index * 97 + 23) % 700) * sy + sin(t * 0.12 + Double(index)) * 7
                    let alpha = 0.10 + (sin(t * 0.4 + Double(index)) + 1) * 0.08
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.3, height: 1.3)), with: .color(Theme.ice.opacity(alpha)))
                }
                for index in 0..<(showOrbs ? 8 : 0) {
                    let angle = Double(index) / 8 * .pi * 2 + t * 0.28
                    let x = center.x + cos(angle) * radius
                    let y = center.y + sin(angle) * radius * 0.78
                    let dot = (5.5 + (sin(angle) + 1) * 1.75) * min(sx, sy)
                    let glow = dot * 4.8
                    let point = CGPoint(x: x, y: y)
                    context.fill(Path(ellipseIn: CGRect(x: x - glow, y: y - glow, width: glow * 2, height: glow * 2)),
                                 with: .radialGradient(Gradient(colors: [Theme.blue.opacity(0.7), Theme.blue.opacity(0.17), .clear]),
                                                       center: point, startRadius: 0, endRadius: glow))
                    context.fill(Path(ellipseIn: CGRect(x: x - dot, y: y - dot, width: dot * 2, height: dot * 2)),
                                 with: .radialGradient(Gradient(colors: [.white, Theme.ice, Theme.blue]), center: point,
                                                       startRadius: 0, endRadius: dot))
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Original arcade-style Player 1 cursor, drawn locally without image assets.
struct PlayerOneIndicator: View {
    static let width: CGFloat = 32
    let selected: Bool

    private var outline: Path {
        Path { path in
            path.move(to: CGPoint(x: 3, y: 2))
            path.addLine(to: CGPoint(x: 25, y: 2))
            path.addLine(to: CGPoint(x: 31, y: 12))
            path.addLine(to: CGPoint(x: 25, y: 22))
            path.addLine(to: CGPoint(x: 3, y: 22))
            path.addLine(to: CGPoint(x: 1, y: 20))
            path.addLine(to: CGPoint(x: 1, y: 4))
            path.closeSubpath()
        }
    }

    var body: some View {
        ZStack {
            outline.fill(LinearGradient(colors: [Theme.blue.opacity(0.65), Theme.blue.opacity(0.18)],
                                        startPoint: .leading, endPoint: .trailing))
            outline.stroke(Theme.ice.opacity(0.9), lineWidth: 1)
            Text("P1").font(.system(size: 14, weight: .black, design: .monospaced)).italic()
                .tracking(-0.5).foregroundStyle(Color.white).offset(x: -2)
        }
        .frame(width: Self.width, height: 24)
        .shadow(color: Theme.blue.opacity(0.5), radius: 5)
        .opacity(selected ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ConsoleOption: View {
    let console: Console
    @ObservedObject var model: LauncherModel
    @ObservedObject private var catalog: GameCatalog

    init(console: Console, model: LauncherModel) {
        self.console = console
        self.model = model
        _catalog = ObservedObject(wrappedValue: model.catalog)
    }
    var selected: Bool { model.selected == console }
    var session: EmulatorState { model.state(console) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Button { model.openConsoleCatalog(console) } label: {
            HStack(spacing: 15) {
                PlayerOneIndicator(selected: selected)
                if let image = Theme.images[console.asset] {
                    Image(nsImage: image).resizable().interpolation(.high).scaledToFit().frame(width: 76, height: 54)
                        .shadow(color: Theme.blue.opacity(selected ? 0.45 : 0), radius: 14).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text(console.name).font(.system(size: 23, weight: .regular, design: .rounded))
                        .foregroundStyle(selected ? Color.white : Theme.pale.opacity(0.56))
                        .shadow(color: Theme.ice.opacity(selected ? 0.45 : 0), radius: 7)
                    Text(console.controller + "  ·  " + console.emulator).font(.system(size: 11)).tracking(0.4)
                        .foregroundStyle(Theme.pale.opacity(selected ? 0.78 : 0.58))
                }
                Spacer(minLength: 0)
                if model.launching == console { ProgressView().controlSize(.small) }
                else if selected { Image(systemName: "chevron.right").font(.system(size: 13, weight: .light)).foregroundStyle(Theme.ice) }
            }
            .padding(.horizontal, 13).frame(height: 76).contentShape(Rectangle())
          }
          .buttonStyle(.plain).disabled(model.launching != nil || model.stopping.contains(console))
          .accessibilityLabel("Entrar na biblioteca do \(console.name)")
          .accessibilityValue(selected ? "Selected · P1, player 1" : "")
          .help("Entrar no ambiente do \(console.badge) e escolher um jogo")
          HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(session.isRunning ? Color.green : Theme.pale.opacity(0.3)).frame(width: 5, height: 5)
                    Text(session.isRunning ? "ON" : "OFF").font(.system(size: 9, weight: .semibold)).tracking(1)
                    if session.isRunning {
                        Text("·  " + model.uptime(console)).font(.system(size: 11, design: .monospaced))
                            .accessibilityLabel("Time on: \(model.uptime(console))")
                    }
                }.foregroundStyle(session.isRunning ? Theme.ice : Theme.pale.opacity(0.6))
                if session.isRunning, let title = session.gameTitle, let path = session.gamePath {
                    NowPlayingGameView(consoleKey: console.rawValue, title: title, gamePath: path,
                                       revision: catalog.revisions[console.rawValue] ?? 0,
                                       source: catalog.source(for: console.rawValue))
                        .id(path)
                } else {
                    Text(session.isRunning ? session.gameTitle ?? "Emulador aberto" : "Sua biblioteca está pronta")
                        .font(.system(size: 12)).foregroundStyle(Theme.pale.opacity(0.65))
                        .lineLimit(1).truncationMode(.middle)
                        .help(session.activityDescription)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if session.isRunning {
                Button { model.requestStop(console) } label: {
                    Label(model.stopping.contains(console) ? "Saindo…" : "Desligar", systemImage: "power")
                        .font(.system(size: 11)).padding(.horizontal, 10).padding(.vertical, 7)
                        .foregroundStyle(Color(red: 1, green: 0.65, blue: 0.64))
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                }.buttonStyle(.plain).disabled(model.stopping.contains(console) || model.launching != nil)
                 .accessibilityLabel("Turn off \(console.badge) — \(console.emulator)")
            }
          }.padding(.leading, 13 + PlayerOneIndicator.width + 15).padding(.trailing, 13).frame(height: 73, alignment: .top)
        }
        .background(LinearGradient(colors: [Theme.blue.opacity(selected ? 0.13 : 0), Theme.blue.opacity(selected ? 0.035 : 0), .clear], startPoint: .leading, endPoint: .trailing))
        .overlay(alignment: .bottom) {
            Rectangle().fill(LinearGradient(colors: [Theme.ice.opacity(selected ? 0.32 : 0.04), .clear], startPoint: .leading, endPoint: .trailing)).frame(height: 1)
        }
        .onHover { inside in model.setConsoleHover(console, inside: inside) }
    }
}

struct ConsolePreview: View {
    let console: Console
    let reducedMotion: Bool
    let size: CGSize

    var body: some View {
        VStack(spacing: 12) {
            HoverAnimationView(resourceName: console == .ps1 ? "PS1Startup" : "PS2Startup", reducedMotion: reducedMotion)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.ice.opacity(0.18), lineWidth: 1))
                .shadow(color: Theme.blue.opacity(0.10), radius: 16)
            HStack(spacing: 8) {
                Text(console.badge).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.ice)
                Text("Escolha seu console. Reviva seus jogos.").font(.system(size: 10)).foregroundStyle(Theme.pale.opacity(0.65))
            }
        }
        .allowsHitTesting(false)
    }
}

struct SystemMenu: View {
    @ObservedObject var model: LauncherModel
    let layout: LauncherLayout
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                if let logo = Theme.images["Logo"] {
                    Image(nsImage: logo).resizable().scaledToFit().frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10)).accessibilityLabel("PlayStation logo")
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("PS1/2").font(.system(size: 27, weight: .light, design: .rounded)).tracking(3)
                        .foregroundStyle(Theme.ice).shadow(color: Theme.blue.opacity(0.7), radius: 12)
                    Text("PlayStation Retro Emulator").font(.system(size: 9, weight: .medium)).tracking(1.5)
                        .foregroundStyle(Theme.pale.opacity(0.6))
                }
                Spacer()
                Button { model.showSessionMenu() } label: {
                    Label("Opções", systemImage: "slider.horizontal.3")
                        .font(.system(size: 11)).foregroundStyle(Theme.ice.opacity(0.85))
                }.buttonStyle(.plain).help("Sessão, ambiente e pastas · Options / S")
                TimelineView(.periodic(from: .now, by: 30)) { time in
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(time.date, format: .dateTime.hour().minute()).font(.system(size: 16, weight: .regular, design: .monospaced))
                    }
                }.foregroundStyle(Theme.pale.opacity(0.68))
            }.padding(.top, 42)
            Group {
                if layout.stacksMenu {
                    VStack(spacing: 32) { preview; consoleChoices }
                } else {
                    HStack(spacing: 32) { preview; consoleChoices }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 21) {
                Rectangle().fill(LinearGradient(colors: [.clear, Theme.ice.opacity(0.19), .clear], startPoint: .leading, endPoint: .trailing)).frame(height: 1)
                HStack(spacing: 24) {
                    Button { model.confirm() } label: { hint("×", "Entrar", "Enter", Theme.ice) }
                    Button { model.back() } label: { hint("○", "Voltar", "Esc", Color(red: 0.92, green: 0.49, blue: 0.51)) }
                    Button { model.toggleFullscreen?() } label: { hint("□", model.fullscreen ? "Janela" : "Tela cheia", "F", Color(red: 0.83, green: 0.58, blue: 0.80)) }
                    Button { model.showCatalog() } label: { hint("△", "Jogos \(model.selected.badge)", "T", Color(red: 0.4, green: 0.9, blue: 0.68)) }
                        .accessibilityLabel("List \(model.selected.badge) games")
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.arrow.down").font(.system(size: 12))
                        Text("Selecionar").font(.system(size: 12))
                    }.foregroundStyle(Theme.pale.opacity(0.52))
                     .help("Arrow keys, D-pad or left stick to select")
                }.buttonStyle(.plain)
                HStack(spacing: 7) {
                    Circle().fill(model.storageMounted ? Theme.ice.opacity(0.8) : Color.orange).frame(width: 4, height: 4)
                    Text(model.storageText).font(.system(size: 10)).tracking(0.2)
                        .lineLimit(1).truncationMode(.middle)
                        .help(model.gameFolder(for: model.catalogConsole ?? model.selected).path)
                    Spacer()
                    if let name = model.controllerName {
                        Image(systemName: "gamecontroller").font(.system(size: 12))
                        Text(name).font(.system(size: 10))
                    }
                }.foregroundStyle(Theme.pale.opacity(0.62))
            }.padding(.bottom, 31)
        }.padding(.horizontal, layout.horizontalPadding)
            .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
    }
    private var preview: some View {
        ZStack {
            if let console = model.previewConsole {
                ConsolePreview(console: console, reducedMotion: model.reduceMotion,
                               size: CGSize(width: layout.previewWidth, height: layout.previewHeight))
                    .id(console)
            }
        }.frame(width: layout.previewColumnWidth, height: layout.previewHeight + 38)
    }
    private var consoleChoices: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Emulador").font(.system(size: 32, weight: .light, design: .rounded))
                .foregroundStyle(Theme.pale).shadow(color: Theme.blue.opacity(0.25), radius: 9).padding(.bottom, 9)
            Text("Dois consoles. Duas gerações. Sua coleção.").font(.system(size: 12)).tracking(0.6)
                .foregroundStyle(Theme.pale.opacity(0.62)).padding(.bottom, 18)
            ConsoleOption(console: .ps1, model: model)
            ConsoleOption(console: .ps2, model: model)
        }.frame(width: layout.optionWidth)
    }
    private func hint(_ symbol: String, _ label: String, _ key: String, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Text(symbol).font(.system(size: 21, weight: .regular)).foregroundStyle(color)
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.pale.opacity(0.9))
            Text(key).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.pale.opacity(0.55))
        }.contentShape(Rectangle())
    }
}

struct BootOverlay: View {
    @ObservedObject var model: LauncherModel
    var body: some View {
        VStack(spacing: 15) {
            Spacer()
            Text("PS1/2").font(.system(size: 62, weight: .ultraLight, design: .rounded)).tracking(11)
                .foregroundStyle(.white).shadow(color: Theme.blue, radius: 28)
            Text("PlayStation Retro Emulator").font(.system(size: 10, weight: .light)).tracking(4)
                .foregroundStyle(Theme.ice.opacity(0.7))
            Spacer()
            Button("Enter ou clique para continuar") { model.finishBoot() }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.pale.opacity(0.5)).padding(.bottom, 49)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle()).onTapGesture { model.finishBoot() }
    }
}

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    var body: some View {
        GeometryReader { geometry in
            let layout = LauncherLayout(size: geometry.size)
            ZStack {
                ConsolePalette.forConsole(model.activeConsole).background
                ConsoleAtmosphere(console: model.activeConsole, active: model.isForeground && model.launching == nil && !model.hasOverlay, reduceMotion: model.reduceMotion)
                    .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
                ZStack {
                    if model.booting { BootOverlay(model: model).transition(.opacity) }
                    else if let console = model.catalogConsole {
                        GameCatalogView(console: console, layout: layout, model: model, catalog: model.catalog).transition(.opacity)
                    } else { SystemMenu(model: model, layout: layout).transition(.opacity) }
                }.frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
                    .accessibilityHidden(model.launching != nil || (model.hasOverlay && !model.showingCatalogFolders))
                    .allowsHitTesting(model.launching == nil && (!model.hasOverlay || model.showingCatalogFolders))
                    .disabled(model.hasOverlay && !model.showingCatalogFolders)
                if model.showingLibrarySettings {
                    LibrarySettingsView(model: model, settings: model.librarySettings)
                        .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
                        .zIndex(5)
                }
                if model.showingSessionMenu {
                    SessionMenuView(model: model)
                        .frame(width: layout.canvasSize.width, height: layout.canvasSize.height).zIndex(6)
                }
                if model.showingExperienceSettings {
                    ExperienceSettingsView(preferences: model.experience, console: model.activeConsole) { model.showingExperienceSettings = false }
                        .frame(width: layout.canvasSize.width, height: layout.canvasSize.height).zIndex(7)
                }
                if let console = model.launching, let id = model.launchID {
                    Color.black.ignoresSafeArea()
                    VStack(spacing: 18) {
                        HStack {
                            Text("INICIANDO \(console.badge)").tracking(3)
                            Spacer()
                            if !model.isOpening {
                                Button("Pular · × / Enter") { model.skipStartup() }.buttonStyle(.plain)
                            }
                            if !model.isOpening || model.waitingForRestart {
                                Button("Cancelar · ○ / Esc") { model.cancelLaunch() }.buttonStyle(.plain)
                            }
                        }.font(.system(size: 12)).foregroundStyle(Theme.pale.opacity(0.6))
                        if model.isOpening {
                            Spacer()
                            ProgressView(model.openingText).foregroundStyle(Theme.ice)
                            Spacer()
                        } else if model.experience.startupMode != .off {
                            StartupAnimationView(resourceName: console == .ps1 ? "PS1Startup" : "PS2Startup", reducedMotion: model.reduceMotion) {
                                model.animationFinished(id)
                            }.id(id)
                            Text(model.launchGameTitle.map { "\($0) · \(console.emulator)" } ?? "Preparando \(console.badge)")
                                .font(.system(size: 11)).foregroundStyle(Theme.pale.opacity(0.4))
                        }
                    }.padding(35).frame(maxWidth: 1000, maxHeight: .infinity)
                }
                if let notice = model.storageNotice {
                    StorageNoticeView(notice: notice, onDismiss: model.dismissStorageNotice)
                        .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
                        .zIndex(10)
                }
                if model.dialog != nil || model.errorMessage != nil {
                    LauncherMessageView(model: model)
                        .frame(width: layout.canvasSize.width, height: layout.canvasSize.height).zIndex(11)
                }
            }.frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
                .scaleEffect(layout.scale, anchor: .center)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}

/// The running tile can be replaced in memory. After quit, the Dock asks
/// Launch Services, which may still have an older copy of this bundle id
/// (a backup or the Trash) and therefore the previous logo.
private enum DockIconRefresh {
    private static let defaultsKey = "PS12PublishedDockIcon"
    private static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    static func applyRunningIcon() {
        guard let icon = currentIcon() else { return }
        NSApp.applicationIconImage = icon.image
    }

    static func publishQuitIconIfNeeded() {
        guard let icon = currentIcon() else { return }
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL.resolvingSymlinksInPath()
        guard isInstalledApp(bundleURL),
              UserDefaults.standard.string(forKey: defaultsKey) != icon.token else { return }
        let mine = bundleURL.path
        DispatchQueue.global(qos: .utility).async {
            guard reregister(mine: mine) else { return }
            DispatchQueue.main.async {
                UserDefaults.standard.set(icon.token, forKey: defaultsKey)
            }
        }
    }

    private static func currentIcon() -> (image: NSImage, token: String)? {
        let bundle = Bundle.main
        guard let name = bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String,
              let url = bundle.url(forResource: name, withExtension: "icns"),
              let image = NSImage(contentsOf: url) else { return nil }
        let version = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let bytes = values?.fileSize ?? 0
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        return (image, "\(name)|\(version)|\(bytes)|\(modified)")
    }

    private static func isInstalledApp(_ url: URL) -> Bool {
        let path = url.path
        if path.hasPrefix("/private/tmp/") || path.hasPrefix("/tmp/") || path.hasPrefix("/var/folders/") { return false }
        return path.hasSuffix(".app")
    }

    private static func reregister(mine: String) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: lsregister) else { return false }
        // Publish only our own bundle. Opening the launcher must not restart
        // the user's Dock, erase system caches or unregister other checkouts.
        return run(lsregister, ["-f", mine])
    }

    private static func run(_ launchPath: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

// Borderless fullscreen keeps the console menu on the current desktop and
// avoids Spaces restoring the window when an external emulator receives focus.
final class LauncherWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Keeps SwiftUI matched to the window. Using a hosting view directly as the
/// content view leaves the ideal 1100×700 size in place when the window is
/// zoomed or moved to another display.
final class LauncherContentView: NSView {
    private let hosting: NSHostingView<LauncherView>
    private var layingOut = false

    init(model: LauncherModel) {
        hosting = NSHostingView(rootView: LauncherView(model: model))
        super.init(frame: .zero)
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.autoresizingMask = [.width, .height]
        hosting.setContentHuggingPriority(.defaultLow, for: .horizontal)
        hosting.setContentHuggingPriority(.defaultLow, for: .vertical)
        hosting.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hosting.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        addSubview(hosting)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func layout() {
        guard !layingOut else { return }
        layingOut = true
        defer { layingOut = false }
        if hosting.frame != bounds { hosting.frame = bounds }
        super.layout()
    }
}

#if !LAUNCHER_MODEL_TESTS
@main
#endif
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private let model = LauncherModel()
    private var keyMonitor: Any?
    private var controllerInput: ControllerInput?
    private var navigationObserver: AnyCancellable?
    private var normalWindowFrame: NSRect?
    private let normalStyle: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        DockIconRefresh.applyRunningIcon()
        DockIconRefresh.publishQuitIconIfNeeded()
        createMenu()
        window = LauncherWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                                styleMask: normalStyle, backing: .buffered, defer: false)
        window.title = "PS1/2"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 1000, height: 650)
        window.collectionBehavior = [.fullScreenNone]
        window.contentView = LauncherContentView(model: model)
        fitInitialWindowToScreen()
        window.center()
        configureWindowButton()
        model.toggleFullscreen = { [weak self] in self?.toggleFullscreen() }
        model.returnToLauncher = { [weak self] in self?.showWindow() }
        model.chooseLibraryFolder = { [weak self] in self?.chooseGameFolder($0) }
        controllerInput = ControllerInput(onMove: { [weak self] direction in self?.handleController { $0.move(direction) } },
                                          onVerticalMove: { [weak self] direction in self?.handleController { $0.moveVertical(direction) } },
                                          onConfirm: { [weak self] in self?.handleController { $0.confirm() } },
                                          onBack: { [weak self] in self?.handleController { $0.back() } },
                                          onFullscreen: { [weak self] in self?.handleController { $0.toggleFullscreen?() } },
                                          onCatalog: { [weak self] in self?.handleController { $0.showCatalog() } },
                                          onReload: { [weak self] in self?.handleController { $0.reloadCatalog() } },
                                          onSort: { [weak self] ascending in self?.handleController { $0.setCatalogSort(ascending: ascending) } },
                                          onFolders: { [weak self] in self?.handleController { $0.toggleCatalogFolders() } },
                                          navigationContext: { [weak self] in self?.analogNavigationContext },
                                          repeatsAnalog: { [weak self] in
                                              guard let self else { return false }
                                              return self.model.catalogConsole != nil && !self.model.showingLibrarySettings
                                          },
                                          onConnectionChanged: { [weak self] in self?.model.controllerName = $0 })
        controllerInput?.start()
        // Sample neutral when a screen changes even if no stick event arrives.
        // @Published emits before mutation, so read the settled model next turn.
        navigationObserver = Publishers.CombineLatest4(model.$booting, model.$catalogConsole,
                                                       model.$launching, model.$errorMessage)
            .combineLatest(model.$storageNotice)
            .combineLatest(model.$showingLibrarySettings, model.$choosingLibraryFolder, model.$showingCatalogFolders)
            .map { combined, settings, choosing, organizing -> String? in
                let (state, storage) = combined
                let (booting, console, launching, error) = state
                guard !booting, launching == nil, error == nil, storage == nil, !choosing else { return nil }
                if settings { return "library-settings" }
                if organizing { return "catalog-folders" }
                return console.map { "catalog-\($0.rawValue)" } ?? "menu"
            }
            .combineLatest(model.$dialog.map { $0 != nil }, model.$showingExperienceSettings, model.$showingSessionMenu)
            .map { base, dialog, experience, session -> String? in
                if dialog { return "dialog" }
                if experience { return "experience" }
                if session { return "session" }
                return base
            }
            .removeDuplicates()
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in self?.controllerInput?.refreshAnalogNavigation() }
            }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self else { return false }
                return self.handleKey(event) == nil
            }
            return handled ? nil : event
        }
        showWindow()
    }
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard NSApp.isActive, NSApp.keyWindow === window, window?.attachedSheet == nil,
              NSApp.modalWindow == nil, !model.choosingLibraryFolder else { return event }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if model.dialog != nil || model.errorMessage != nil || model.showingSessionMenu || model.showingExperienceSettings {
            if modifiers.contains(.command) { return event }
            switch event.keyCode {
            case 53: model.back()
            case 36, 76: if !event.isARepeat { model.confirm() }
            case 123: model.move(-1)
            case 124: model.move(1)
            case 125: model.moveVertical(1)
            case 126: model.moveVertical(-1)
            default: return event.keyCode == 48 ? event : nil
            }
            return nil
        }
        // Text entry owns letters, arrows and standard editing shortcuts. In
        // particular typing F/R/T in search must never launch another action.
        if let editor = window.firstResponder as? NSTextView, editor.isEditable {
            if event.keyCode == 53 { window.makeFirstResponder(nil); return nil }
            return event
        }
        if model.storageNotice != nil {
            // Keep system shortcuts and Tab navigation, but no console/game
            // shortcuts may act through the storage dialog.
            if modifiers.contains(.command) { return event }
            if event.keyCode == 53 { model.back(); return nil }
            if [36, 76].contains(event.keyCode), !event.isARepeat { model.confirm(); return nil }
            return event.keyCode == 48 ? event : nil
        }
        if model.showingCatalogFolders {
            if event.keyCode == 53 { model.back(); return nil }
            if [123, 124, 125, 126].contains(event.keyCode) {
                if event.keyCode == 123 { model.move(-1) }
                else if event.keyCode == 124 { model.move(1) }
                else if event.keyCode == 126 { model.moveVertical(-1) }
                else { model.moveVertical(1) }
                return nil
            }
            if [36, 76].contains(event.keyCode), !event.isARepeat { model.confirm(); return nil }
            return event
        }
        if modifiers.contains(.command) {
            if event.charactersIgnoringModifiers == "," { model.showLibrarySettings(); return nil }
            if model.showingLibrarySettings { return event }
            if event.charactersIgnoringModifiers == "1" { model.finishBoot(); model.openConsoleCatalog(.ps1); return nil }
            if event.charactersIgnoringModifiers == "2" { model.finishBoot(); model.openConsoleCatalog(.ps2); return nil }
            return event
        }
        if modifiers.contains(.control) || modifiers.contains(.option) { return event }
        switch event.keyCode {
        case 123: if !event.isARepeat || model.catalogConsole != nil { model.move(-1) }; return nil
        case 124: if !event.isARepeat || model.catalogConsole != nil { model.move(1) }; return nil
        case 126: if !event.isARepeat || model.catalogConsole != nil { model.moveVertical(-1) }; return nil
        case 125: if !event.isARepeat || model.catalogConsole != nil { model.moveVertical(1) }; return nil
        case 36, 76: if !event.isARepeat { model.confirm() }; return nil
        case 53: model.back(); return nil
        default:
            if event.charactersIgnoringModifiers?.lowercased() == "f", !event.isARepeat { toggleFullscreen(); return nil }
            if event.charactersIgnoringModifiers?.lowercased() == "t", !event.isARepeat { model.showCatalog(); return nil }
            if event.charactersIgnoringModifiers?.lowercased() == "r", !event.isARepeat { model.reloadCatalog(); return nil }
            if event.charactersIgnoringModifiers?.lowercased() == "s", !event.isARepeat { model.showSessionMenu(); return nil }
            if model.catalogConsole != nil, !model.showingLibrarySettings, !event.isARepeat {
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "a": model.setCatalogSort(ascending: true); return nil
                case "z": model.setCatalogSort(ascending: false); return nil
                case "c": model.toggleSectionOfSelection(); return nil
                case "p": model.toggleCatalogFolders(); return nil
                default: break
                }
            }
            return event
        }
    }
    private func handleController(_ action: (LauncherModel) -> Void) {
        guard NSApp.isActive, window?.isKeyWindow == true, window?.isVisible == true,
              window?.isMiniaturized == false, window?.attachedSheet == nil,
              !model.choosingLibraryFolder, NSApp.modalWindow == nil else { return }
        if window.firstResponder is NSTextView { window.makeFirstResponder(nil) }
        action(model)
    }
    private var analogNavigationContext: String? {
        guard NSApp.isActive, window?.isKeyWindow == true, window?.isVisible == true,
              window?.isMiniaturized == false, window?.attachedSheet == nil,
              NSApp.modalWindow == nil, !model.booting, model.launching == nil,
              model.errorMessage == nil, model.storageNotice == nil, !model.choosingLibraryFolder else { return nil }
        if model.dialog != nil { return "dialog" }
        if model.showingExperienceSettings { return "experience" }
        if model.showingSessionMenu { return "session" }
        if model.showingLibrarySettings { return "library-settings" }
        if model.showingCatalogFolders { return "catalog-folders" }
        return model.catalogConsole.map { "catalog-\($0.rawValue)" } ?? "menu"
    }
    private func updateActivity() {
        model.isForeground = NSApp.isActive && window?.isVisible == true && window?.isMiniaturized == false
            && window?.occlusionState.contains(.visible) == true
        NSApp.presentationOptions = model.fullscreen && model.isForeground ? [.autoHideDock, .autoHideMenuBar] : []
        if !model.isForeground { model.sounds.stop() }
        model.catalog.setArtworkPrefetchSuspended(!model.isForeground && model.sessions.values.contains(where: \.isRunning))
        controllerInput?.refreshAnalogNavigation()
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        model.refreshStorage()
        model.refreshSessions()
        updateActivity()
    }
    func applicationDidResignActive(_ notification: Notification) { updateActivity() }
    func windowDidBecomeKey(_ notification: Notification) { updateActivity() }
    func windowDidResignKey(_ notification: Notification) { updateActivity() }
    func windowDidChangeOcclusionState(_ notification: Notification) { updateActivity() }
    func windowWillClose(_ notification: Notification) {
        model.cancelLaunch()
        model.isForeground = false
        NSApp.presentationOptions = []
    }
    func windowDidChangeScreen(_ notification: Notification) {
        refitToCurrentDisplay()
    }
    func applicationDidChangeScreenParameters(_ notification: Notification) {
        refitToCurrentDisplay()
    }
    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        guard let screen = window.screen ?? NSScreen.main else { return newFrame }
        return model.fullscreen ? screen.frame : screen.visibleFrame
    }
    func windowDidMiniaturize(_ notification: Notification) { updateActivity() }
    func windowDidDeminiaturize(_ notification: Notification) { updateActivity() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if window.isMiniaturized || !window.isVisible { showWindow() }
        else { NSApp.activate(ignoringOtherApps: true); updateActivity() }
        return false
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        navigationObserver = nil
        controllerInput?.stop()
    }
    @objc private func showWindow() {
        model.refreshStorage()
        if window.isMiniaturized { window.deminiaturize(nil) }
        if model.fullscreen { window.makeKeyAndOrderFront(nil) }
        else { window.makeKeyAndOrderFront(nil) }
        NSApp.activate(ignoringOtherApps: true)
        updateActivity()
    }
    private func configureWindowButton() {
        window.standardWindowButton(.zoomButton)?.target = self
        window.standardWindowButton(.zoomButton)?.action = #selector(toggleFullscreen)
    }
    @objc private func toggleFullscreen() {
        guard !model.hasOverlay, model.launching == nil else { return }
        if model.fullscreen {
            model.fullscreen = false
            NSApp.presentationOptions = []
            window.styleMask = normalStyle
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            if let frame = normalWindowFrame { window.setFrame(frame, display: true) }
            configureWindowButton()
        } else {
            guard let screen = window.screen ?? NSScreen.main else { return }
            normalWindowFrame = window.frame
            model.fullscreen = true
            window.styleMask = [.borderless]
            window.setFrame(screen.frame, display: true)
        }
        window.contentView?.layoutSubtreeIfNeeded()
        window.makeKeyAndOrderFront(nil)
        updateActivity()
    }
    /// Opens inside the current display. A 14-inch MacBook and a larger
    /// external screen each keep the 1100×700 design only when it fits.
    private func fitInitialWindowToScreen() {
        guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        var frame = window.frame
        guard frame.width > visible.width || frame.height > visible.height else { return }
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height)
        window.setFrame(frame, display: false)
    }
    /// Fullscreen covers the display the window is on. A zoomed window fills
    /// that display's usable area, below the menu bar and beside the Dock.
    private func refitToCurrentDisplay() {
        guard window != nil, let screen = window.screen ?? NSScreen.main else { return }
        let target = model.fullscreen ? screen.frame : (window.isZoomed ? screen.visibleFrame : nil)
        guard let target, framesDiffer(window.frame, target) else { return }
        window.setFrame(target, display: true)
        window.contentView?.layoutSubtreeIfNeeded()
    }
    private func framesDiffer(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) > 0.5 || abs(lhs.origin.y - rhs.origin.y) > 0.5
            || abs(lhs.size.width - rhs.size.width) > 0.5 || abs(lhs.size.height - rhs.size.height) > 0.5
    }
    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "PS1/2"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "5.0.1"
        alert.informativeText = "Versão \(version) · PlayStation Retro Emulator\n\n× entra na biblioteca e inicia o jogo. ○ volta, □ alterna tela cheia e △ abre ou atualiza o catálogo. S abre as opções da sessão.\n\nFavoritos, recentes, busca e densidade ficam na biblioteca. Em Experiência, escolha a animação de início, os sons e o movimento. Sons originais, opcionais e desligados por padrão.\n\nEscolha as pastas em PS1/2 → Pastas dos jogos (⌘,). O catálogo e as capas em cache funcionam offline; para jogar, conecte o disco. Jogos, BIOS, saves e configurações dos emuladores não são movidos.\n\nDuckStation e PCSX2 continuam sendo aplicativos independentes. A central inicia jogos em tela cheia e acompanha as sessões que abriu; não salva nem restaura progresso.\n\nLogo: fornecido pelo usuário. Fotos: Evan-Amos / Wikimedia, domínio público. GIFs: Tenor. Créditos completos no pacote. Sem vínculo oficial com Sony."
        alert.icon = Theme.images["Logo"]
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    private func createMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "PS1/2")
        appMenu.addItem(withTitle: "Sobre PS1/2", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(withTitle: "Pastas dos jogos…", action: #selector(showGameFolders), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Ocultar PS1/2", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Sair do PS1/2", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let item = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "PS1/2", action: #selector(showWindow), keyEquivalent: "0")
        windowMenu.addItem(withTitle: "Full screen", action: #selector(toggleFullscreen), keyEquivalent: "f").keyEquivalentModifierMask = [.command, .control]
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        item.submenu = windowMenu
        menu.addItem(item)
        NSApp.mainMenu = menu
        NSApp.windowsMenu = windowMenu
    }
    @objc private func showGameFolders() { model.showLibrarySettings() }

    private func chooseGameFolder(_ console: Console) {
        guard model.showingLibrarySettings, !model.choosingLibraryFolder, model.launching == nil,
              window.attachedSheet == nil else { return }
        model.settingsConsole = console
        model.librarySettingsError = nil
        model.choosingLibraryFolder = true
        controllerInput?.suspendAnalogNavigation()
        let panel = NSOpenPanel()
        panel.title = "\(console.badge) game folder"
        panel.message = "Choose the folder with the \(console.badge) games, on the Mac or on an external disk. Nothing will be moved."
        panel.prompt = "Use this folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        if model.isStorageAvailable(for: console) { panel.directoryURL = model.gameFolder(for: console) }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.model.choosingLibraryFolder = false
            if response == .OK, let folder = panel.url { self.model.setGameFolder(folder, for: console) }
            self.controllerInput?.refreshAnalogNavigation()
        }
    }
}
