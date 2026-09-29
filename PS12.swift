import AppKit
import SwiftUI

enum Console: String, CaseIterable, Identifiable {
    case ps1, ps2
    var id: String { rawValue }
    var name: String { self == .ps1 ? "PlayStation 1" : "PlayStation 2" }
    var badge: String { self == .ps1 ? "PS1" : "PS2" }
    var emulator: String { self == .ps1 ? "DuckStation" : "PCSX2" }
    var controller: String { self == .ps1 ? "Controle original" : "DualShock 2" }
    var asset: String { self == .ps1 ? "PS1Controller" : "PS2Controller" }
    var bundleID: String { self == .ps1 ? "com.github.stenzek.duckstation" : "net.pcsx2.pcsx2" }
    var folder: URL { URL(fileURLWithPath: "/Volumes/Extreme SSD/Emulacao/\(badge)/Jogos", isDirectory: true) }
    var applicationURL: URL? {
        let standard = URL(fileURLWithPath: "/Applications/\(emulator).app", isDirectory: true)
        if FileManager.default.fileExists(atPath: standard.path) { return standard }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
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
    @Published var storageMounted = false
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
    @Published var gameSelection: [String: String] = [:]
    @Published var launchGameTitle: String?
    @Published var openingText = ""
    @Published var waitingForRestart = false
    let catalog: GameCatalog
    let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    var toggleFullscreen: (() -> Void)?
    private var timer: Timer?
    private let storageProbe: () -> Bool
    private let monitor = EmulatorMonitor()
    private var launchURL: URL?
    private var launchGameURL: URL?
    private var restartDuckStation: (pid: Int32, launchedAt: Date?)?
    private var stopDeadlines: [Console: Date] = [:]
    let startedAt = Date()

    init(catalog: GameCatalog? = nil, storageProbe: @escaping () -> Bool = {
        FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [])?
            .contains { $0.standardizedFileURL.path == "/Volumes/Extreme SSD" } ?? false
    }, startServices: Bool = true) {
        self.catalog = catalog ?? GameCatalog()
        self.storageProbe = storageProbe
        refreshStorage()
        guard startServices else { return }
        self.catalog.restoreSavedCatalogs()
        refreshSessions()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStorage()
                self?.refreshSessions()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 1.7)) { [weak self] in self?.finishBoot() }
    }
    func refreshSessions() {
        monitor.refresh()
        sessions = monitor.states
        now = Date()
        for console in Array(stopping) {
            if !state(console).isRunning {
                stopping.remove(console)
                stopDeadlines.removeValue(forKey: console)
                notice = "\(console.badge) desligado."
            } else if let deadline = stopDeadlines[console], now >= deadline {
                stopping.remove(console)
                stopDeadlines.removeValue(forKey: console)
                notice = "\(console.emulator) continua aberto. Confirme ou cancele a saída no emulador."
            }
        }
    }
    func state(_ console: Console) -> EmulatorState { sessions[console.rawValue] ?? .off }
    func uptime(_ console: Console) -> String {
        guard let date = state(console).launchedAt else { return "--:--:--" }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
    func refreshStorage() {
        // Read only the mounted-volume list, not game folders or descriptors.
        // An unplugged SSD does not erase the last complete catalog snapshot.
        let mounted = storageProbe()
        if storageMounted != mounted { storageMounted = mounted }
    }
    func finishBoot() {
        guard booting else { return }
        withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.65)) { booting = false }
    }
    func select(_ console: Console) {
        guard launching == nil, !booting, errorMessage == nil, storageNotice == nil else { return }
        withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.2)) { selected = console }
    }
    var previewConsole: Console? {
        guard !booting, isForeground, launching == nil, catalogConsole == nil, errorMessage == nil, storageNotice == nil else { return nil }
        return selected
    }
    func setConsoleHover(_ console: Console, inside: Bool) {
        guard inside, !booting, isForeground, launching == nil,
              catalogConsole == nil, errorMessage == nil, storageNotice == nil else { return }
        select(console)
    }
    func move(_ direction: Int) {
        guard errorMessage == nil, storageNotice == nil, NSApp.modalWindow == nil else { return }
        guard !booting, launching == nil else { finishBoot(); return }
        if catalogConsole != nil { moveGame(direction); return }
        select(selected == .ps1 ? .ps2 : .ps1)
    }
    func moveVertical(_ direction: Int) {
        if catalogConsole != nil { moveGame(direction * Theme.catalogColumns) } else { move(direction) }
    }
    var listedGames: [CatalogGame] { catalog.games[catalogConsole?.rawValue ?? ""] ?? [] }
    var selectedGame: CatalogGame? {
        guard let console = catalogConsole else { return nil }
        return listedGames.first { $0.id == gameSelection[console.rawValue] } ?? listedGames.first
    }
    func selectGame(_ game: CatalogGame) {
        guard launching == nil, storageNotice == nil, game.consoleKey == catalogConsole?.rawValue else { return }
        gameSelection[game.consoleKey] = game.id
    }
    private func moveGame(_ delta: Int) {
        guard launching == nil, errorMessage == nil, storageNotice == nil, NSApp.modalWindow == nil,
              let current = selectedGame, let index = listedGames.firstIndex(where: { $0.id == current.id }) else { return }
        let next = min(max(0, index + delta), listedGames.count - 1)
        selectGame(listedGames[next])
    }
    func showCatalog() {
        guard launching == nil, errorMessage == nil, storageNotice == nil, NSApp.modalWindow == nil else { return }
        finishBoot()
        let forceRefresh = catalogConsole != nil
        let console = catalogConsole ?? selected
        catalogConsole = console
        catalog.refresh(console.rawValue, force: forceRefresh)
    }
    func confirm() {
        guard errorMessage == nil, NSApp.modalWindow == nil else { return }
        if storageNotice != nil { dismissStorageNotice(); return }
        if booting { finishBoot() }
        else if let console = catalogConsole {
            if !catalog.loading.contains(console.rawValue), let game = selectedGame { launchGame(game) }
        }
        else { launch(selected) }
    }
    func back() {
        guard errorMessage == nil, NSApp.modalWindow == nil else { return }
        if storageNotice != nil { dismissStorageNotice(); return }
        if booting { finishBoot() }
        else if launching != nil { cancelLaunch() }
        else if catalogConsole != nil { catalogConsole = nil }
        else if fullscreen { toggleFullscreen?() }
    }
    func launch(_ console: Console) {
        guard launching == nil, !booting, errorMessage == nil, storageNotice == nil, !stopping.contains(console) else { return }
        select(console)
        guard let url = console.applicationURL else {
            errorMessage = "Não encontrei o \(console.emulator). Coloque o aplicativo na pasta Aplicativos e tente novamente."
            return
        }
        launching = console
        launchID = UUID()
        launchURL = url
        launchGameURL = nil
        launchGameTitle = nil
        restartDuckStation = nil
        isOpening = false
        notice = "Inicializando \(console.badge)…"
    }
    func cancelLaunch() {
        guard launching != nil, !isOpening || waitingForRestart else { return }
        let exitRequested = waitingForRestart
        clearLaunchState()
        notice = exitRequested ? "Abertura cancelada; a saída do DuckStation já foi solicitada." : "Abertura cancelada."
    }
    private func clearLaunchState() {
        launching = nil
        launchID = nil
        launchURL = nil
        launchGameURL = nil
        launchGameTitle = nil
        restartDuckStation = nil
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
        guard storageMounted else {
            storageNotice = StorageNotice(gameTitle: title, consoleName: console.badge)
            return false
        }
        guard GameLaunchCheck.isAvailable(file, library: console.folder) else {
            errorMessage = "Não foi possível acessar \(title). Verifique os arquivos e as permissões do jogo no Extreme SSD. Use △ ou T para atualizar o catálogo se o jogo foi movido ou removido."
            return false
        }
        return true
    }
    func launchGame(_ game: CatalogGame) {
        guard let console = Console(rawValue: game.consoleKey), launching == nil, !booting,
              errorMessage == nil, storageNotice == nil, !stopping.contains(console), NSApp.modalWindow == nil else { return }
        guard checkGameAccess(game.fileURL, title: game.title, console: console) else { return }
        refreshSessions()
        let current = state(console)
        if current.isRunning && sameLoadedGame(game, path: current.gamePath) {
            launch(console)
            return
        }
        guard canOpenGame(console) else { return }
        var restart: (pid: Int32, launchedAt: Date?)?
        if console == .ps1, current.isRunning, let pid = current.pid {
            let alert = NSAlert()
            alert.messageText = "Abrir \(game.title)?"
            alert.informativeText = "Para iniciar este jogo diretamente, a central precisa encerrar e reabrir o DuckStation. Salve qualquer sessão antes de continuar. O encerramento será normal, respeitando as confirmações do emulador."
            alert.addButton(withTitle: "Cancelar")
            alert.addButton(withTitle: "Abrir jogo")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
            restart = (pid, current.launchedAt)
        }
        launch(console)
        guard launching == console else { return }
        launchGameURL = game.fileURL
        launchGameTitle = game.title
        restartDuckStation = restart
    }
    private func sameLoadedGame(_ game: CatalogGame, path: String?) -> Bool {
        guard let path else { return false }
        let loaded = URL(fileURLWithPath: path).standardizedFileURL
        let requested = game.fileURL.standardizedFileURL
        if loaded.path == requested.path { return true }
        guard ["cue", "ccd"].contains(requested.pathExtension.lowercased()),
              loaded.deletingLastPathComponent().path == requested.deletingLastPathComponent().path else { return false }
        let stem = loaded.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: #"(?i)\s*(?:\(|\[)track[\s_-]*\d+(?:\)|\])\s*$"#, with: "", options: .regularExpression)
        return stem.caseInsensitiveCompare(requested.deletingPathExtension().lastPathComponent) == .orderedSame
    }
    private func canOpenGame(_ console: Console) -> Bool {
        let current = state(console)
        if current.isRunning && (current.gamePath != nil || current.activityDescription != "Emulador aberto · sem jogo detectado") {
            errorMessage = "O \(console.emulator) já tem uma sessão aberta ou ainda não foi possível confirmar seu estado. Feche o jogo atual no próprio emulador e tente novamente. A central não vai trocar o disco nem interromper sua partida."
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
        if console == .ps1, launchGameURL != nil, state(console).isRunning {
            guard let accepted = restartDuckStation, accepted.pid == state(console).pid,
                  accepted.launchedAt == state(console).launchedAt, let pid = state(console).pid,
                  let app = NSRunningApplication(processIdentifier: pid), app.bundleIdentifier == console.bundleID else {
                finishLaunch(id, console: console, app: nil, error: nil)
                errorMessage = "A sessão do DuckStation mudou durante a animação. Nenhuma sessão nova foi encerrada. Tente novamente."
                return
            }
            openingText = "Reabrindo DuckStation para iniciar o jogo…"
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
                self.errorMessage = "O DuckStation continuou aberto. Confirme ou cancele a saída no emulador e tente novamente. Nenhum encerramento foi forçado."
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
            guard canOpenGame(console), console != .ps1 || !state(console).isRunning else {
                let explanation = errorMessage
                finishLaunch(id, console: console, app: nil, error: nil)
                errorMessage = explanation ?? "O DuckStation voltou a abrir antes do envio do jogo. Encerre a sessão e tente novamente."
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
            if console == .ps2 {
                NSWorkspace.shared.open([game], withApplicationAt: url, configuration: configuration, completionHandler: completion)
            } else {
                configuration.arguments = ["--", game.path]
                NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: completion)
            }
        } else {
            NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: completion)
        }
    }
    private func finishLaunch(_ id: UUID, console: Console, app: NSRunningApplication?, error: Error?) {
        guard launchID == id else { return }
        let title = launchGameTitle
        clearLaunchState()
        refreshSessions()
        if let error {
            notice = ""
            errorMessage = "Não foi possível abrir o \(console.emulator). \(error.localizedDescription)"
        } else if app != nil {
            notice = title.map { "Abertura de \($0) enviada ao \(console.emulator)." } ?? "\(console.emulator) aberto. Boa partida."
        } else {
            notice = ""
            errorMessage = "Não foi possível concluir a abertura do \(console.emulator). Verifique sua janela e tente novamente."
        }
    }
    func requestStop(_ console: Console) {
        guard launching == nil, storageNotice == nil, !stopping.contains(console), NSApp.modalWindow == nil else { return }
        refreshSessions()
        guard let pid = state(console).pid else { return }
        let alert = NSAlert()
        alert.messageText = "Desligar \(console.badge)?"
        alert.informativeText = "O \(console.emulator) será encerrado normalmente. Salve sua partida antes de continuar. Se o emulador pedir confirmação, ela será exibida em sua janela. A central continuará aberta."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancelar")
        alert.addButton(withTitle: "Desligar")
        guard alert.runModal() == .alertSecondButtonReturn,
              let app = NSRunningApplication(processIdentifier: pid),
              app.bundleIdentifier == console.bundleID, !app.isTerminated else { return }
        stopping.insert(console)
        stopDeadlines[console] = Date().addingTimeInterval(15)
        notice = "Solicitando encerramento de \(console.emulator)…"
        app.activate(options: [])
        if !app.terminate() {
            stopping.remove(console)
            stopDeadlines.removeValue(forKey: console)
            errorMessage = "O \(console.emulator) não aceitou o pedido de saída. Salve sua partida e encerre pelo menu do próprio emulador."
        }
        refreshSessions()
    }
    var storageText: String {
        if storageMounted { return notice.isEmpty ? "Extreme SSD  ·  Conectado" : notice }
        return "SSD desconectado · Catálogo salvo disponível · Conecte para jogar"
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
          Button { model.launch(console) } label: {
            HStack(spacing: 15) {
                ZStack {
                    Circle().fill(Theme.blue.opacity(selected ? 0.3 : 0)).frame(width: 24, height: 24).blur(radius: 6)
                    Circle().fill(selected ? Theme.ice : Color.white.opacity(0.15)).frame(width: 5, height: 5)
                }.frame(width: 21)
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
          .accessibilityLabel("Abrir \(console.name) — \(console.emulator)")
          .accessibilityValue(selected ? "Selecionado" : "")
          .help("Reproduzir a abertura de \(console.badge) e abrir \(console.emulator)")
          HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(session.isRunning ? Color.green : Theme.pale.opacity(0.3)).frame(width: 5, height: 5)
                    Text(session.isRunning ? "LIGADO" : "DESLIGADO").font(.system(size: 9, weight: .semibold)).tracking(1)
                    if session.isRunning {
                        Text("·  " + model.uptime(console)).font(.system(size: 11, design: .monospaced))
                            .accessibilityLabel("Tempo ligado: \(model.uptime(console))")
                    }
                }.foregroundStyle(session.isRunning ? Theme.ice : Theme.pale.opacity(0.6))
                if session.isRunning, let title = session.gameTitle, let path = session.gamePath {
                    NowPlayingGameView(consoleKey: console.rawValue, title: title, gamePath: path,
                                       revision: catalog.revisions[console.rawValue] ?? 0)
                        .id(path)
                } else {
                    Text(session.isRunning ? session.activityDescription : "Pronto para iniciar")
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
                 .accessibilityLabel("Desligar \(console.badge) — \(console.emulator)")
            }
          }.padding(.leading, 49).padding(.trailing, 13).frame(height: 73, alignment: .top)
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

    var body: some View {
        VStack(spacing: 12) {
            HoverAnimationView(resourceName: console == .ps1 ? "PS1Startup" : "PS2Startup", reducedMotion: reducedMotion)
                .frame(width: 398, height: 298)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.ice.opacity(0.18), lineWidth: 1))
                .shadow(color: Theme.blue.opacity(0.10), radius: 16)
            HStack(spacing: 8) {
                Text(console.badge).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.ice)
                Text("Prévia · sem iniciar o emulador").font(.system(size: 10)).foregroundStyle(Theme.pale.opacity(0.65))
            }
        }
        .allowsHitTesting(false)
    }
}

struct SystemMenu: View {
    @ObservedObject var model: LauncherModel
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                if let logo = Theme.images["Logo"] {
                    Image(nsImage: logo).resizable().scaledToFit().frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10)).accessibilityLabel("Logo PlayStation")
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("PS1/2").font(.system(size: 27, weight: .light, design: .rounded)).tracking(3)
                        .foregroundStyle(Theme.ice).shadow(color: Theme.blue.opacity(0.7), radius: 12)
                    Text("Playstation Retro Emulator").font(.system(size: 9, weight: .medium)).tracking(1.5)
                        .foregroundStyle(Theme.pale.opacity(0.6))
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 30)) { time in
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(time.date, format: .dateTime.hour().minute()).font(.system(size: 16, weight: .regular, design: .monospaced))
                    }
                }.foregroundStyle(Theme.pale.opacity(0.68))
            }.padding(.top, 42)
            HStack(spacing: 0) {
                ZStack {
                    if let console = model.previewConsole {
                        ConsolePreview(console: console, reducedMotion: model.reduceMotion)
                            .id(console)
                    }
                }.frame(width: 440, height: 342)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Emulador").font(.system(size: 32, weight: .light, design: .rounded))
                        .foregroundStyle(Theme.pale).shadow(color: Theme.blue.opacity(0.25), radius: 9).padding(.bottom, 9)
                    Text("Selecione um console · acompanhe sua sessão").font(.system(size: 12)).tracking(0.6)
                        .foregroundStyle(Theme.pale.opacity(0.62)).padding(.bottom, 18)
                    ConsoleOption(console: .ps1, model: model)
                    ConsoleOption(console: .ps2, model: model)
                }.frame(width: 470).padding(.leading, 27)
                Spacer(minLength: 0)
            }.frame(maxHeight: .infinity)
            VStack(spacing: 21) {
                Rectangle().fill(LinearGradient(colors: [.clear, Theme.ice.opacity(0.19), .clear], startPoint: .leading, endPoint: .trailing)).frame(height: 1)
                HStack(spacing: 24) {
                    Button { model.confirm() } label: { hint("×", "Confirmar", "Enter", Theme.ice) }
                    Button { model.back() } label: { hint("○", "Voltar", "Esc", Color(red: 0.92, green: 0.49, blue: 0.51)) }
                    Button { model.toggleFullscreen?() } label: { hint("□", model.fullscreen ? "Janela" : "Tela cheia", "F", Color(red: 0.83, green: 0.58, blue: 0.80)) }
                    Button { model.showCatalog() } label: { hint("△", "Listar jogos \(model.selected.badge)", "T", Color(red: 0.4, green: 0.9, blue: 0.68)) }
                        .accessibilityLabel("Listar jogos \(model.selected.badge)")
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.arrow.down").font(.system(size: 12))
                        Text("Selecionar").font(.system(size: 12))
                    }.foregroundStyle(Theme.pale.opacity(0.52))
                }.buttonStyle(.plain)
                HStack(spacing: 7) {
                    Circle().fill(model.storageMounted ? Theme.ice.opacity(0.8) : Color.orange).frame(width: 4, height: 4)
                    Text(model.storageText).font(.system(size: 10)).tracking(0.2)
                    Spacer()
                    if let name = model.controllerName {
                        Image(systemName: "gamecontroller").font(.system(size: 12))
                        Text(name).font(.system(size: 10))
                    }
                }.foregroundStyle(Theme.pale.opacity(0.62))
            }.padding(.bottom, 31)
        }.padding(.horizontal, 63).frame(width: 1100, height: 700)
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
            Text("Playstation Retro Emulator").font(.system(size: 10, weight: .light)).tracking(4)
                .foregroundStyle(Theme.ice.opacity(0.7))
            Spacer()
            Button("Enter ou clique para continuar") { model.finishBoot() }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.pale.opacity(0.5)).padding(.bottom, 49)
        }.frame(width: 1100, height: 700).contentShape(Rectangle()).onTapGesture { model.finishBoot() }
    }
}

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    var body: some View {
        GeometryReader { geometry in
            let scale = min(1, min(geometry.size.width / 1100, geometry.size.height / 700))
            ZStack {
                Theme.background
                SystemScene(active: model.isForeground && model.launching == nil && model.catalogConsole == nil && model.previewConsole == nil, reduceMotion: model.reduceMotion, booting: model.booting, startedAt: model.startedAt, showOrbs: model.previewConsole == nil)
                    .frame(width: 1100, height: 700).scaleEffect(scale)
                ZStack {
                    if model.booting { BootOverlay(model: model).transition(.opacity) }
                    else if let console = model.catalogConsole {
                        GameCatalogView(console: console, model: model, catalog: model.catalog).transition(.opacity)
                    } else { SystemMenu(model: model).transition(.opacity) }
                }.frame(width: 1100, height: 700).scaleEffect(scale)
                    .accessibilityHidden(model.launching != nil || model.storageNotice != nil)
                    .allowsHitTesting(model.launching == nil && model.storageNotice == nil)
                    .disabled(model.storageNotice != nil)
                if let console = model.launching, let id = model.launchID {
                    Color.black.ignoresSafeArea()
                    VStack(spacing: 18) {
                        HStack {
                            Text("INICIANDO \(console.badge)").tracking(3)
                            Spacer()
                            if !model.isOpening || model.waitingForRestart {
                                Button("Cancelar · Esc") { model.cancelLaunch() }.buttonStyle(.plain)
                            }
                        }.font(.system(size: 12)).foregroundStyle(Theme.pale.opacity(0.6))
                        if model.isOpening {
                            Spacer()
                            ProgressView(model.openingText).foregroundStyle(Theme.ice)
                            Spacer()
                        } else {
                            StartupAnimationView(resourceName: console == .ps1 ? "PS1Startup" : "PS2Startup", reducedMotion: model.reduceMotion) {
                                model.animationFinished(id)
                            }.id(id)
                            Text(model.launchGameTitle.map { "\($0) · \(console.emulator)" } ?? "A abertura termina antes de acessar o \(console.emulator)")
                                .font(.system(size: 11)).foregroundStyle(Theme.pale.opacity(0.4))
                        }
                    }.padding(35).frame(maxWidth: 1000, maxHeight: .infinity)
                }
                if let notice = model.storageNotice {
                    StorageNoticeView(notice: notice, onDismiss: model.dismissStorageNotice)
                        .frame(width: 1100, height: 700).scaleEffect(scale)
                        .zIndex(10)
                }
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }
        .preferredColorScheme(.dark)
        .alert("PS1/2", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}

// Borderless fullscreen keeps the console menu on the current desktop and
// avoids Spaces restoring the window when an external emulator receives focus.
final class LauncherWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
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
        // Refresh the running Dock tile explicitly instead of retaining an old
        // Launch Services icon cached under this application's stable bundle ID.
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String,
           let url = Bundle.main.url(forResource: name, withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
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
        window.contentView = NSHostingView(rootView: LauncherView(model: model))
        window.center()
        configureWindowButton()
        model.toggleFullscreen = { [weak self] in self?.toggleFullscreen() }
        controllerInput = ControllerInput(onMove: { [weak self] direction in self?.handleController { $0.move(direction) } },
                                          onVerticalMove: { [weak self] direction in self?.handleController { $0.moveVertical(direction) } },
                                          onConfirm: { [weak self] in self?.handleController { $0.confirm() } },
                                          onBack: { [weak self] in self?.handleController { $0.back() } },
                                          onFullscreen: { [weak self] in self?.handleController { $0.toggleFullscreen?() } },
                                          onCatalog: { [weak self] in self?.handleController { $0.showCatalog() } },
                                          onConnectionChanged: { [weak self] in self?.model.controllerName = $0 })
        controllerInput?.start()
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
        guard NSApp.isActive, NSApp.keyWindow === window, NSApp.modalWindow == nil, model.errorMessage == nil else { return event }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if model.storageNotice != nil {
            // Keep system shortcuts and Tab navigation, but no console/game
            // shortcuts may act through the storage dialog.
            if modifiers.contains(.command) { return event }
            if event.keyCode == 53 { model.back(); return nil }
            if [36, 76].contains(event.keyCode), !event.isARepeat { model.confirm(); return nil }
            return event.keyCode == 48 ? event : nil
        }
        if modifiers.contains(.command) {
            if event.charactersIgnoringModifiers == "1" { model.finishBoot(); model.launch(.ps1); return nil }
            if event.charactersIgnoringModifiers == "2" { model.finishBoot(); model.launch(.ps2); return nil }
            return event
        }
        if modifiers.contains(.control) || modifiers.contains(.option) { return event }
        switch event.keyCode {
        case 123: if !event.isARepeat { model.move(-1) }; return nil
        case 124: if !event.isARepeat { model.move(1) }; return nil
        case 126: if !event.isARepeat { model.moveVertical(-1) }; return nil
        case 125: if !event.isARepeat { model.moveVertical(1) }; return nil
        case 36, 76: if !event.isARepeat { model.confirm() }; return nil
        case 53: model.back(); return nil
        default:
            if event.charactersIgnoringModifiers?.lowercased() == "f", !event.isARepeat { toggleFullscreen(); return nil }
            if event.charactersIgnoringModifiers?.lowercased() == "t", !event.isARepeat { model.showCatalog(); return nil }
            return event
        }
    }
    private func handleController(_ action: (LauncherModel) -> Void) {
        guard NSApp.isActive, window?.isKeyWindow == true, window?.isVisible == true,
              window?.isMiniaturized == false, model.errorMessage == nil, NSApp.modalWindow == nil else { return }
        action(model)
    }
    private func updateActivity() {
        model.isForeground = NSApp.isActive && window?.isVisible == true && window?.isMiniaturized == false
            && window?.occlusionState.contains(.visible) == true
        NSApp.presentationOptions = model.fullscreen && model.isForeground ? [.autoHideDock, .autoHideMenuBar] : []
    }
    func applicationDidBecomeActive(_ notification: Notification) {
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
        if model.fullscreen, let screen = window.screen { window.setFrame(screen.frame, display: true) }
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
        guard model.storageNotice == nil else { return }
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
        window.makeKeyAndOrderFront(nil)
        updateActivity()
    }
    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "PS1/2"
        alert.informativeText = "Versão 4.7 · Interface inspirada no PlayStation 2\n\nO console pré-selecionado mostra sua prévia animada em loop, por mouse, teclado ou controle, sem abrir o emulador. Catálogos salvos de PS1 e PS2 são restaurados ao iniciar, mesmo sem o SSD. Ao tentar jogar sem ele, um aviso de armazenamento pede a conexão. Reconectar não inicia jogos automaticamente.\n\nUse setas para selecionar, Enter para confirmar, T / △ para listar jogos ou realizar uma nova carga completa, F / □ para tela cheia e Esc / ○ para voltar.\n\nLogo: fornecido pelo usuário.\nFotos: Evan-Amos / Wikimedia — domínio público.\nGIFs: Tenor; créditos completos no pacote do app.\n\nInicializador pessoal para DuckStation e PCSX2, sem vínculo oficial com a Sony."
        alert.icon = Theme.images["Logo"]
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    private func createMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "PS1/2")
        appMenu.addItem(withTitle: "Sobre PS1/2", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Ocultar PS1/2", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Sair de PS1/2", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let item = NSMenuItem()
        let windowMenu = NSMenu(title: "Janela")
        windowMenu.addItem(withTitle: "PS1/2", action: #selector(showWindow), keyEquivalent: "0")
        windowMenu.addItem(withTitle: "Tela cheia", action: #selector(toggleFullscreen), keyEquivalent: "f").keyEquivalentModifierMask = [.command, .control]
        windowMenu.addItem(withTitle: "Minimizar", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        item.submenu = windowMenu
        menu.addItem(item)
        NSApp.mainMenu = menu
        NSApp.windowsMenu = windowMenu
    }
}
