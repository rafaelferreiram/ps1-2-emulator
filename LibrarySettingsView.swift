import SwiftUI

struct LibrarySettingsView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var settings: GameLibrarySettings

    var body: some View {
        ZStack {
            Theme.background.opacity(0.97).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Image(systemName: "folder.badge.gearshape").font(.system(size: 26)).foregroundStyle(Theme.ice)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Game folders").font(.system(size: 26, weight: .light, design: .rounded))
                        Text("Choose where to look for the PS1 and PS2 catalogs.")
                            .font(.system(size: 12)).foregroundStyle(Theme.pale)
                    }
                    Spacer()
                    Button("Done · Esc") { model.dismissLibrarySettings() }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.ice)
                        .disabled(model.choosingLibraryFolder)
                }
                ForEach(Console.allCases) { console in folderRow(console) }
                if let error = model.librarySettingsError {
                    Text(error).font(.system(size: 12)).foregroundStyle(.orange).lineLimit(3)
                }
                Text("One folder per console, including its subfolders. It can be on the Mac or on an external disk. Games are not copied or moved; BIOS, saves and emulator settings stay as they are.")
                    .font(.system(size: 12)).foregroundStyle(Theme.pale.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("↑↓ / Stick · Console     × / Enter · Choose folder     ○ / Esc · Back")
                        .font(.system(size: 10)).foregroundStyle(Theme.ice.opacity(0.7))
                    Spacer()
                }
            }
            .padding(28).frame(width: 720)
            .background(Theme.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Theme.ice.opacity(0.25), lineWidth: 1))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Game folder settings")
    }

    private func folderRow(_ console: Console) -> some View {
        let location = settings.location(for: console.rawValue)
        let selected = model.settingsConsole == console
        let isDefault = location == GameLibrarySettings.defaultLocation(for: console.rawValue)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                PlayerOneIndicator(selected: selected)
                Text(console.badge).font(.system(size: 18, weight: .semibold, design: .rounded))
                Text(console.emulator).font(.system(size: 11)).foregroundStyle(Theme.pale)
                Spacer()
                Text(isDefault ? "Default · Extreme SSD" : location.volumeName)
                    .font(.system(size: 10)).foregroundStyle(Theme.ice.opacity(0.8)).lineLimit(1)
            }
            Text(location.folder.path).font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.pale).lineLimit(2).truncationMode(.middle)
                .help(location.folder.path)
            HStack(spacing: 16) {
                Button {
                    model.settingsConsole = console
                    model.chooseLibraryFolder?(console)
                } label: {
                    Label("Choose folder…", systemImage: "folder")
                        .font(.system(size: 12)).padding(.horizontal, 13).padding(.vertical, 8)
                        .background(Theme.blue.opacity(0.23), in: RoundedRectangle(cornerRadius: 6))
                }
                .accessibilityLabel("Choose \(console.badge) game folder")
                Button("Restore default") { model.resetGameFolder(for: console) }
                    .font(.system(size: 11)).foregroundStyle(Theme.pale.opacity(isDefault ? 0.4 : 0.8))
                    .disabled(isDefault)
                    .accessibilityLabel("Restore default \(console.badge) folder")
                Spacer()
            }.buttonStyle(.plain).disabled(model.choosingLibraryFolder)
        }
        .padding(16)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Theme.ice.opacity(0.65) : Theme.ice.opacity(0.13), lineWidth: 1))
    }
}
