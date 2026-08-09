import Foundation
import Testing
@testable import AmparoAPI
@testable import AmparoShared

@Suite("VaultStore")
struct VaultStoreTests {
    // MARK: Enrollment

    /// Full offline enrollment against captured live bodies with the real
    /// fixture master password — real PBKDF2/HKDF/AES/RSA all the way down,
    /// cross-checked against the M1 E2E vectors.
    @Test func enrollmentDerivesRealKeysAndPersistsEverything() async throws {
        let test = TestVault(script: try TestVault.happyEnrollmentScript())
        try await test.vault.enroll(TestVault.enrollmentRequest())

        let vectors = try SharedSamples.vectors()
        let account = vectors["account"] as! [String: Any]
        let organization = vectors["organization"] as! [String: Any]

        let blob = try #require(try test.keychain.read(.vaultKeys))
        let material = try JSONDecoder().decode(VaultKeyMaterial.self, from: blob)
        #expect(material.userKey.count == 64)
        #expect(material.userKey.map { String(format: "%02x", $0) }.joined() == account["userKeyHex"] as? String)
        #expect(!material.privateKeyDer.isEmpty)
        let orgId = organization["id"] as! String
        let orgKey = try #require(material.organizationKeys[orgId])
        #expect(orgKey.map { String(format: "%02x", $0) }.joined() == organization["orgKeyHex"] as? String)

        for item: KeychainItem in [.refreshToken, .serverURL, .email,
                                   .deviceIdentifier, .caregiverProfile, .caregiverPIN, .consentRecord] {
            #expect(try test.keychain.read(item) != nil, "missing \(item)")
        }
        #expect(await test.vault.isEnrolled())
        let snapshot = try #require(try test.cipherStore.load())
        #expect(snapshot.ciphers.count == 11)
        #expect(snapshot.organizationKeyStrings[orgId] != nil)
    }

    @Test func failedEnrollmentLeavesNoPartialState() async throws {
        let prelogin = try SharedSamples.load("prelogin")
        let wrong = try SharedSamples.load("token-wrong-password")
        let test = TestVault(script: [
            .response(status: prelogin.status, body: prelogin.body),
            .response(status: wrong.status, body: wrong.body),
        ])

        await #expect(throws: AmparoError.invalidCredentials) {
            try await test.vault.enroll(TestVault.enrollmentRequest())
        }
        #expect(test.fakeSecItems.storedAccounts.isEmpty)
        #expect(await !test.vault.isEnrolled())
        #expect(try test.cipherStore.load() == nil)
    }

    // MARK: Member reads

    @Test func tilesAreStrippedSortedAndSecretFree() async throws {
        let test = TestVault(script: try TestVault.happyEnrollmentScript())
        try await test.vault.enroll(TestVault.enrollmentRequest())

        let tiles = try await test.vault.tiles()
        #expect(tiles.count == 11)
        // D4 prefix convention: "1. Bank" → "Bank", ordered by index;
        // the unprefixed personal cipher sorts last.
        #expect(tiles.first?.displayName == "Bank")
        #expect(tiles.map(\.displayName).contains("1. Bank") == false)
        #expect(tiles.last?.displayName == "Medical Portal")
        #expect(tiles.last?.sortIndex == Int.max)
        #expect(tiles.allSatisfy { $0.username?.isEmpty == false })
        #expect(tiles.allSatisfy { $0.domain?.isEmpty == false })
    }

    @Test func secretsDecryptOnDemandIncludingTOTP() async throws {
        let test = TestVault(script: try TestVault.happyEnrollmentScript())
        try await test.vault.enroll(TestVault.enrollmentRequest())
        let tiles = try await test.vault.tiles()

        let retirement = try #require(tiles.first { $0.displayName == "Retirement" })
        let secrets = try #require(try await test.vault.secrets(forCipher: retirement.id))
        #expect(secrets.password?.isEmpty == false)
        let totp = try #require(secrets.totp)
        #expect(totp.code(at: Date(timeIntervalSince1970: 59)) == "996554")  // fixture secret

        let bank = try #require(tiles.first { $0.displayName == "Bank" })
        let bankSecrets = try #require(try await test.vault.secrets(forCipher: bank.id))
        #expect(bankSecrets.totp == nil)
        #expect(bankSecrets.password?.isEmpty == false)
    }

    @Test func biometryInvalidationIsDetectedAfterLock() async throws {
        let test = TestVault(script: try TestVault.happyEnrollmentScript())
        try await test.vault.enroll(TestVault.enrollmentRequest())
        _ = try await test.vault.tiles()

        // Simulate Face ID re-enrollment: the biometry-tier item vanishes
        // while the passcode-tier enrollment markers survive.
        await test.vault.lock()
        test.keychain.delete(.vaultKeys)

        await #expect(throws: VaultStoreError.biometryInvalidated) {
            _ = try await test.vault.tiles()
        }
    }

    @Test func unenrolledVaultRefusesMemberReads() async throws {
        let test = TestVault(script: [])
        await #expect(throws: VaultStoreError.notEnrolled) {
            _ = try await test.vault.tiles()
        }
    }

    // MARK: Sync lifecycle

    @Test func freshProcessRestoresClientAndSyncs() async throws {
        let test = TestVault(script: try TestVault.happyEnrollmentScript())
        try await test.vault.enroll(TestVault.enrollmentRequest())

        // New VaultStore over the same keychain/store = process restart.
        let token = try SharedSamples.load("token-success")
        let sync = try SharedSamples.load("sync-success")
        let restartTransport = StubTransport([
            .response(status: token.status, body: token.body),
            .response(status: sync.status, body: sync.body),
        ])
        let restarted = VaultStore(
            keychain: test.keychain, cipherStore: test.cipherStore, transport: restartTransport
        )
        let snapshot = try await restarted.syncNow()
        #expect(snapshot.ciphers.count == 11)
        // No access token survives a restart: refresh first, then sync.
        let urls = await restartTransport.requestURLs
        #expect(urls == [
            "https://vw.test:8443/identity/connect/token",
            "https://vw.test:8443/api/sync?excludeDomains=true",
        ])
    }

    @Test func reenrollRequiredPurgesSecretsButKeepsCaregiverContact() async throws {
        let test = TestVault(script: try TestVault.happyEnrollmentScript())
        try await test.vault.enroll(TestVault.enrollmentRequest())

        let invalid = try SharedSamples.load("token-refresh-invalid")
        let restarted = VaultStore(
            keychain: test.keychain,
            cipherStore: test.cipherStore,
            transport: StubTransport([.response(status: invalid.status, body: invalid.body)])
        )
        await #expect(throws: AmparoError.reenrollRequired) {
            try await restarted.syncNow()
        }
        // Everything secret is gone; the call-caregiver screen still works
        // AND its hidden caregiver door still accepts the PIN (D19).
        #expect(test.fakeSecItems.storedAccounts == [
            KeychainItem.caregiverProfile.rawValue,
            KeychainItem.consentRecord.rawValue,
            KeychainItem.caregiverPIN.rawValue,
        ])
        #expect(try test.cipherStore.load() == nil)
        #expect(await !restarted.isEnrolled())
        #expect(await restarted.caregiverProfile() != nil)
        #expect(await restarted.verifyCaregiverPIN("2468"))
    }

    /// D19 regression: on device, every biometry-item read prompts Face ID —
    /// a whole unlocked session (list + two detail reads) must hit the
    /// biometry tier exactly once.
    @Test func unlockedSessionReadsBiometryTierExactlyOnce() async throws {
        let test = TestVault(script: try TestVault.happyEnrollmentScript())
        try await test.vault.enroll(TestVault.enrollmentRequest())

        let tiles = try await test.vault.tiles()
        _ = try await test.vault.secrets(forCipher: tiles[0].id)
        _ = try await test.vault.secrets(forCipher: tiles[1].id)

        #expect(test.fakeSecItems.readCount(for: .vaultKeys) == 1)
    }

    @Test func transientSyncFailureKeepsLocalState() async throws {
        let test = TestVault(script: try TestVault.happyEnrollmentScript())
        try await test.vault.enroll(TestVault.enrollmentRequest())

        let restarted = VaultStore(
            keychain: test.keychain,
            cipherStore: test.cipherStore,
            transport: StubTransport([.failure(URLError(.notConnectedToInternet))])
        )
        await #expect(throws: AmparoError.offline(.notConnectedToInternet)) {
            try await restarted.syncNow()
        }
        // Snapshot and enrollment survive — the member keeps working.
        #expect(try test.cipherStore.load()?.ciphers.count == 11)
        #expect(await restarted.isEnrolled())
    }

    // MARK: Caregiver state

    @Test func caregiverProfilePINAndConsentRoundTrip() async throws {
        let test = TestVault(script: try TestVault.happyEnrollmentScript())
        try await test.vault.enroll(TestVault.enrollmentRequest(pin: "1359"))

        #expect(await test.vault.caregiverProfile() ==
            CaregiverProfile(name: "Dev Caregiver", phone: "+15551234567"))
        #expect(await test.vault.consentRecord()?.caregiverName == "Dev Caregiver")
        #expect(await test.vault.verifyCaregiverPIN("1359"))
        #expect(await !test.vault.verifyCaregiverPIN("0000"))
    }
}
