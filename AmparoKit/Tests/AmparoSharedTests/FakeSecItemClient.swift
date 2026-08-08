import Foundation
import Security
@testable import AmparoShared

/// In-memory SecItem backend: stores full add-attribute dictionaries so
/// tests can assert protection classes, and replays scripted statuses.
final class FakeSecItemClient: SecItemClient, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: [CFString: Any]] = [:]
    private var nextAddStatus: OSStatus?
    private var nextCopyStatus: OSStatus?
    private var copyCounts: [String: Int] = [:]

    func failNextAdd(with status: OSStatus) {
        lock.withLock { nextAddStatus = status }
    }

    func failNextCopy(with status: OSStatus) {
        lock.withLock { nextCopyStatus = status }
    }

    func add(_ attributes: [CFString: Any]) -> OSStatus {
        lock.withLock {
            if let status = nextAddStatus {
                nextAddStatus = nil
                return status
            }
            let account = attributes[kSecAttrAccount] as! String
            guard storage[account] == nil else { return errSecDuplicateItem }
            storage[account] = attributes
            return errSecSuccess
        }
    }

    func copyMatching(_ query: [CFString: Any]) -> (OSStatus, AnyObject?) {
        lock.withLock {
            if let status = nextCopyStatus {
                nextCopyStatus = nil
                return (status, nil)
            }
            let account = query[kSecAttrAccount] as! String
            copyCounts[account, default: 0] += 1
            guard let attributes = storage[account] else { return (errSecItemNotFound, nil) }
            return (errSecSuccess, attributes[kSecValueData] as AnyObject?)
        }
    }

    /// On a real device every read of a biometry item prompts Face ID —
    /// tests use this to pin the one-prompt-per-unlock rule (D19).
    func readCount(for item: KeychainItem) -> Int {
        lock.withLock { copyCounts[item.rawValue] ?? 0 }
    }

    func delete(_ query: [CFString: Any]) -> OSStatus {
        lock.withLock {
            let account = query[kSecAttrAccount] as! String
            guard storage.removeValue(forKey: account) != nil else { return errSecItemNotFound }
            return errSecSuccess
        }
    }

    func attributes(for item: KeychainItem) -> [CFString: Any]? {
        lock.withLock { storage[item.rawValue] }
    }

    var storedAccounts: Set<String> {
        lock.withLock { Set(storage.keys) }
    }
}
