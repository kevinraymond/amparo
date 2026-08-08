import Foundation
import Testing
@testable import AmparoAPI
@testable import AmparoShared

@Suite("CipherStore")
struct CipherStoreTests {
    private func makeStore() -> CipherStore {
        CipherStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("amparo-store-\(UUID().uuidString).json")
        )
    }

    @Test func roundTripsSnapshotLosslessly() throws {
        let store = makeStore()
        let cipher = try JSONDecoder().decode(Cipher.self, from: Data("""
        {"id": "c1", "organizationId": "o1", "type": 1,
         "name": "2.QUJDREVGR0hJSktMTU5PUA==|c2VjcmV0LWJsb2I=|QUJDREVGR0hJSktMTU5PUA==",
         "login": {"username": null, "password": null, "totp": null, "uris": []}}
        """.utf8))
        let snapshot = VaultSnapshot(
            syncedAt: Date(timeIntervalSince1970: 1_754_000_000),
            organizationKeyStrings: ["o1": "4.c2VjcmV0LWJsb2I="],
            ciphers: [cipher]
        )
        try store.save(snapshot)
        #expect(try store.load() == snapshot)
        store.wipe()
        #expect(try store.load() == nil)
    }

    @Test func missingFileIsNilNotAnError() throws {
        #expect(try makeStore().load() == nil)
    }

    @Test func corruptFileIsStoreCorrupted() throws {
        let store = makeStore()
        try Data("not a snapshot".utf8).write(to: store.fileURL)
        #expect(throws: VaultStoreError.storeCorrupted) {
            _ = try store.load()
        }
    }
}

@Suite("Cipher presentation")
struct CipherPresentationTests {
    @Test(arguments: [
        ("1. Banco", 1, "Banco"),
        ("12. Cartao", 12, "Cartao"),
        ("3.NoSpace", 3, "NoSpace"),
        ("9. Previdencia", 9, "Previdencia"),
        ("Portal Medico", Int.max, "Portal Medico"),
        ("2026 Taxes", Int.max, "2026 Taxes"),  // number without dot = no prefix
    ])
    func splitsOrderingPrefix(raw: String, index: Int, display: String) {
        let (sortIndex, displayName) = CipherPresentation.split(raw)
        #expect(sortIndex == index)
        #expect(displayName == display)
    }

    @Test(arguments: [
        ("https://banco.example.com/login", "banco.example.com"),
        ("banco.example.com", "banco.example.com"),
        ("", nil),
    ])
    func extractsDomains(uri: String, expected: String?) {
        #expect(CipherPresentation.domain(fromURI: uri) == expected)
    }
}

@Suite("PIN hashing")
struct PINHashTests {
    @Test func verifiesCorrectPINOnly() {
        let stored = PINHash.create("2468")
        #expect(PINHash.verify("2468", against: stored))
        #expect(!PINHash.verify("2469", against: stored))
        #expect(!PINHash.verify("", against: stored))
        #expect(!PINHash.verify("2468", against: Data("short".utf8)))
    }

    @Test func saltsMakeHashesUnique() {
        #expect(PINHash.create("2468") != PINHash.create("2468"))
    }
}

@Suite("IconCache")
struct IconCacheTests {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() { lock.withLock { value += 1 } }
        var count: Int { lock.withLock { value } }
    }

    private func makeCache() -> IconCache {
        IconCache(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("amparo-icons-\(UUID().uuidString)")
        )
    }

    @Test func fetchesOnceThenServesFromDisk() async {
        let cache = makeCache()
        let counter = Counter()
        let fetch: @Sendable (String) async throws -> Data? = { _ in
            counter.increment()
            return Data([1, 2, 3])
        }
        #expect(await cache.icon(for: "banco.example.com", fetch: fetch) == Data([1, 2, 3]))
        #expect(await cache.icon(for: "banco.example.com", fetch: fetch) == Data([1, 2, 3]))
        #expect(counter.count == 1)
    }

    @Test func cachesMissesAsNegative() async {
        let cache = makeCache()
        let counter = Counter()
        let fetch: @Sendable (String) async throws -> Data? = { _ in
            counter.increment()
            return nil
        }
        #expect(await cache.icon(for: "unknown.example.com", fetch: fetch) == nil)
        #expect(await cache.icon(for: "unknown.example.com", fetch: fetch) == nil)
        #expect(counter.count == 1)
    }

    @Test func transportFailureIsNotCached() async {
        let cache = makeCache()
        let counter = Counter()
        let failing: @Sendable (String) async throws -> Data? = { _ in
            counter.increment()
            throw URLError(.notConnectedToInternet)
        }
        #expect(await cache.icon(for: "x.example.com", fetch: failing) == nil)
        #expect(await cache.icon(for: "x.example.com", fetch: failing) == nil)
        #expect(counter.count == 2)  // no negative entry for offline
    }

    @Test func sanitizesDomainsIntoFileNames() {
        #expect(IconCache.fileName(for: "Banco.Example.com") == "banco.example.com.icon")
        #expect(IconCache.fileName(for: "weird/../host") == "weird_.._host.icon")
    }
}
