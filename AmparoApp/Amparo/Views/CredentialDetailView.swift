import AmparoCrypto
import AmparoShared
import SwiftUI
import UniformTypeIdentifiers

/// §7.4 detail: username shown large, one giant copy button (60 s clipboard
/// expiry), an explicit reveal with 30 s auto-hide, and the TOTP ring when
/// the site uses codes. Nothing else.
struct CredentialDetailView: View {
    @Environment(AppModel.self) private var model
    let tile: MemberTile

    @State private var secrets: CredentialSecrets?
    @State private var revealed = false
    @State private var copied = false
    @State private var hideTask: Task<Void, Never>?
    @State private var copiedTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                if let username = secrets?.username ?? tile.username {
                    VStack(spacing: 4) {
                        Text(String(localized: "username.label"))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text(username)
                            .font(.title.bold())
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                    }
                }
                if let password = secrets?.password {
                    Button {
                        copy(password)
                    } label: {
                        Label(
                            copied ? String(localized: "copied") : String(localized: "copy.password"),
                            systemImage: copied ? "checkmark" : "doc.on.doc"
                        )
                        .font(.title.bold())
                        .frame(maxWidth: .infinity, minHeight: 88)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel(String(localized: "copy.password"))

                    Button {
                        toggleReveal()
                    } label: {
                        Text(revealed ? String(localized: "reveal.hide") : String(localized: "reveal.show"))
                            .font(.title2)
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                    .buttonStyle(.bordered)

                    if revealed {
                        Text(password)
                            .font(.system(.title2, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                    }
                }
                if let totp = secrets?.totp {
                    TOTPView(generator: totp)
                }
            }
            .padding(24)
        }
        .navigationTitle(tile.displayName)
        .task { await load() }
        .onDisappear {
            hideTask?.cancel()
            copiedTask?.cancel()
        }
        .dynamicTypeSize(DynamicTypeSize.accessibility1...DynamicTypeSize.accessibility5)
    }

    private func load() async {
        do {
            secrets = try await model.vault.secrets(forCipher: tile.id)
        } catch {
            model.failToHuman()
        }
    }

    private func copy(_ password: String) {
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: password]],
            options: [
                .localOnly: true,
                .expirationDate: Date().addingTimeInterval(60),
            ]
        )
        copied = true
        copiedTask?.cancel()
        copiedTask = Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    private func toggleReveal() {
        revealed.toggle()
        hideTask?.cancel()
        if revealed {
            hideTask = Task {
                try? await Task.sleep(for: .seconds(30))
                revealed = false
            }
        }
    }
}

struct TOTPView: View {
    let generator: TOTPGenerator

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = generator.secondsRemaining(at: context.date)
            let code = generator.code(at: context.date)
            VStack(spacing: 12) {
                Text(spaced(code))
                    .font(.system(size: 64, weight: .bold, design: .monospaced))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .accessibilityLabel(Text(String(localized: "code.label")))
                    .accessibilityValue(code)
                ZStack {
                    Circle()
                        .stroke(Color(.systemFill), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: CGFloat(remaining) / CGFloat(generator.period))
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(remaining)")
                        .font(.headline)
                        .monospacedDigit()
                }
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            }
        }
    }

    private func spaced(_ code: String) -> String {
        let mid = code.index(code.startIndex, offsetBy: code.count / 2)
        return String(code[..<mid]) + " " + String(code[mid...])
    }
}
