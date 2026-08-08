import Foundation
import Testing
import AmparoCrypto

@Suite("EncString Codable")
struct EncStringCodableTests {
    // Parse-valid type 2; base64 chosen without `/` or `+` so the encoded
    // JSON string is byte-stable across Foundation JSON writers.
    private let wire = "2.QUJDREVGR0hJSktMTU5PUA==|c2VjcmV0LWJsb2I=|QUJDREVGR0hJSktMTU5PUA=="

    @Test func roundTripsThroughJSON() throws {
        let decoded = try JSONDecoder().decode([EncString].self, from: Data("[\"\(wire)\"]".utf8))
        #expect(decoded == [try EncString(parsing: wire)])
        let encoded = String(data: try JSONEncoder().encode(decoded), encoding: .utf8)
        #expect(encoded == "[\"\(wire)\"]")
    }

    @Test func malformedStringFailsDecoding() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode([EncString].self, from: Data(#"["nope"]"#.utf8))
        }
    }
}
