import Foundation

/// An EncString travels through JSON payloads (token/sync responses, and
/// later the §7.3 stored-as-received cipher cache) in its serialized string
/// form.
extension EncString: Codable {
    public init(from decoder: any Decoder) throws {
        try self.init(parsing: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(serialized())
    }
}
