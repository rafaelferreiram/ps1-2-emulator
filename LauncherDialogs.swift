import SwiftUI

@MainActor
struct LauncherDialog {
    let title: String
    let message: String
    let acceptTitle: String
    let accept: () -> Void
}

enum SessionMenuAction: String, Identifiable {
    case resume, openEmulator, stop, appearance, libraries, close
    var id: String { rawValue }
    var title: String {
        switch self {
        case .resume: return "Voltar à sessão"
        case .openEmulator: return "Abrir emulador sem jogo"
        case .stop: return "Desligar emulador…"
        case .appearance: return "Ambiente, som e inicialização"
        case .libraries: return "Pastas dos jogos"
        case .close: return "Voltar"
        }
    }
    var icon: String {
        switch self {
        case .resume: return "play.fill"
        case .openEmulator: return "gamecontroller"
        case .stop: return "power"
        case .appearance: return "sparkles"
        case .libraries: return "folder"
        case .close: return "arrow.uturn.backward"
        }
    }
}

struct LauncherMessageView: View {
    @ObservedObject var model: LauncherModel
    private var palette: ConsolePalette { .forConsole(model.activeConsole) }
    var body: some View {
        ZStack {
            palette.background.opacity(0.98)
            VStack(alignment: .leading, spacing: 22) {
                Text(model.activeConsole.badge + "  /  SISTEMA")
                    .font(.system(size: 11, weight: .medium)).tracking(3).foregroundStyle(palette.highlight)
                Text(model.errorMessage != nil ? "Não foi possível continuar" : model.dialog?.title ?? "")
                    .font(.system(size: 25, weight: .light)).foregroundStyle(.white)
                Text(model.errorMessage ?? model.dialog?.message ?? "")
                    .font(.system(size: 14)).foregroundStyle(palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 16) {
                    if model.errorMessage != nil {
                        action("Entendi · ×", selected: true) { model.errorMessage = nil }
                    } else {
                        action("Cancelar · ○", selected: !model.dialogAcceptSelected) { model.dialog = nil }
                        action(model.dialog?.acceptTitle ?? "Continuar", selected: model.dialogAcceptSelected) {
                            model.dialogAcceptSelected = true
                            model.confirm()
                        }
                    }
                }
                Text("← → selecionar     × confirmar     ○ voltar")
                    .font(.system(size: 11)).foregroundStyle(palette.text.opacity(0.7))
            }
            .padding(30).frame(width: 620)
            .background(palette.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.highlight.opacity(0.3)))
        }.accessibilityElement(children: .contain)
    }
    private func action(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white).padding(.horizontal, 18).padding(.vertical, 12)
                .background(palette.accent.opacity(selected ? 0.35 : 0.08), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.highlight.opacity(selected ? 0.9 : 0.15)))
        }.buttonStyle(.plain)
    }
}

struct SessionMenuView: View {
    @ObservedObject var model: LauncherModel
    private var palette: ConsolePalette { .forConsole(model.activeConsole) }
    var body: some View {
        ZStack {
            palette.background.opacity(0.97)
            VStack(alignment: .leading, spacing: 12) {
                Text(model.activeConsole.badge + "  /  OPÇÕES")
                    .font(.system(size: 12, weight: .medium)).tracking(3).foregroundStyle(palette.highlight)
                    .padding(.bottom, 12)
                ForEach(Array(model.sessionActions.enumerated()), id: \.element.id) { index, action in
                    Button {
                        model.sessionMenuIndex = index
                        model.activateSessionAction()
                    } label: {
                        HStack(spacing: 15) {
                            PlayerOneIndicator(selected: model.sessionMenuIndex == index)
                            Label(action.title, systemImage: action.icon)
                            Spacer()
                        }.font(.system(size: 15)).padding(13)
                            .background(palette.accent.opacity(model.sessionMenuIndex == index ? 0.2 : 0.03), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.highlight.opacity(model.sessionMenuIndex == index ? 0.7 : 0.06)))
                    }.buttonStyle(.plain).foregroundStyle(palette.text)
                }
                Text("↑ ↓ selecionar     × confirmar     ○ voltar")
                    .font(.system(size: 11)).foregroundStyle(palette.text.opacity(0.65)).padding(.top, 14)
            }.padding(30).frame(width: 630)
        }.accessibilityElement(children: .contain)
    }
}
