import Foundation

extension JSONDecoder {
    /// Server JSON casing varies (captured samples, D13): sync bodies are
    /// camelCase, token bodies mix snake_case OAuth fields with PascalCase
    /// Bitwarden fields (`Key`, `PrivateKey`, `Kdf`). Lowercasing the first
    /// letter normalizes PascalCase to camelCase — the Swift transposition of
    /// the fixtures' tolerant `field()` accessor; snake_case fields carry
    /// explicit `CodingKeys` in their models.
    static func vaultwarden() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { path in
            let key = path.last!.stringValue
            guard let first = key.first, first.isUppercase else { return path.last! }
            return AnyCodingKey(stringValue: first.lowercased() + key.dropFirst())
        }
        return decoder
    }
}

struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

/// Decodes array elements individually and drops the ones that fail — one
/// exotic future cipher must not kill the whole sync (D13).
struct LossyArray<Element: Decodable>: Decodable {
    let elements: [Element]

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                // A failed decode does not advance the container; consuming
                // into an empty Decodable skips the element.
                _ = try? container.decode(Skip.self)
            }
        }
        self.elements = elements
    }

    private struct Skip: Decodable {
        init(from decoder: any Decoder) throws {}
    }
}
