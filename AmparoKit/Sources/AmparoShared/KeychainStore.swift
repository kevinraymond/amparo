import Foundation
import Security

/// Raw-Data keychain access for the shared items (§7.3). Writes are
/// delete-then-add upserts; reads of biometry-protected items make the
/// system present Face ID automatically.
public final class KeychainStore: @unchecked Sendable {
    public struct Configuration: Sendable {
        public let service: String
        /// Shared access group so app and autofill extension see the same
        /// items; nil for unit tests and non-provisioned builds.
        public let accessGroup: String?

        public init(service: String = "onl.kev.amparo", accessGroup: String? = nil) {
            self.service = service
            self.accessGroup = accessGroup
        }
    }

    private let configuration: Configuration
    private let client: any SecItemClient

    public convenience init(configuration: Configuration = Configuration()) {
        self.init(configuration: configuration, client: SystemSecItemClient())
    }

    init(configuration: Configuration, client: any SecItemClient) {
        self.configuration = configuration
        self.client = client
    }

    public func store(_ data: Data, for item: KeychainItem) throws {
        _ = client.delete(baseQuery(item))
        var attributes = baseQuery(item)
        attributes[kSecValueData] = data
        if item.isBiometryProtected {
            guard let control = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet, nil
            ) else { throw KeychainError.accessControlCreationFailed }
            attributes[kSecAttrAccessControl] = control
        } else {
            attributes[kSecAttrAccessible] = kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        }
        let status = client.add(attributes)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    /// nil means not present — for a biometry item whose enrollment markers
    /// still exist, the caller interprets that as biometry invalidation.
    public func read(_ item: KeychainItem) throws -> Data? {
        var query = baseQuery(item)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        let (status, result) = client.copyMatching(query)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        case errSecUserCanceled: throw KeychainError.userCancelledAuth
        case errSecAuthFailed: throw KeychainError.authenticationFailed
        default: throw KeychainError.unhandled(status)
        }
    }

    public func delete(_ item: KeychainItem) {
        _ = client.delete(baseQuery(item))
    }

    /// Enrollment reset / reenroll-required purge (§6.3). `except` exists
    /// for the call-caregiver contact: the terminal error screen must still
    /// know who to call after a purge.
    public func purgeEverything(except keep: Set<KeychainItem> = []) {
        for item in KeychainItem.allCases where !keep.contains(item) {
            delete(item)
        }
    }

    private func baseQuery(_ item: KeychainItem) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: configuration.service,
            kSecAttrAccount: item.rawValue,
        ]
        if let group = configuration.accessGroup {
            query[kSecAttrAccessGroup] = group
        }
        return query
    }
}
