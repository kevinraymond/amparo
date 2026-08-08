import Foundation

/// Disk-forever icon cache (§6.5: "cache aggressively"). A zero-byte file
/// is a cached miss — the server said 404 once, don't ask again. Transport
/// failures cache nothing so the next foreground retries. nil → the UI
/// falls back to a monogram tile.
public actor IconCache {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func icon(
        for domain: String,
        fetch: @Sendable (String) async throws -> Data?
    ) async -> Data? {
        let file = directory.appendingPathComponent(Self.fileName(for: domain))
        if let cached = try? Data(contentsOf: file) {
            return cached.isEmpty ? nil : cached
        }
        let fetched: Data?
        do {
            fetched = try await fetch(domain)
        } catch {
            return nil  // transport failure: cache nothing, retry next time
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? (fetched ?? Data()).write(to: file, options: [.atomic])
        return fetched
    }

    static func fileName(for domain: String) -> String {
        let sanitized = domain.lowercased().map { character in
            character.isLetter || character.isNumber || character == "." || character == "-"
                ? character : "_"
        }
        return String(sanitized) + ".icon"
    }
}
