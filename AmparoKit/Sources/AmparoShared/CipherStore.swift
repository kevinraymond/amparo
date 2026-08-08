import AmparoAPI
import Foundation

/// What survives between launches: the member-consumable ciphers exactly as
/// the server sent them (every secret still an EncString, §7.3) plus the
/// serialized org-key EncStrings so a post-enrollment organization can be
/// unwrapped late.
public struct VaultSnapshot: Codable, Equatable, Sendable {
    public var syncedAt: Date
    public var organizationKeyStrings: [String: String]
    public var ciphers: [Cipher]

    public init(syncedAt: Date, organizationKeyStrings: [String: String], ciphers: [Cipher]) {
        self.syncedAt = syncedAt
        self.organizationKeyStrings = organizationKeyStrings
        self.ciphers = ciphers
    }
}

/// Flat-JSON store in the App Group container (D5): tens of ciphers at most,
/// nothing here is plaintext, and Codable round-trips the wire format
/// losslessly. Atomic writes; complete file protection on device.
public struct CipherStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The shared container both the app and the autofill extension read.
    public static func appGroup(_ identifier: String = "group.onl.kev.amparo") -> CipherStore? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: identifier) else { return nil }
        return CipherStore(fileURL: container.appendingPathComponent("vault-snapshot.json"))
    }

    /// nil = never synced. A file that exists but does not decode is
    /// `VaultStoreError.storeCorrupted` — the app routes that to
    /// call-caregiver, never tries to repair.
    public func load() throws -> VaultSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            return try Self.decoder().decode(VaultSnapshot.self, from: data)
        } catch {
            throw VaultStoreError.storeCorrupted
        }
    }

    public func save(_ snapshot: VaultSnapshot) throws {
        let data = try Self.encoder().encode(snapshot)
        #if os(iOS)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: fileURL, options: [.atomic])
        #endif
    }

    public func wipe() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
