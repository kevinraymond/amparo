import Foundation
import Security
import Testing
@testable import AmparoShared

@Suite("KeychainStore")
struct KeychainStoreTests {
    private let fake = FakeSecItemClient()

    private func makeStore(accessGroup: String? = "group-test") -> KeychainStore {
        KeychainStore(
            configuration: .init(service: "test.amparo", accessGroup: accessGroup),
            client: fake
        )
    }

    @Test func roundTripsAndOverwrites() throws {
        let store = makeStore()
        try store.store(Data("first".utf8), for: .refreshToken)
        #expect(try store.read(.refreshToken) == Data("first".utf8))
        try store.store(Data("second".utf8), for: .refreshToken)
        #expect(try store.read(.refreshToken) == Data("second".utf8))
    }

    @Test func biometryItemsCarryAccessControlNotAccessible() throws {
        let store = makeStore()
        try store.store(Data(count: 64), for: .vaultKeys)
        let attributes = try #require(fake.attributes(for: .vaultKeys))
        #expect(attributes[kSecAttrAccessControl] != nil)
        #expect(attributes[kSecAttrAccessible] == nil)
        #expect(attributes[kSecAttrService] as? String == "test.amparo")
        #expect(attributes[kSecAttrAccessGroup] as? String == "group-test")
    }

    @Test func passcodeItemsAreDeviceOnlyWithoutBiometry() throws {
        let store = makeStore()
        try store.store(Data("rt".utf8), for: .refreshToken)
        let attributes = try #require(fake.attributes(for: .refreshToken))
        #expect(attributes[kSecAttrAccessControl] == nil)
        let accessible = attributes[kSecAttrAccessible] as! CFString
        #expect(accessible == kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly)
    }

    @Test func accessGroupIsOmittedWhenNotConfigured() throws {
        let store = makeStore(accessGroup: nil)
        try store.store(Data("e".utf8), for: .email)
        let attributes = try #require(fake.attributes(for: .email))
        #expect(attributes[kSecAttrAccessGroup] == nil)
    }

    @Test func missingItemReadsAsNil() throws {
        #expect(try makeStore().read(.vaultKeys) == nil)
    }

    @Test func deleteThenReadIsNil() throws {
        let store = makeStore()
        try store.store(Data("x".utf8), for: .email)
        store.delete(.email)
        #expect(try store.read(.email) == nil)
    }

    @Test func purgeEverythingClearsAllSlots() throws {
        let store = makeStore()
        try store.store(Data(count: 64), for: .vaultKeys)
        try store.store(Data("rt".utf8), for: .refreshToken)
        try store.store(Data("e".utf8), for: .email)
        store.purgeEverything()
        #expect(fake.storedAccounts.isEmpty)
    }

    @Test func authStatusesMapToTypedErrors() throws {
        let store = makeStore()
        fake.failNextCopy(with: errSecUserCanceled)
        #expect(throws: KeychainError.userCancelledAuth) { try store.read(.vaultKeys) }
        fake.failNextCopy(with: errSecAuthFailed)
        #expect(throws: KeychainError.authenticationFailed) { try store.read(.vaultKeys) }
        fake.failNextCopy(with: errSecInteractionNotAllowed)
        #expect(throws: KeychainError.unhandled(errSecInteractionNotAllowed)) { try store.read(.vaultKeys) }
    }

    @Test func storeFailureSurfacesStatus() throws {
        let store = makeStore()
        fake.failNextAdd(with: errSecNotAvailable)
        #expect(throws: KeychainError.unhandled(errSecNotAvailable)) {
            try store.store(Data("x".utf8), for: .email)
        }
    }
}
