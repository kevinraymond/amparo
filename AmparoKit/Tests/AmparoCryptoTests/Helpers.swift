import Foundation

extension Data {
    /// Test-only hex decoding; traps on malformed input (vectors are static).
    init(hex: String) {
        self.init()
        var iterator = hex.makeIterator()
        while let high = iterator.next(), let low = iterator.next() {
            append(UInt8(String([high, low]), radix: 16)!)
        }
    }

    var hex: String { map { String(format: "%02x", $0) }.joined() }
}

/// Mirrors fixtures/gen-vectors.mjs output — behavioral capture from the dev
/// Vaultwarden + official bw CLI (see fixtures/README.md).
struct Vectors: Decodable {
    struct Account: Decodable {
        let email: String
        let password: String
        let kdf: Int
        let kdfIterations: Int
        let masterKeyHex: String
        let masterPasswordHashB64: String
        let stretchedEncKeyHex: String
        let stretchedMacKeyHex: String
        let protectedUserKey: String
        let userKeyHex: String
        let encryptedPrivateKey: String
        let privateKeyPkcs8B64: String
    }

    struct Organization: Decodable {
        let id: String
        let encKey: String
        let orgKeyHex: String
    }

    struct Field: Decodable {
        let enc: String
        let expected: String
    }

    struct Cipher: Decodable {
        let id: String
        let organizationId: String?
        let name: Field
        let username: Field
        let password: Field
        let uri: Field
        let totp: Field?
    }

    let account: Account
    let organization: Organization
    let ciphers: [Cipher]

    static func load() throws -> Vectors {
        let url = Bundle.module.url(
            forResource: "e2e-vectors", withExtension: "json", subdirectory: "Resources"
        )!
        return try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
    }
}
