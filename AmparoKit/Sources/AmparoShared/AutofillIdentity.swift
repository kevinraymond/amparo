import AmparoAPI
import AuthenticationServices
import Foundation

/// The identifiers the app and the autofill extension must agree on.
public enum AmparoIdentifiers {
    public static let keychainService = "onl.kev.amparo"
    public static let appGroup = "group.onl.kev.amparo"
}

extension VaultStore {
    /// The one production configuration, shared by the app and the autofill
    /// extension: app-group keychain + app-group snapshot.
    public static func makeShared(transport: any HTTPTransport = URLSessionTransport()) -> VaultStore {
        VaultStore(
            keychain: KeychainStore(configuration: .init(
                service: AmparoIdentifiers.keychainService,
                accessGroup: AmparoIdentifiers.appGroup
            )),
            cipherStore: CipherStore.appGroup(AmparoIdentifiers.appGroup) ?? CipherStore(
                fileURL: URL.applicationSupportDirectory.appendingPathComponent("vault-snapshot.json")
            ),
            transport: transport
        )
    }
}

/// QuickType registration (§8, amended by D20): identities are derived from
/// *decrypted* tiles, so registration runs after each unlock — not after
/// sync, which happens before Face ID and only holds EncStrings. A new
/// credential reaches QuickType the next time the member opens the app.
public enum CredentialIdentityRegistrar {
    /// The pure mapping, separated for tests: only tiles with both a domain
    /// and a username can be offered by QuickType.
    static func identities(from tiles: [MemberTile]) -> [ASPasswordCredentialIdentity] {
        tiles.compactMap { tile in
            guard let domain = tile.domain, let username = tile.username else { return nil }
            return ASPasswordCredentialIdentity(
                serviceIdentifier: ASCredentialServiceIdentifier(identifier: domain, type: .domain),
                user: username,
                recordIdentifier: tile.id
            )
        }
    }

    /// Full replace: the vault is small and replace-all is idempotent.
    /// No-op when the member hasn't enabled Amparo in AutoFill settings.
    public static func update(from tiles: [MemberTile]) async {
        let store = ASCredentialIdentityStore.shared
        guard await store.state().isEnabled else { return }
        try? await store.replaceCredentialIdentities(identities(from: tiles))
    }

    /// Enrollment reset / purge: QuickType must stop suggesting immediately.
    public static func removeAll() async {
        try? await ASCredentialIdentityStore.shared.removeAllCredentialIdentities()
    }
}

/// Service-identifier ↔ stored-domain matching for the extension's picker.
/// Identifiers arrive as URLs or bare hosts; tiles store bare domains.
/// Subdomain-tolerant in both directions (`www.banco.example.com` matches a
/// stored `banco.example.com` and vice versa).
public enum AutofillMatcher {
    public static func matches(serviceIdentifier: String, domain: String?) -> Bool {
        guard let domain, !domain.isEmpty,
              let host = host(from: serviceIdentifier) else { return false }
        let stored = domain.lowercased()
        return host == stored
            || host.hasSuffix("." + stored)
            || stored.hasSuffix("." + host)
    }

    public static func host(from identifier: String) -> String? {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("://"), let hostname = URL(string: trimmed)?.host {
            return hostname
        }
        guard !trimmed.contains("/") else { return nil }
        return trimmed
    }
}
