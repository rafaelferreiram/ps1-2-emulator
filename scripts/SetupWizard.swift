import AppKit
import SwiftUI

enum SetupDistribution {
    case source, prebuilt

    var preparationNote: String {
        switch self {
        case .source: return "A central será compilada neste Mac; são necessárias as ferramentas de linha de comando da Apple."
        case .prebuilt: return "A central já está pronta: não é necessário instalar um compilador, o Xcode ou as ferramentas de linha de comando."
        }
    }
}

struct SetupLaunchConfiguration {
    let source: URL
    let preview: Bool
    let distribution: SetupDistribution
}

struct SetupLaunchError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum SetupStartup {
    // Finder may supply a legacy process serial number. It is never a source
    // argument, and cannot be combined with an external installer path.
    static func resolve(arguments: [String], resources: URL?, fileManager: FileManager = .default) throws -> SetupLaunchConfiguration {
        var options = arguments
        if let first = options.first, first.hasPrefix("-psn_") {
            guard first.range(of: #"^-psn_[0-9]+_[0-9]+$"#, options: .regularExpression) != nil else {
                throw usageError
            }
            options.removeFirst()
            guard options.isEmpty || options == ["--preview"] else { throw usageError }
        }
        let preview = options.last == "--preview"
        if preview { options.removeLast() }
        let configuration: SetupLaunchConfiguration
        if options.isEmpty {
            guard let resources, resources.isFileURL, resources.path.hasPrefix("/") else {
                throw SetupLaunchError(message: "Não encontramos os recursos do instalador. Abra o aplicativo Install PS1-2 completo no disco baixado.")
            }
            let installer = resources.appendingPathComponent("Installer", isDirectory: true).standardizedFileURL
            let resourceRoot = resources.resolvingSymlinksInPath().standardizedFileURL.path
            guard installer.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(resourceRoot + "/") else {
                throw SetupLaunchError(message: "Os arquivos do instalador precisam estar dentro do aplicativo. Baixe uma nova cópia do disco de instalação.")
            }
            configuration = SetupLaunchConfiguration(source: installer,
                                                     preview: preview, distribution: .prebuilt)
        } else if options.count == 1, options[0].hasPrefix("/") {
            configuration = SetupLaunchConfiguration(source: URL(fileURLWithPath: options[0], isDirectory: true).standardizedFileURL,
                                                     preview: preview, distribution: .source)
        } else {
            throw usageError
        }
        try validate(source: configuration.source, distribution: configuration.distribution, fileManager: fileManager)
        return configuration
    }

    static func validate(source: URL, distribution: SetupDistribution, fileManager: FileManager = .default) throws {
        guard source.isFileURL, source.path.hasPrefix("/"), isDirectory(source, fileManager: fileManager) else {
            throw SetupLaunchError(message: "A pasta do instalador não está disponível. Mantenha os arquivos do download juntos e abra o instalador novamente.")
        }
        let root = source.resolvingSymlinksInPath().standardizedFileURL
        func requireFile(_ relativePath: String, executable: Bool = false) throws -> URL {
            let url = source.appendingPathComponent(relativePath)
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            let contained = resolved.path.hasPrefix(root.path + "/")
            let regular = (try? resolved.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            guard (distribution == .source || contained), regular, fileManager.isReadableFile(atPath: url.path),
                  !executable || fileManager.isExecutableFile(atPath: url.path) else {
                throw SetupLaunchError(message: "O instalador está incompleto ou danificado: \(relativePath). Baixe uma nova cópia e abra o aplicativo completo.")
            }
            return url
        }
        _ = try requireFile("install.sh")
        guard distribution == .prebuilt else { return }
        let manifestURL = try requireFile("distribution.plist")
        guard let manifest = try? PropertyListSerialization.propertyList(from: Data(contentsOf: manifestURL), format: nil) as? [String: Any],
              manifest["PS12Distribution"] as? String == "prebuilt-v1" else {
            throw SetupLaunchError(message: "Esta distribuição do instalador não é compatível. Baixe uma nova cópia do disco de instalação.")
        }
        let appPath = "payload/PS1-2.app"
        let infoURL = try requireFile(appPath + "/Contents/Info.plist")
        guard let info = try? PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL), format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == SetupApplication.central.bundleID,
              let executable = info["CFBundleExecutable"] as? String, !executable.isEmpty,
              executable != ".", executable != "..", !executable.contains("/"), !executable.contains("\0") else {
            throw SetupLaunchError(message: "A central incluída no instalador está incompleta ou tem uma identidade inesperada. Baixe uma nova cópia do disco de instalação.")
        }
        _ = try requireFile(appPath + "/Contents/MacOS/" + executable, executable: true)
        _ = try requireFile("payload/MoveApp", executable: true)
        _ = try requireFile("payload/InspectMachO", executable: true)
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var directory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }

    private static var usageError: SetupLaunchError {
        SetupLaunchError(message: "Abra Install PS1-2.app no Finder ou execute SetupWizard /caminho/absoluto/do/projeto [--preview]. A opção --preview também funciona com os recursos incluídos no aplicativo.")
    }
}

// install.sh remains the only installation authority; arguments are never interpolated into a shell command.
enum SetupCommand {
    static func arguments(source: URL, destination: URL, check: Bool) -> [String] {
        [source.appendingPathComponent("install.sh").path, check ? "--check" : "--yes", "--destination", destination.path]
    }
}

enum SetupDestination {
    static let system = URL(fileURLWithPath: "/Applications", isDirectory: true)

    static func candidates(home: URL) -> [URL] {
        [system, home.appendingPathComponent("Applications", isDirectory: true)]
    }

    // Read-only: a missing personal Applications folder is created only by the
    // user in the native folder chooser, never by startup or preflight.
    static func isWritableDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue && FileManager.default.isWritableFile(atPath: url.path)
    }

    static func preferred(candidates: [URL], canUse: (URL) -> Bool) -> URL {
        candidates.first(where: canUse) ?? system
    }

    static func chooserDirectory(destination: URL, home: URL, canUse: (URL) -> Bool) -> URL {
        canUse(destination) ? destination : home
    }
}

enum SetupStep: String, CaseIterable {
    case preflight, build, downloadPS1 = "download-ps1", downloadPS2 = "download-ps2", install, complete
    var title: String {
        switch self {
        case .preflight: return "Conferir o Mac"
        case .build: return "Preparar a central"
        case .downloadPS1: return "DuckStation · PS1"
        case .downloadPS2: return "PCSX2 · PS2"
        case .install: return "Instalar os aplicativos"
        case .complete: return "Tudo pronto"
        }
    }
    static func marker(in line: String) -> (SetupStep, String)? {
        let fields = line.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard fields.count == 3, fields[0] == "PS12_STEP", let step = SetupStep(rawValue: String(fields[1])) else { return nil }
        return (step, String(fields[2]))
    }
}

struct SetupLog {
    static let limit = 64 * 1024
    private(set) var text = ""
    mutating func append(_ value: String) {
        text.append(value)
        if text.utf8.count > Self.limit {
            text = "[As linhas mais antigas foram omitidas.]\n" + String(decoding: Array(text.utf8.suffix(Self.limit - 96)), as: UTF8.self)
        }
    }
}

struct SetupLineDecoder {
    private var pending = Data()
    mutating func consume(_ data: Data, finished: Bool = false) -> [String] {
        pending.append(data)
        var lines: [String] = []
        while let index = pending.firstIndex(where: { $0 == 10 || $0 == 13 }) {
            if index > pending.startIndex { lines.append(String(decoding: pending[..<index], as: UTF8.self)) }
            pending.removeSubrange(...index)
        }
        if pending.count > 16 * 1024 || (finished && !pending.isEmpty) {
            lines.append(String(decoding: pending, as: UTF8.self))
            pending.removeAll(keepingCapacity: true)
        }
        return lines
    }
}

enum SetupApplication: CaseIterable {
    case duckstation, pcsx2, central
    var name: String {
        switch self { case .duckstation: return "DuckStation"; case .pcsx2: return "PCSX2"; case .central: return "PS1/2" }
    }
    var filename: String {
        switch self { case .duckstation: return "DuckStation.app"; case .pcsx2: return "PCSX2.app"; case .central: return "PS1-2.app" }
    }
    var bundleID: String {
        switch self { case .duckstation: return "com.github.stenzek.duckstation"; case .pcsx2: return "net.pcsx2.pcsx2"; case .central: return "local.rafael.centraldejogos" }
    }
    var caption: String {
        switch self { case .duckstation: return "1 · Configurar PS1"; case .pcsx2: return "2 · Configurar PS2"; case .central: return "3 · Abrir a central" }
    }
}

@MainActor
final class SetupModel: ObservableObject {
    enum Phase { case checking, ready, installing, complete, failed }
    @Published private(set) var phase: Phase = .checking
    @Published private(set) var log = SetupLog()
    @Published private(set) var step: SetupStep = .preflight
    @Published private(set) var status = "Conferindo os requisitos do Mac…"
    @Published var notice: String?
    @Published var showLog = false
    @Published private(set) var destination: URL
    @Published private(set) var failureLogURL: URL?
    let source: URL
    let preview: Bool
    let distribution: SetupDistribution
    private let canUseDestination: (URL) -> Bool
    private let failureLogDirectory: URL?
    private var process: Process?
    private(set) var exitCode: Int32 = 0

    init(source: URL, preview: Bool, distribution: SetupDistribution = .source, failureLogDirectory: URL? = nil,
         destinationCandidates: [URL] = SetupDestination.candidates(home: FileManager.default.homeDirectoryForCurrentUser),
         canUseDestination: @escaping (URL) -> Bool = SetupDestination.isWritableDirectory) {
        self.source = source
        self.preview = preview
        self.distribution = distribution
        self.failureLogDirectory = failureLogDirectory
        self.canUseDestination = canUseDestination
        self.destination = SetupDestination.preferred(candidates: destinationCandidates, canUse: canUseDestination)
        if preview { phase = .ready; status = "Prévia visual · nenhuma instalação será executada." }
    }
    var isInstalling: Bool { phase == .installing }
    var isBusy: Bool { phase == .installing || phase == .checking }
    var canInstall: Bool { phase == .ready && !preview }
    var destinationGuidance: String? {
        canUseDestination(destination) ? nil : "Esta pasta não está disponível para instalação. Em Escolher pasta, selecione uma pasta com permissão de escrita ou crie Applications dentro da sua pasta pessoal."
    }

    func preflight() {
        guard !preview, !isInstalling, process == nil else { return }
        run(check: true)
    }
    func install() {
        guard canInstall, process == nil else { return }
        run(check: false)
    }
    func chooseDestination() {
        guard !isBusy, phase != .complete, !preview else { return }
        let panel = NSOpenPanel()
        panel.title = "Onde instalar os aplicativos?"
        panel.message = "Escolha uma pasta com permissão de escrita. Você também pode criar Applications dentro da sua pasta pessoal usando Nova Pasta."
        panel.prompt = "Usar esta pasta"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = SetupDestination.chooserDirectory(destination: destination,
            home: FileManager.default.homeDirectoryForCurrentUser, canUse: canUseDestination)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        destination = url.standardizedFileURL
        preflight()
    }
    func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(log.text, forType: .string)
    }
    func openApplication(_ application: SetupApplication) {
        guard phase == .complete, !preview else { return }
        let roots = [destination, URL(fileURLWithPath: "/Applications", isDirectory: true),
                     FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)]
        guard let url = roots.map({ $0.appendingPathComponent(application.filename, isDirectory: true) })
            .first(where: { Bundle(url: $0)?.bundleIdentifier == application.bundleID }) else {
            notice = "Não foi possível localizar \(application.name) com a identidade esperada. Veja os detalhes da instalação."
            showLog = true
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
            if let error {
                DispatchQueue.main.async { self?.notice = "O macOS não conseguiu abrir \(application.name): \(error.localizedDescription)" }
            }
        }
    }
    private func run(check: Bool) {
        failureLogURL = nil
        do {
            try SetupStartup.validate(source: source, distribution: distribution)
        } catch {
            phase = .failed; exitCode = 1
            status = "Não foi possível conferir os arquivos do instalador."
            notice = error.localizedDescription
            log = SetupLog()
            log.append(error.localizedDescription + "\n")
            showLog = true
            reportFailure()
            return
        }
        notice = nil
        phase = check ? .checking : .installing
        step = .preflight
        status = check ? "Conferindo os requisitos do Mac…" : "Iniciando a instalação…"
        showLog = !check
        log = SetupLog()
        failureLogURL = nil
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/bash")
        child.arguments = SetupCommand.arguments(source: source, destination: destination, check: check)
        child.currentDirectoryURL = source
        child.standardInput = FileHandle.nullDevice
        let output = Pipe()
        child.standardOutput = output
        child.standardError = output
        process = child
        do {
            try child.run()
            // Only the child keeps writers open; EOF follows the entire output.
            try? output.fileHandleForWriting.close()
        } catch {
            try? output.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
            process = nil; phase = .failed; exitCode = 1
            status = "Não foi possível iniciar o instalador."
            log.append(error.localizedDescription + "\n")
            showLog = true
            reportFailure()
            return
        }
        // Drain stdout/stderr continuously. Pipe reads and waitUntilExit never block the UI.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var decoder = SetupLineDecoder()
            do {
                while let data = try output.fileHandleForReading.read(upToCount: 8192), !data.isEmpty {
                    let lines = decoder.consume(data)
                    if !lines.isEmpty { DispatchQueue.main.async { self?.receive(lines) } }
                }
            } catch {
                let message = "Leitura do log: \(error.localizedDescription)"
                DispatchQueue.main.async { self?.receive([message]) }
            }
            let finalLines = decoder.consume(Data(), finished: true)
            try? output.fileHandleForReading.close()
            child.waitUntilExit()
            let code = child.terminationStatus
            DispatchQueue.main.async {
                self?.receive(finalLines)
                self?.finished(check: check, code: code)
            }
        }
    }
    private func receive(_ lines: [String]) {
        guard !lines.isEmpty else { return }
        log.append(lines.joined(separator: "\n") + "\n")
        for line in lines {
            if let (next, message) = SetupStep.marker(in: line) {
                step = next
                if !message.isEmpty { status = message }
            }
        }
    }
    private func finished(check: Bool, code: Int32) {
        process = nil
        exitCode = code
        if code == 0 {
            phase = check ? .ready : .complete
            step = check ? .preflight : .complete
            status = check ? "Mac conferido. Você pode iniciar a instalação." : "Instalação concluída. Configure os emuladores para começar."
            showLog = false
        } else {
            phase = .failed
            status = check ? "Precisamos resolver um requisito antes de instalar." : "A instalação não foi concluída."
            notice = "Código \(code). Consulte o motivo nos detalhes abaixo. Corrija o que foi indicado e confira novamente; nada será reinstalado sem sua confirmação."
            showLog = true
            reportFailure()
        }
    }
    private func reportFailure() {
        // The source bootstrap captures stderr. Finder launches additionally
        // preserve bounded diagnostics outside the read-only installer bundle.
        let details = "\nPS1/2 · diagnóstico (código \(exitCode))\n\(status)\n\(notice ?? "")\n\(log.text)\n"
        try? FileHandle.standardError.write(contentsOf: Data(details.utf8))
        guard let failureLogDirectory else { return }
        do {
            try FileManager.default.createDirectory(at: failureLogDirectory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let url = failureLogDirectory.appendingPathComponent("installation-\(UUID().uuidString).log")
            if FileManager.default.createFile(atPath: url.path, contents: Data(details.utf8), attributes: [.posixPermissions: 0o600]) {
                failureLogURL = url
            }
        } catch {
            // Copy details remains available if the user's Logs folder is unavailable.
        }
    }
}

private struct SetupBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.025, green: 0.045, blue: 0.13), Color(red: 0.005, green: 0.01, blue: 0.035)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Canvas { context, size in
                for index in 0..<12 {
                    let height = CGFloat(90 + (index * 67) % 270)
                    let rectangle = CGRect(x: CGFloat(index) * size.width / 11, y: size.height - height, width: 19, height: height)
                    context.fill(Path(rectangle), with: .color(.blue.opacity(0.035 + Double(index % 3) * 0.012)))
                }
                let center = CGPoint(x: size.width * 0.88, y: size.height * 0.12)
                for radius in [90.0, 130.0, 175.0] {
                    context.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .color(.cyan.opacity(0.065)), lineWidth: 1)
                }
            }
        }.ignoresSafeArea().allowsHitTesting(false)
    }
}

private struct SetupButtonStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 17).padding(.vertical, 10)
            .foregroundStyle(primary ? Color.white : Color(red: 0.78, green: 0.88, blue: 1))
            .background((primary ? Color(red: 0.08, green: 0.35, blue: 0.76) : Color.white.opacity(0.05)).opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(primary ? 0.22 : 0.13), lineWidth: 1))
    }
}

struct SetupView: View {
    @ObservedObject var model: SetupModel
    private let muted = Color(red: 0.60, green: 0.69, blue: 0.83)
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SetupBackdrop()
                VStack(alignment: .leading, spacing: 0) {
                    header
                    Divider().overlay(.white.opacity(0.10)).padding(.vertical, 19)
                    HStack(alignment: .top, spacing: 28) {
                        if geometry.size.width >= 820 { steps.frame(width: 180) }
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                if model.phase == .complete { complete } else { welcome }
                                status
                                if model.phase != .complete { destination }
                                if let notice = model.notice {
                                    Label(notice, systemImage: "info.circle").font(.system(size: 12))
                                        .foregroundStyle(Color(red: 0.97, green: 0.80, blue: 0.49)).fixedSize(horizontal: false, vertical: true)
                                }
                                if !model.log.text.isEmpty { logs }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 3)
                        }
                    }
                    Spacer(minLength: 16)
                    footer
                }.padding(26)
            }
        }.preferredColorScheme(.dark).frame(minWidth: 720, minHeight: 620)
    }
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("PS1/2").font(.system(size: 31, weight: .light, design: .rounded)).tracking(3)
                Text("PLAYSTATION RETRO EMULATOR").font(.system(size: 10, weight: .medium)).tracking(2.3).foregroundStyle(muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text("INSTALAÇÃO").font(.system(size: 11, weight: .medium)).tracking(2)
                Text("macOS · Apple Silicon").font(.system(size: 11)).foregroundStyle(muted)
            }
        }
    }
    private var steps: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(Array(SetupStep.allCases.enumerated()), id: \.element) { index, item in
                let current = SetupStep.allCases.firstIndex(of: model.step) ?? 0
                HStack(spacing: 11) {
                    ZStack {
                        Circle().stroke(index == current ? Color.cyan.opacity(0.8) : .white.opacity(0.18), lineWidth: 1)
                        Text(index < current || model.phase == .complete ? "✓" : String(index + 1)).font(.system(size: 11, weight: .medium, design: .monospaced))
                    }.frame(width: 26, height: 26)
                    Text(item.title).font(.system(size: 12, weight: index == current ? .semibold : .regular)).foregroundStyle(index == current ? .white : muted)
                }
            }
            Text("Sem reiniciar o Mac.\nSem jogos ou BIOS incluídos.").font(.system(size: 11)).foregroundStyle(muted).lineSpacing(4).padding(.top, 8)
        }.padding(.top, 4)
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(model.isInstalling ? "Preparando seu espaço de jogos." : "Bem-vindo de volta ao clássico.")
                .font(.system(size: 22, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            Text("A central organiza sua biblioteca e abre os jogos nos emuladores dedicados. Este assistente instala o PS1/2 e baixa DuckStation (PS1) e PCSX2 (PS2), de fontes oficiais, somente se estiverem ausentes.")
                .font(.system(size: 13)).foregroundStyle(muted).lineSpacing(4)
            VStack(alignment: .leading, spacing: 8) {
                note(model.distribution.preparationNote)
                note("Emuladores existentes são mantidos; a central anterior recebe uma cópia de segurança.")
                note("Jogos, BIOS, saves e configurações pessoais não são alterados.")
                note("Você fornece os jogos e a BIOS e conclui a configuração inicial de cada emulador.")
            }
        }
    }
    private func note(_ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(.cyan.opacity(0.75)).padding(.top, 3)
            Text(value).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.83)).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var status: some View {
        HStack(spacing: 12) {
            if model.isBusy { ProgressView().controlSize(.small).tint(.cyan) }
            else { Image(systemName: model.phase == .failed ? "exclamationmark.circle" : "checkmark.circle").foregroundStyle(model.phase == .failed ? .orange : .cyan) }
            VStack(alignment: .leading, spacing: 5) {
                Text(model.status).font(.system(size: 13, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                if model.isInstalling {
                    Text("Mantenha esta janela aberta. Downloads dependem da sua conexão.").font(.system(size: 11)).foregroundStyle(muted)
                } else if model.phase == .ready && !model.preview {
                    Text("A conferência não baixa nem altera arquivos. Internet e jogos ainda não foram testados.").font(.system(size: 11)).foregroundStyle(muted)
                }
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.cyan.opacity(0.14), lineWidth: 1))
    }
    private var destination: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("DESTINO DOS APLICATIVOS").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(muted)
                Text(model.destination.path).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle).help(model.destination.path)
                if let guidance = model.destinationGuidance {
                    Text(guidance).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Button("Escolher pasta…") { model.chooseDestination() }.buttonStyle(SetupButtonStyle()).disabled(model.isBusy || model.preview).opacity(model.isBusy || model.preview ? 0.5 : 1)
        }
    }
    private var logs: some View {
        DisclosureGroup(isExpanded: $model.showLog) {
            VStack(alignment: .trailing, spacing: 8) {
                ScrollView {
                    Text(model.log.text).font(.system(size: 10.5, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }.frame(height: 170).background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 7))
                Button("Copiar detalhes") { model.copyLog() }.buttonStyle(SetupButtonStyle())
                if let url = model.failureLogURL {
                    Text("Diagnóstico salvo em \(url.path)").font(.system(size: 10)).foregroundStyle(muted)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.top, 9)
        } label: { Text("Detalhes técnicos").font(.system(size: 12)).foregroundStyle(muted) }.tint(muted)
    }
    private var complete: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Sua central está instalada.").font(.system(size: 22, weight: .medium))
            Text("Agora faça a configuração inicial. Nenhum aplicativo será aberto sem você escolher.").font(.system(size: 13)).foregroundStyle(muted).lineSpacing(4)
            note("No DuckStation e no PCSX2, adicione sua BIOS, configure o controle e as pastas de jogos. Teste um jogo em cada um.")
            note("Se o PCSX2 precisar de Rosetta, o macOS poderá pedir a instalação ao abri-lo. Aceite a licença somente no aviso da Apple, se desejar.")
            note("Depois abra o PS1/2 e escolha as bibliotecas de PS1 e PS2 em Pastas de jogos. Elas podem estar no Mac ou em um disco externo.")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 9) { appButtons }
                VStack(alignment: .leading, spacing: 9) { appButtons }
            }.padding(.top, 3)
        }
    }
    private var appButtons: some View {
        ForEach(SetupApplication.allCases, id: \.self) { application in
            Button { model.openApplication(application) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Abrir \(application.name)")
                    Text(application.caption).font(.system(size: 10)).foregroundStyle(muted)
                }
            }.buttonStyle(SetupButtonStyle(primary: application == .central))
        }
    }
    private var footer: some View {
        VStack(spacing: 15) {
            Divider().overlay(.white.opacity(0.10))
            HStack {
                HStack(spacing: 12) {
                    Text("□").foregroundStyle(.pink.opacity(0.8))
                    Text("△").foregroundStyle(.mint.opacity(0.8))
                    Text("○").foregroundStyle(.red.opacity(0.8))
                    Text("×").foregroundStyle(.blue.opacity(0.9))
                }.font(.system(size: 20, weight: .light)).accessibilityHidden(true)
                Spacer()
                if !model.isBusy && model.phase != .complete {
                    Button("Fechar") { NSApp.terminate(nil) }.buttonStyle(SetupButtonStyle())
                        .keyboardShortcut(.cancelAction)
                }
                if model.phase == .ready {
                    Button("Instalar") { model.install() }.buttonStyle(SetupButtonStyle(primary: true)).disabled(!model.canInstall)
                        .keyboardShortcut(.defaultAction)
                } else if model.phase == .failed {
                    Button("Conferir novamente") { model.preflight() }.buttonStyle(SetupButtonStyle(primary: true))
                        .keyboardShortcut(.defaultAction)
                } else if model.phase == .complete {
                    Button("Concluir") { NSApp.terminate(nil) }.buttonStyle(SetupButtonStyle())
                        .keyboardShortcut(.defaultAction)
                } else {
                    Text(model.isInstalling ? "Instalação em andamento" : "Conferindo…").font(.system(size: 12)).foregroundStyle(muted)
                }
            }
        }
    }
}

@MainActor
final class SetupDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model: SetupModel
    private var window: NSWindow?
    init(model: SetupModel) { self.model = model }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let iconURL = Bundle.main.resourceURL?.appendingPathComponent("icon.png")
        NSApp.applicationIconImage = iconURL.flatMap { NSImage(contentsOf: $0) } ?? NSImage(contentsOf: model.source.appendingPathComponent("docs/images/icon.png"))
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: min(960, visible.width - 60), height: min(780, visible.height - 50))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "PS1/2 · Instalação"
        window.minSize = NSSize(width: 720, height: 620)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: SetupView(model: model))
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Sair do instalador", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = menu
        NSApp.activate(ignoringOtherApps: true)
        model.preflight()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.isInstalling else { return true }
        explainActiveInstallation(); return false
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.isInstalling else { return .terminateNow }
        explainActiveInstallation(); return .terminateCancel
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        // Return backend failure status to command-line/bootstrap callers.
        exit(model.exitCode)
    }
    private func explainActiveInstallation() {
        model.notice = "A instalação ainda está em andamento. Aguarde sua conclusão antes de fechar; interrompê-la durante a troca dos aplicativos pode deixar a instalação incompleta."
        window?.makeKeyAndOrderFront(nil)
        NSSound.beep()
    }
}

#if !SETUP_WIZARD_TESTS
@main
struct SetupWizardMain {
    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        let configuration: SetupLaunchConfiguration
        do {
            configuration = try SetupStartup.resolve(arguments: Array(CommandLine.arguments.dropFirst()), resources: Bundle.main.resourceURL)
        } catch {
            fputs(error.localizedDescription + "\n", stderr)
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Não foi possível abrir o instalador."
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "Fechar")
            application.activate(ignoringOtherApps: true)
            alert.runModal()
            exit(2)
        }
        let logDirectory = configuration.distribution == .prebuilt
            ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/PS1-2 Installer", isDirectory: true) : nil
        let model = SetupModel(source: configuration.source, preview: configuration.preview,
                               distribution: configuration.distribution, failureLogDirectory: logDirectory)
        let delegate = SetupDelegate(model: model)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
        exit(model.exitCode)
    }
}
#endif
