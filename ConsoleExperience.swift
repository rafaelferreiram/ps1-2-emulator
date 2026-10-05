import AppKit
import SwiftUI
import Combine

/// Shared by the library and launcher-owned dialogs; no console artwork is downloaded.
struct ConsolePalette {
    let accent: Color
    let highlight: Color
    let text: Color
    let background: Color

    static func forConsole(_ console: Console) -> ConsolePalette {
        switch console {
        case .ps1:
            return ConsolePalette(accent: Color(red: 0.77, green: 0.67, blue: 0.43),
                                  highlight: Color(red: 0.98, green: 0.90, blue: 0.69),
                                  text: Color(red: 0.91, green: 0.90, blue: 0.85),
                                  background: Color(red: 0.065, green: 0.068, blue: 0.075))
        case .ps2:
            return ConsolePalette(accent: Color(red: 0.21, green: 0.43, blue: 0.92),
                                  highlight: Color(red: 0.68, green: 0.87, blue: 1),
                                  text: Color(red: 0.82, green: 0.87, blue: 0.97),
                                  background: Color(red: 0.009, green: 0.018, blue: 0.052))
        }
    }
}

/// Original, resolution-independent geometry: low-rate updates, paused when hidden.
struct ConsoleAtmosphere: View {
    let console: Console
    let active: Bool
    let reduceMotion: Bool

    var body: some View {
        let palette = ConsolePalette.forConsole(console)
        ZStack {
            palette.background
            LinearGradient(colors: [palette.accent.opacity(console == .ps1 ? 0.07 : 0.12), .clear, .black.opacity(0.5)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            TimelineView(.animation(minimumInterval: 1 / 12, paused: !active || reduceMotion)) { timeline in
                Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                    let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                    if console == .ps1 { drawPS1(context, size: size, time: time) }
                    else { drawPS2(context, size: size, time: time) }
                }
            }
        }
        .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }

    private func drawPS1(_ context: GraphicsContext, size: CGSize, time: TimeInterval) {
        let unit = min(size.width, size.height)
        guard unit > 0 else { return }
        let colors: [Color] = [Color(red: 0.79, green: 0.2, blue: 0.28), Color(red: 0.17, green: 0.61, blue: 0.54),
                               Color(red: 0.9, green: 0.71, blue: 0.19), Color(red: 0.23, green: 0.42, blue: 0.78)]
        for index in 0..<9 {
            let phase = Double(index) * 1.61
            let x = size.width * (0.07 + Double((index * 31) % 88) / 100)
            let y = size.height * (0.09 + Double((index * 19) % 80) / 100)
            let radius = unit * (0.027 + Double(index % 3) * 0.017)
            var layer = context
            layer.translateBy(x: x, y: y + sin(time * 0.09 + phase) * unit * 0.008)
            layer.rotate(by: .radians(phase + time * 0.008))
            let bounds = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
            var path = Path()
            if index % 3 == 0 {
                path.move(to: CGPoint(x: 0, y: -radius))
                path.addLine(to: CGPoint(x: radius, y: radius))
                path.addLine(to: CGPoint(x: -radius, y: radius))
                path.closeSubpath()
            } else if index % 3 == 1 { path.addRect(bounds) }
            else { path.addEllipse(in: bounds) }
            layer.fill(path, with: .color(colors[index % colors.count].opacity(0.016)))
            layer.stroke(path, with: .color(colors[index % colors.count].opacity(0.16)), lineWidth: 1)
        }
        var horizon = Path()
        horizon.move(to: CGPoint(x: 0, y: size.height * 0.91))
        horizon.addLine(to: CGPoint(x: size.width, y: size.height * 0.91))
        context.stroke(horizon, with: .color(.white.opacity(0.045)), lineWidth: 1)
    }

    private func drawPS2(_ context: GraphicsContext, size: CGSize, time: TimeInterval) {
        let unit = min(size.width, size.height)
        guard unit > 0 else { return }
        let blue = ConsolePalette.forConsole(.ps2).accent
        for index in 0..<15 {
            let x = size.width * (Double(index) / 14) - unit * 0.018
            let height = unit * (0.12 + Double((index * 17) % 31) / 100)
            let width = unit * (0.025 + Double(index % 3) * 0.012)
            let drift = sin(time * 0.07 + Double(index)) * unit * 0.009
            let rect = CGRect(x: x, y: size.height - height + drift, width: width, height: height)
            context.fill(Path(rect), with: .linearGradient(
                Gradient(colors: [blue.opacity(0.12), blue.opacity(0.012)]),
                startPoint: CGPoint(x: x, y: rect.minY), endPoint: CGPoint(x: x, y: size.height)))
            var top = Path()
            top.move(to: CGPoint(x: rect.minX, y: rect.minY))
            top.addLine(to: CGPoint(x: rect.minX + width * 0.35, y: rect.minY - width * 0.23))
            top.addLine(to: CGPoint(x: rect.maxX + width * 0.35, y: rect.minY - width * 0.23))
            top.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            top.closeSubpath()
            context.fill(top, with: .color(blue.opacity(0.14)))
        }
        let center = CGPoint(x: size.width * 0.82, y: size.height * 0.28)
        for index in 0..<7 {
            let angle = time * 0.11 + Double(index) * .pi * 2 / 7
            let x = center.x + cos(angle) * unit * 0.105
            let y = center.y + sin(angle) * unit * 0.061
            let radius = unit * 0.0045
            let orb = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: orb.insetBy(dx: -radius * 2.5, dy: -radius * 2.5)), with: .color(blue.opacity(0.028)))
            context.fill(Path(ellipseIn: orb), with: .color(Color.cyan.opacity(0.21)))
        }
    }
}

enum StartupMode: String, CaseIterable, Identifiable {
    case full, short, off
    var id: String { rawValue }
    var title: String {
        switch self { case .full: return "Completa"; case .short: return "Curta"; case .off: return "Desligada" }
    }
    /// nil preserves the full GIF. Zero skips it; a short boot is capped at 1.4 seconds.
    var durationLimit: TimeInterval? {
        switch self { case .full: return nil; case .short: return 1.4; case .off: return 0 }
    }
}

enum ExperienceMotionMode: String, CaseIterable, Identifiable {
    case system, reduced
    var id: String { rawValue }
    var title: String { self == .system ? "Seguir o macOS" : "Movimento reduzido" }
}

enum ExperienceSetting: Int, CaseIterable { case startup, sound, volume, motion, done }

@MainActor
final class ExperiencePreferences: ObservableObject {
    private let defaults: UserDefaults
    private static let prefix = "experience.v1."
    @Published var startupMode: StartupMode { didSet { defaults.set(startupMode.rawValue, forKey: Self.prefix + "startup") } }
    @Published var soundsEnabled: Bool { didSet { defaults.set(soundsEnabled, forKey: Self.prefix + "sounds") } }
    @Published private var storedSoundVolume: Double
    var soundVolume: Double {
        get { storedSoundVolume }
        set {
            let volume = newValue.isFinite ? min(1, max(0, newValue)) : 0.35
            storedSoundVolume = volume
            defaults.set(volume, forKey: Self.prefix + "volume")
        }
    }
    @Published var motionMode: ExperienceMotionMode { didSet { defaults.set(motionMode.rawValue, forKey: Self.prefix + "motion") } }
    @Published var focusedSetting: ExperienceSetting = .startup

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        startupMode = StartupMode(rawValue: defaults.string(forKey: Self.prefix + "startup") ?? "") ?? .full
        soundsEnabled = defaults.bool(forKey: Self.prefix + "sounds")
        let savedVolume = defaults.object(forKey: Self.prefix + "volume") as? Double ?? 0.35
        storedSoundVolume = savedVolume.isFinite ? min(1, max(0, savedVolume)) : 0.35
        motionMode = ExperienceMotionMode(rawValue: defaults.string(forKey: Self.prefix + "motion") ?? "") ?? .system
    }
    func reduceMotion(system: Bool) -> Bool { system || motionMode == .reduced }
    func moveFocus(_ delta: Int) {
        let settings = ExperienceSetting.allCases
        focusedSetting = settings[max(0, min(settings.count - 1, focusedSetting.rawValue + delta))]
    }
    func adjust(_ delta: Int) {
        guard delta != 0 else { return }
        switch focusedSetting {
        case .startup: startupMode = cycle(startupMode, choices: StartupMode.allCases, delta: delta)
        case .sound: soundsEnabled.toggle()
        case .volume: soundVolume = (soundVolume * 10 + Double(delta.signum())).rounded() / 10
        case .motion: motionMode = cycle(motionMode, choices: ExperienceMotionMode.allCases, delta: delta)
        case .done: break
        }
    }
    /// True means the launcher should close the overlay.
    @discardableResult func confirmSelection() -> Bool {
        if focusedSetting == .done { return true }
        adjust(1)
        return false
    }
    private func cycle<T: Equatable>(_ value: T, choices: [T], delta: Int) -> T {
        let index = choices.firstIndex(of: value) ?? 0
        return choices[(index + delta.signum() + choices.count) % choices.count]
    }
}

struct ExperienceSettingsView: View {
    @ObservedObject var preferences: ExperiencePreferences
    let console: Console
    let dismiss: () -> Void
    private var palette: ConsolePalette { .forConsole(console) }

    var body: some View {
        ZStack {
            palette.background.opacity(0.96).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 13) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 25)).foregroundStyle(palette.highlight)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Experiência de console").font(.system(size: 25, weight: .light, design: .rounded))
                        Text("Personalize a inicialização, os sons e o movimento.")
                            .font(.system(size: 12)).foregroundStyle(palette.text.opacity(0.7))
                    }
                    Spacer()
                    Text(console.badge).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(palette.highlight)
                }.padding(.bottom, 5)
                settingRow(.startup, title: "Animação de inicialização", subtitle: "Pode ser pulada antes de abrir o jogo.") {
                    choices(StartupMode.allCases, value: preferences.startupMode, title: { $0.title }) {
                        preferences.focusedSetting = .startup
                        preferences.startupMode = $0
                    }
                }
                settingRow(.sound, title: "Sons de navegação", subtitle: "Efeitos originais; não alteram o áudio do jogo.") {
                    Button(preferences.soundsEnabled ? "Ligados" : "Desligados") {
                        preferences.focusedSetting = .sound
                        preferences.soundsEnabled.toggle()
                    }.buttonStyle(.plain).foregroundStyle(palette.highlight)
                        .accessibilityLabel("Sons de navegação")
                        .accessibilityValue(preferences.soundsEnabled ? "Ligados" : "Desligados")
                }
                settingRow(.volume, title: "Volume dos efeitos", subtitle: "Somente na central, enquanto ela estiver ativa.") {
                    HStack(spacing: 9) {
                        Slider(value: $preferences.soundVolume, in: 0...1, step: 0.1)
                            .frame(width: 130).tint(palette.accent)
                            .onTapGesture { preferences.focusedSetting = .volume }
                            .accessibilityLabel("Volume dos efeitos")
                        Text("\(Int((preferences.soundVolume * 100).rounded()))%")
                            .font(.system(size: 11, design: .monospaced)).frame(width: 36, alignment: .trailing)
                    }
                }
                settingRow(.motion, title: "Animações de fundo", subtitle: "O movimento reduzido do macOS é sempre respeitado.") {
                    Button(preferences.motionMode.title) {
                        preferences.focusedSetting = .motion
                        preferences.adjust(1)
                    }.buttonStyle(.plain).foregroundStyle(palette.highlight)
                        .accessibilityLabel("Animações de fundo").accessibilityValue(preferences.motionMode.title)
                }
                HStack {
                    Text("↑↓ Selecionar   ←→ Ajustar   × Confirmar   ○ Voltar")
                        .font(.system(size: 10)).foregroundStyle(palette.text.opacity(0.65))
                    Spacer()
                    Button("Concluído") { dismiss() }
                        .buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 17).padding(.vertical, 9)
                        .background(palette.accent.opacity(0.24), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(palette.highlight.opacity(preferences.focusedSetting == .done ? 0.85 : 0.2)))
                }.padding(.top, 6)
            }
            .foregroundStyle(palette.text).padding(26).frame(maxWidth: 760)
            .background(palette.accent.opacity(0.075), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(palette.highlight.opacity(0.25)))
            .padding(24)
        }
        .accessibilityElement(children: .contain).accessibilityLabel("Configurações da experiência de console")
    }

    private func settingRow<Content: View>(_ setting: ExperienceSetting, title: String, subtitle: String,
                                            @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(subtitle).font(.system(size: 10)).foregroundStyle(palette.text.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            content().font(.system(size: 11))
        }
        .padding(14).background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .stroke(palette.highlight.opacity(preferences.focusedSetting == setting ? 0.62 : 0.12)))
        .contentShape(Rectangle()).onTapGesture { preferences.focusedSetting = setting }
    }

    private func choices<T: Hashable>(_ values: [T], value: T, title: @escaping (T) -> String,
                                      select: @escaping (T) -> Void) -> some View {
        HStack(spacing: 4) {
            ForEach(values, id: \.self) { option in
                Button(title(option)) { select(option) }
                    .buttonStyle(.plain).padding(.horizontal, 9).padding(.vertical, 7)
                    .background(value == option ? palette.accent.opacity(0.27) : .clear, in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(value == option ? palette.highlight : palette.text.opacity(0.65))
                    .accessibilityAddTraits(value == option ? .isSelected : [])
            }
        }
    }
}

enum ConsoleSoundCue: String, CaseIterable { case navigate, confirm, back }

/// Original synthesized PCM cues, not Sony recordings or BIOS sounds.
@MainActor
final class ConsoleSoundPlayer {
    typealias Cue = ConsoleSoundCue
    private var clips: [String: NSSound] = [:]
    private var lastNavigation = Date.distantPast

    func play(_ cue: Cue, console: Console, preferences: ExperiencePreferences) {
        guard preferences.soundsEnabled, preferences.soundVolume > 0, NSApp?.isActive == true else { return }
        let now = Date()
        if cue == .navigate {
            guard now.timeIntervalSince(lastNavigation) >= 0.075 else { return }
            lastNavigation = now
        }
        let key = console.rawValue + "." + cue.rawValue
        let sound: NSSound
        if let saved = clips[key] { sound = saved }
        else {
            guard let created = NSSound(data: Self.waveData(cue, console: console)) else { return }
            clips[key] = created
            sound = created
        }
        // Six reusable clips, so held analog input never queues unbounded audio.
        if sound.isPlaying { sound.stop() }
        sound.volume = Float(preferences.soundVolume)
        sound.play()
    }
    func stop() { for sound in clips.values where sound.isPlaying { sound.stop() } }

    /// Pure synthesis can be tested without playing sound or writing files.
    static func waveData(_ cue: Cue, console: Console) -> Data {
        let sampleRate = 22_050
        let duration: Double = cue == .navigate ? 0.055 : 0.115
        let count = Int(Double(sampleRate) * duration)
        let base: Double = console == .ps1 ? 620 : 760
        var samples = Data(capacity: count * 2)
        for index in 0..<count {
            let t = Double(index) / Double(sampleRate)
            let progress = Double(index) / Double(max(1, count - 1))
            let frequency: Double
            switch cue {
            case .navigate: frequency = base
            case .confirm: frequency = base * (progress < 0.45 ? 1 : 1.5)
            case .back: frequency = base * (progress < 0.45 ? 0.95 : 0.7)
            }
            let tone = sin(2 * .pi * frequency * t)
            let overtone = console == .ps1 ? sin(2 * .pi * frequency * 3 * t) * 0.12 : 0
            let attack = min(1, t / 0.006)
            let release = pow(max(0, 1 - progress), 1.8)
            let amplitude = (tone + overtone) * attack * release * 0.18
            appendLE(Int16((amplitude * Double(Int16.max)).rounded()), to: &samples)
        }
        var result = Data("RIFF".utf8)
        appendLE(UInt32(36 + samples.count), to: &result)
        result.append(contentsOf: "WAVEfmt ".utf8)
        appendLE(UInt32(16), to: &result)
        appendLE(UInt16(1), to: &result)
        appendLE(UInt16(1), to: &result)
        appendLE(UInt32(sampleRate), to: &result)
        appendLE(UInt32(sampleRate * 2), to: &result)
        appendLE(UInt16(2), to: &result)
        appendLE(UInt16(16), to: &result)
        result.append(contentsOf: "data".utf8)
        appendLE(UInt32(samples.count), to: &result)
        result.append(samples)
        return result
    }
    private static func appendLE<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}
