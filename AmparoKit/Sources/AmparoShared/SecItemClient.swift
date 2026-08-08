import Foundation
import Security

/// Seam over the four SecItem calls so KeychainStore's query construction is
/// unit-testable without a real keychain (same pattern as AmparoAPI's
/// HTTPTransport).
protocol SecItemClient: Sendable {
    func add(_ attributes: [CFString: Any]) -> OSStatus
    func copyMatching(_ query: [CFString: Any]) -> (OSStatus, AnyObject?)
    func delete(_ query: [CFString: Any]) -> OSStatus
}

struct SystemSecItemClient: SecItemClient {
    func add(_ attributes: [CFString: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func copyMatching(_ query: [CFString: Any]) -> (OSStatus, AnyObject?) {
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result)
    }

    func delete(_ query: [CFString: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}
