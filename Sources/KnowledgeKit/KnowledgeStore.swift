import Foundation

/// On-device persistence for the knowledge corpus. Fetches from a
/// ``KnowledgeSource``, caches the records to disk (JSON in Application Support
/// by default), and serves them back for retrieval — so the corpus is available
/// fully offline after the first sync.
///
/// An `actor` so concurrent reads/writes of the cache are race-free.
public actor KnowledgeStore {
    public struct SyncMetadata: Codable, Sendable {
        public var lastSyncedAt: Date
        public var count: Int
        public var sourceLabel: String?
    }

    private let recordsURL: URL
    private let metadataURL: URL

    /// - Parameters:
    ///   - name: cache file base name (allows multiple independent stores).
    ///   - directory: where to persist; defaults to Application Support/KnowledgeKit.
    public init(name: String = "knowledge", directory: URL? = nil) throws {
        let dir = try directory ?? Self.defaultDirectory()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw KnowledgeError.io("create directory \(dir.path): \(error.localizedDescription)")
        }
        self.recordsURL = dir.appendingPathComponent("\(name).json")
        self.metadataURL = dir.appendingPathComponent("\(name).meta.json")
    }

    /// Records currently cached on-device (empty before the first sync).
    public func records() throws -> [KnowledgeRecord] {
        guard FileManager.default.fileExists(atPath: recordsURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: recordsURL)
            return try JSONDecoder().decode([KnowledgeRecord].self, from: data)
        } catch {
            throw KnowledgeError.io("read cache: \(error.localizedDescription)")
        }
    }

    /// Overwrite the cache with `records`.
    public func save(_ records: [KnowledgeRecord], sourceLabel: String? = nil) throws {
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: recordsURL, options: .atomic)
            let metadata = SyncMetadata(lastSyncedAt: Date(), count: records.count, sourceLabel: sourceLabel)
            if let metaData = try? JSONEncoder().encode(metadata) {
                try? metaData.write(to: metadataURL, options: .atomic)
            }
        } catch {
            throw KnowledgeError.io("write cache: \(error.localizedDescription)")
        }
    }

    /// Fetch from `source` and persist the result on-device. Returns the records.
    @discardableResult
    public func sync(from source: KnowledgeSource, label: String? = nil) async throws -> [KnowledgeRecord] {
        let fetched = try await source.fetch()
        try save(fetched, sourceLabel: label ?? "\(type(of: source))")
        return fetched
    }

    public func metadata() -> SyncMetadata? {
        guard let data = try? Data(contentsOf: metadataURL) else { return nil }
        return try? JSONDecoder().decode(SyncMetadata.self, from: data)
    }

    public var isEmpty: Bool {
        !FileManager.default.fileExists(atPath: recordsURL.path)
    }

    public func clear() throws {
        try? FileManager.default.removeItem(at: recordsURL)
        try? FileManager.default.removeItem(at: metadataURL)
    }

    static func defaultDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return base.appendingPathComponent("KnowledgeKit", isDirectory: true)
    }
}
