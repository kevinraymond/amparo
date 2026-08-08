import AmparoAPI
import AmparoShared
import SwiftUI

/// App-level state machine. The routing rule is handoff principle 4: every
/// member-facing failure terminates at the call-caregiver screen; the only
/// exceptions are Face ID cancellation (retryable, `.locked`) and background
/// sync hiccups (member keeps working from the snapshot).
@MainActor
@Observable
final class AppModel {
    enum Phase {
        case loading
        case enrollment
        case locked
        case home([MemberTile])
        case callCaregiver
    }

    private(set) var phase: Phase = .loading
    private(set) var caregiver: CaregiverProfile?
    let vault: VaultStore
    private let iconCache: IconCache

    init() {
        self.vault = VaultStore.makeShared()
        self.iconCache = IconCache(directory: URL.cachesDirectory.appendingPathComponent("icons"))
    }

    func start() async {
        caregiver = await vault.caregiverProfile()
        guard await vault.isEnrolled() else {
            phase = .enrollment
            return
        }
        await unlock()
    }

    /// Reading the vault triggers Face ID (§7.3) — this *is* the unlock UX.
    /// Any keychain-level hiccup (cancelled Face ID, device not fully
    /// unlocked yet → interaction-not-allowed, …) is retryable `.locked`;
    /// only vault-level states (biometry invalidated, store corrupted) are
    /// terminal.
    func unlock() async {
        do {
            let tiles = try await vault.tiles()
            phase = .home(tiles)
            // QuickType registration happens here, not post-sync: only an
            // unlocked session has decrypted domains/usernames (D20).
            await CredentialIdentityRegistrar.update(from: tiles)
        } catch is KeychainError {
            phase = .locked
        } catch {
            failToHuman()
        }
    }

    func enteredBackground() {
        Task { await vault.lock() }
        if case .home = phase {
            phase = .locked
        }
    }

    func becameActive() async {
        switch phase {
        case .loading:
            await start()
        case .locked:
            await refreshFromServer()
            await unlock()
        case .home:
            await refreshFromServer()
            if let tiles = try? await vault.tiles() {
                phase = .home(tiles)
                await CredentialIdentityRegistrar.update(from: tiles)
            }
        case .callCaregiver:
            // Self-heal: if the vault wasn't actually purged (transient
            // failure landed here), a fresh foreground quietly retries.
            // A genuinely purged vault stays on the call screen.
            if await vault.isEnrolled() {
                await refreshFromServer()
                await unlock()
            }
        case .enrollment:
            break
        }
    }

    func completeEnrollment() async {
        caregiver = await vault.caregiverProfile()
        await unlock()
    }

    func resetEnrollment() async {
        await vault.reset()
        await CredentialIdentityRegistrar.removeAll()
        phase = .enrollment
    }

    func failToHuman() {
        phase = .callCaregiver
    }

    func icon(for domain: String?) async -> UIImage? {
        guard let domain else { return nil }
        let vault = vault
        let data = await iconCache.icon(for: domain) { domain in
            await vault.fetchIconData(domain: domain)
        }
        return data.flatMap(UIImage.init(data:))
    }

    /// Foreground sync. Offline or a flaky server never disturbs the member
    /// (local-first, principle 5); only a definitive revocation — which has
    /// already purged secrets — changes the screen.
    private func refreshFromServer() async {
        guard await vault.isEnrolled() else { return }
        do {
            try await vault.syncNow()
        } catch AmparoError.reenrollRequired {
            failToHuman()
        } catch {
            // Transient or unexpected: keep the snapshot, stay quiet.
        }
    }
}
