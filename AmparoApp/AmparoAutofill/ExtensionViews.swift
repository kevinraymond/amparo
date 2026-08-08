import AmparoShared
import AuthenticationServices
import SwiftUI

/// Big-tile picker (§8): the app's home-grid visual language, filtered to
/// the requesting service when anything matches, everything otherwise.
/// Monogram tiles only — the icon cache lives in the app container (v1).
struct CredentialPickerView: View {
    let vault: VaultStore
    let serviceIdentifiers: [String]
    let onPick: (ASPasswordCredential) -> Void
    let onCancel: () -> Void

    @State private var tiles: [MemberTile] = []
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if failed {
                    ExtensionFailureView(onCancel: onCancel)
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 150), spacing: 16)],
                            spacing: 16
                        ) {
                            ForEach(displayedTiles) { tile in
                                Button {
                                    pick(tile)
                                } label: {
                                    ExtensionTileView(tile: tile)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(tile.displayName)
                            }
                        }
                        .padding()
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "cancel")) { onCancel() }
                }
            }
        }
        .dynamicTypeSize(DynamicTypeSize.accessibility1...DynamicTypeSize.accessibility5)
        .task { await load() }
    }

    private var displayedTiles: [MemberTile] {
        let matching = tiles.filter { tile in
            serviceIdentifiers.contains {
                AutofillMatcher.matches(serviceIdentifier: $0, domain: tile.domain)
            }
        }
        return matching.isEmpty ? tiles : matching
    }

    private func load() async {
        do {
            tiles = try await vault.tiles()  // Face ID fires here
        } catch is KeychainError {
            onCancel()                       // member declined Face ID
        } catch {
            failed = true
        }
    }

    private func pick(_ tile: MemberTile) {
        Task {
            guard let secrets = try? await vault.secrets(forCipher: tile.id),
                  let password = secrets.password else {
                failed = true
                return
            }
            onPick(ASPasswordCredential(user: secrets.username ?? "", password: password))
        }
    }
}

struct ExtensionTileView: View {
    let tile: MemberTile

    var body: some View {
        VStack(spacing: 12) {
            Text(String(tile.displayName.prefix(1)))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(Color.accentColor.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            Text(tile.displayName)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

/// The interactive fallback: attempts the fill on appear (Face ID), leaves
/// a single giant retry button if the member cancelled.
struct UnlockAndFillView: View {
    let attempt: () async throws -> ASPasswordCredential?
    let onFilled: (ASPasswordCredential) -> Void
    let onCancel: () -> Void

    @State private var failed = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            if failed {
                ExtensionFailureView(onCancel: onCancel)
            } else {
                Image(systemName: "faceid")
                    .font(.system(size: 64))
                    .accessibilityHidden(true)
                Button {
                    Task { await run() }
                } label: {
                    Text(String(localized: "unlock.button"))
                        .font(.title.bold())
                        .frame(maxWidth: .infinity, minHeight: 80)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 32)
                Button(String(localized: "cancel")) { onCancel() }
                    .font(.title3)
            }
            Spacer()
        }
        .dynamicTypeSize(DynamicTypeSize.accessibility1...DynamicTypeSize.accessibility5)
        .task { await run() }
    }

    private func run() async {
        do {
            if let credential = try await attempt() {
                onFilled(credential)
            } else {
                failed = true
            }
        } catch is KeychainError {
            // Cancelled Face ID: stay — the retry button is on screen.
        } catch {
            failed = true
        }
    }
}

/// Principle 4, extension flavor: calm copy pointing at the family, one
/// cancel button. No tel: links from an extension context — the app is the
/// place with the giant call button.
struct ExtensionFailureView: View {
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "phone.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(String(localized: "call.title"))
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(String(localized: "call.body.generic"))
                .font(.title3)
                .multilineTextAlignment(.center)
            Button(String(localized: "cancel")) { onCancel() }
                .font(.title3)
        }
        .padding(24)
    }
}
