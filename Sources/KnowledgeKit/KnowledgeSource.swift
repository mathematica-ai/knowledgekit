import Foundation

/// A place KnowledgeKit can fetch records from. Implementations never hold
/// privileged Knowledge-backend credentials — they talk to a published snapshot,
/// a bearer-gated proxy, or a bundled file. (The privileged P1/Polymorph creds
/// stay server-side, per the backend's `server-only` contract.)
public protocol KnowledgeSource: Sendable {
    func fetch() async throws -> [KnowledgeRecord]
}

// MARK: - Snapshot (recommended for full corpus)

/// Fetches a single JSON export of the corpus from a URL (e.g. a static snapshot
/// the server publishes, or a bearer-gated export endpoint). Accepts a bare
/// `[KnowledgeRecord]`, a `{ "records": [...] }` / `{ "documents": [...] }`
/// wrapper, or any shape the tolerant extractor can read.
public struct SnapshotKnowledgeSource: KnowledgeSource {
    public let url: URL
    public let bearerToken: String?
    public let session: URLSession

    public init(url: URL, bearerToken: String? = nil, session: URLSession = .shared) {
        self.url = url
        self.bearerToken = bearerToken
        self.session = session
    }

    public func fetch() async throws -> [KnowledgeRecord] {
        var request = URLRequest(url: url)
        if let bearerToken { request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        try HTTP.check(response, data)
        return try Self.decodeRecords(data)
    }

    /// Decode records from snapshot/bundle data, tolerating common envelopes.
    public static func decodeRecords(_ data: Data) throws -> [KnowledgeRecord] {
        let decoder = JSONDecoder()
        if let array = try? decoder.decode([KnowledgeRecord].self, from: data) { return array }

        struct Wrapper: Decodable { let records: [KnowledgeRecord]?; let documents: [KnowledgeRecord]? }
        if let wrapper = try? decoder.decode(Wrapper.self, from: data),
           let records = wrapper.records ?? wrapper.documents { return records }

        if let object = try? JSONSerialization.jsonObject(with: data) {
            let extracted = KnowledgeExtractor.records(from: object)
            if !extracted.isEmpty { return extracted }
        }
        throw KnowledgeError.decoding("unrecognized snapshot shape")
    }
}

// MARK: - Search harvest (works with the existing search endpoint)

/// Builds the corpus by querying a search endpoint (`GET <endpoint>?q=&top_k=`)
/// with a battery of seed queries and de-duplicating the returned chunks. Useful
/// when the backend exposes only search (no bulk export). Coverage depends on the
/// seed queries — log/inspect what comes back.
public struct SearchKnowledgeSource: KnowledgeSource {
    public let endpoint: URL
    public let queries: [String]
    public let topK: Int
    public let bearerToken: String?
    public let session: URLSession

    public init(endpoint: URL, queries: [String], topK: Int = 8,
                bearerToken: String? = nil, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.queries = queries
        self.topK = topK
        self.bearerToken = bearerToken
        self.session = session
    }

    public func fetch() async throws -> [KnowledgeRecord] {
        var seen = Set<String>()
        var results: [KnowledgeRecord] = []
        for query in queries {
            guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { continue }
            components.queryItems = (components.queryItems ?? []) + [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "top_k", value: String(topK)),
            ]
            guard let url = components.url else { continue }
            var request = URLRequest(url: url)
            if let bearerToken { request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization") }
            let (data, response) = try await session.data(for: request)
            try HTTP.check(response, data)
            guard let object = try? JSONSerialization.jsonObject(with: data) else { continue }
            for record in KnowledgeExtractor.records(from: object) where seen.insert(record.id).inserted {
                results.append(record)
            }
        }
        return results
    }
}

// MARK: - Bundled (offline default / seed)

/// Loads records from in-app JSON data — the offline default before any sync.
public struct BundledKnowledgeSource: KnowledgeSource {
    public let data: Data
    public init(data: Data) { self.data = data }
    public func fetch() async throws -> [KnowledgeRecord] {
        try SnapshotKnowledgeSource.decodeRecords(data)
    }
}

// MARK: - HTTP helper

enum HTTP {
    static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw KnowledgeError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
    }
}
