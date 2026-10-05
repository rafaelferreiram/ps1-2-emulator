import SwiftUI

struct LibrarySettingsView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var settings: GameLibrarySettings
    private var palette: ConsolePalette { .forConsole(model.settingsConsole) }

    var body: some View {
        ZStack {
            palette.background.opacity(0.97).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Image(systemName: "folder.badge.gearshape").font(.system(size: 26)).foregroundStyle(palette.highlight)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Pastas de jogos").font(.system(size: 26, weight: .light, design: .rounded))
                        Text("Escolha onde buscar as bibliotecas de PS1 e PS2.")
                            .font(.system(size: 12)).foregroundStyle(palette.text)
                    }
                    Spacer()
                    Button("Concluído · Esc") { model.dismissLibrarySettings() }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(palette.highlight)
                        .disabled(model.choosingLibraryFolder)
                }
                ForEach(Console.allCases) { console in folderRow(console) }
                if let error = model.librarySettingsError {
                    Text(error).font(.system(size: 12)).foregroundStyle(.orange).lineLimit(3)
                }
                Text("Uma pasta por console, incluindo subpastas. Pode estar no Mac ou em um disco externo. Nenhum jogo é copiado ou movido; BIOS, saves e configurações dos emuladores permanecem intactos.")
                    .font(.system(size: 12)).foregroundStyle(palette.text.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("↑↓ / Analógico · Console     × / Enter · Escolher pasta     ○ / Esc · Voltar")
                        .font(.system(size: 10)).foregroundStyle(palette.highlight.opacity(0.7))
                    Spacer()
                }
            }
            .foregroundStyle(palette.text)
            .padding(28).frame(maxWidth: 740)
            .background(palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(palette.highlight.opacity(0.25), lineWidth: 1))
            .padding(24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Configurações das pastas de jogos")
    }

    private func folderRow(_ console: Console) -> some View {
        let location = settings.location(for: console.rawValue)
        let selected = model.settingsConsole == console
        let isDefault = location == GameLibrarySettings.defaultLocation(for: console.rawValue)
        let rowPalette = ConsolePalette.forConsole(console)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                PlayerOneIndicator(selected: selected)
                Text(console.badge).font(.system(size: 18, weight: .semibold, design: .rounded))
                Text(console.emulator).font(.system(size: 11)).foregroundStyle(rowPalette.text)
                Spacer()
                Text(isDefault ? "Padrão · \(location.volumeName)" : location.volumeName)
                    .font(.system(size: 10)).foregroundStyle(rowPalette.highlight.opacity(0.8)).lineLimit(1)
            }
            Text(location.folder.path).font(.system(size: 11, design: .monospaced))
                .foregroundStyle(rowPalette.text).lineLimit(2).truncationMode(.middle)
                .help(location.folder.path)
            HStack(spacing: 16) {
                Button {
                    model.settingsConsole = console
                    model.chooseLibraryFolder?(console)
                } label: {
                    Label("Escolher pasta…", systemImage: "folder")
                        .font(.system(size: 12)).padding(.horizontal, 13).padding(.vertical, 8)
                        .background(rowPalette.accent.opacity(0.23), in: RoundedRectangle(cornerRadius: 6))
                }
                .accessibilityLabel("Escolher pasta dos jogos de \(console.badge)")
                Button("Restaurar padrão") { model.resetGameFolder(for: console) }
                    .font(.system(size: 11)).foregroundStyle(rowPalette.text.opacity(isDefault ? 0.4 : 0.8))
                    .disabled(isDefault)
                    .accessibilityLabel("Restaurar pasta padrão de \(console.badge)")
                Spacer()
            }.buttonStyle(.plain).disabled(model.choosingLibraryFolder)
        }
        .padding(16)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(rowPalette.highlight.opacity(selected ? 0.65 : 0.13), lineWidth: 1))
    }
}
