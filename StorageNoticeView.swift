import SwiftUI

struct StorageNotice: Equatable, Sendable {
    let gameTitle: String
    let consoleName: String
    var volumeName: String = "Extreme SSD"
}

/// A local-storage notice, styled like the central's console UI. The launcher
/// owns keyboard/controller routing and disables the content underneath it.
struct StorageNoticeView: View {
    let notice: StorageNotice
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let scale = min(1, min(max(0, geometry.size.width - 40) / 560,
                                   max(0, geometry.size.height - 40) / 380))
            ZStack {
                Theme.background.opacity(0.90)
                RadialGradient(colors: [Theme.blue.opacity(0.17), .clear],
                               center: .center, startRadius: 50, endRadius: 470)
                panel
                    .frame(width: 560)
                    .scaleEffect(scale)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Aviso de armazenamento da biblioteca")
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.blue.opacity(0.15))
                    Image(systemName: "externaldrive")
                        .font(.system(size: 25, weight: .light))
                        .foregroundStyle(Theme.ice)
                }
                .frame(width: 54, height: 54)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.ice.opacity(0.25), lineWidth: 0.7))
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 7) {
                    Text("PS1/2  ·  ARMAZENAMENTO")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1.8)
                        .foregroundStyle(Theme.ice.opacity(0.78))
                    Text(notice.volumeName == "Extreme SSD" ? "Conecte o SSD para jogar" : "Conecte o disco para jogar")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
            }

            Rectangle()
                .fill(LinearGradient(colors: [Theme.ice.opacity(0.38), Theme.blue.opacity(0.04)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 12) {
                Text("Para abrir este jogo no \(notice.consoleName), conecte \(notice.volumeName) ao Mac. Se a pasta mudou, confira Pastas de jogos.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.pale.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "opticaldisc")
                        .font(.system(size: 17, weight: .light))
                        .foregroundStyle(Theme.ice.opacity(0.85))
                        .accessibilityHidden(true)
                    Text(notice.gameTitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Jogo: \(notice.gameTitle)")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.22)))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.ice.opacity(0.10), lineWidth: 0.6))

                Text("O catálogo e as capas salvas continuam disponíveis.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.pale.opacity(0.66))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                Button(action: onDismiss) {
                    HStack(spacing: 10) {
                        Text("Voltar ao catálogo")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text("×")
                            .font(.system(size: 22, weight: .light))
                        Text("Enter")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.pale.opacity(0.78))
                    }
                    .foregroundStyle(Theme.ice)
                    .padding(.horizontal, 16)
                    .frame(height: 43)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.blue.opacity(0.18)))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.ice.opacity(0.46), lineWidth: 0.8))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Voltar ao catálogo")
                .accessibilityHint("Fecha o aviso. Use X ou círculo no controle, Enter ou Esc no teclado.")

                HStack(spacing: 7) {
                    Text("○").font(.system(size: 15, weight: .light))
                    Text("Esc  ·  Voltar").font(.system(size: 10, design: .monospaced))
                }
                .foregroundStyle(Theme.pale.opacity(0.55))
                .accessibilityHidden(true)
            }
        }
        .padding(28)
        .background {
            RoundedRectangle(cornerRadius: 15)
                .fill(LinearGradient(colors: [Color(red: 0.035, green: 0.078, blue: 0.18), Theme.background],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 15)
            .stroke(LinearGradient(colors: [Theme.ice.opacity(0.34), Theme.blue.opacity(0.12)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.5), radius: 32, y: 16)
        .shadow(color: Theme.blue.opacity(0.13), radius: 25)
    }
}
