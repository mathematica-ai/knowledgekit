import XCTest
@testable import KnowledgeKit

// MARK: - URLProtocol stub (deterministic, no real network)

final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

private func stubSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: config)
}

private func ok(_ url: URL, _ json: String) -> (HTTPURLResponse, Data) {
    (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
}

// MARK: - Store

final class KnowledgeStoreTests: XCTestCase {
    private func tempStore() throws -> KnowledgeStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return try KnowledgeStore(name: "test", directory: dir)
    }

    func testSaveAndLoadRoundTrip() async throws {
        let store = try tempStore()
        let isEmpty = await store.isEmpty
        XCTAssertTrue(isEmpty)
        let records = [
            KnowledgeRecord(id: "a", text: "alpha", metadata: ["brand": "Acme"]),
            KnowledgeRecord(id: "b", text: "beta"),
        ]
        try await store.save(records, sourceLabel: "unit")
        let loaded = try await store.records()
        XCTAssertEqual(loaded, records)
        let meta = await store.metadata()
        XCTAssertEqual(meta?.count, 2)
        XCTAssertEqual(meta?.sourceLabel, "unit")
    }

    func testClear() async throws {
        let store = try tempStore()
        try await store.save([KnowledgeRecord(id: "a", text: "alpha")])
        try await store.clear()
        let loaded = try await store.records()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testSyncFromBundledSource() async throws {
        let store = try tempStore()
        let json = #"[{"id":"x","text":"hello","metadata":{}}]"#
        let count = try await store.sync(from: BundledKnowledgeSource(data: Data(json.utf8)), label: "bundled")
        XCTAssertEqual(count.count, 1)
        let loaded = try await store.records()
        XCTAssertEqual(loaded.first?.text, "hello")
    }
}

// MARK: - Decoding / extraction

final class KnowledgeDecodeTests: XCTestCase {
    func testDecodesBareArray() throws {
        let json = #"[{"id":"a","text":"alpha","metadata":{"brand":"Acme"}}]"#
        let records = try SnapshotKnowledgeSource.decodeRecords(Data(json.utf8))
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.metadata["brand"], "Acme")
    }

    func testDecodesRecordsWrapper() throws {
        let json = #"{"records":[{"id":"a","text":"alpha"},{"id":"b","text":"beta"}]}"#
        let records = try SnapshotKnowledgeSource.decodeRecords(Data(json.utf8))
        XCTAssertEqual(records.count, 2)
    }

    func testExtractsFromSearchShape() throws {
        // MCP-style: { result: { chunks: [ { chunk_id, content, metadata } ] } }
        let json = #"{"query":"q","result":{"chunks":[{"chunk_id":"c1","content":"Acme 2-year guarantee","metadata":{"country":"FR"}}]}}"#
        let records = try SnapshotKnowledgeSource.decodeRecords(Data(json.utf8))
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.id, "c1")
        XCTAssertEqual(records.first?.metadata["country"], "FR")
    }

    func testStableIDIsDeterministic() {
        XCTAssertEqual(KnowledgeExtractor.stableID("same text"), KnowledgeExtractor.stableID("same text"))
        XCTAssertNotEqual(KnowledgeExtractor.stableID("a"), KnowledgeExtractor.stableID("b"))
    }
}

// MARK: - Network sources (stubbed)

final class KnowledgeNetworkTests: XCTestCase {
    func testSnapshotSourceFetches() async throws {
        let url = URL(string: "https://example.com/knowledge.json")!
        StubURLProtocol.handler = { req in
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
            return ok(req.url!, #"{"records":[{"id":"a","text":"alpha"}]}"#)
        }
        let source = SnapshotKnowledgeSource(url: url, bearerToken: "tok", session: stubSession())
        let records = try await source.fetch()
        XCTAssertEqual(records.map(\.id), ["a"])
    }

    func testSearchSourceHarvestsAndDeduplicates() async throws {
        let endpoint = URL(string: "https://example.com/api/knowledge/search")!
        StubURLProtocol.handler = { req in
            let q = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "q" })?.value ?? ""
            // q1 → a,b ; q2 → b,c  (b overlaps → must de-dupe)
            let chunks = q.contains("defect")
                ? #"[{"id":"a","text":"alpha"},{"id":"b","text":"beta"}]"#
                : #"[{"id":"b","text":"beta"},{"id":"c","text":"gamma"}]"#
            return ok(req.url!, "{\"result\":{\"chunks\":\(chunks)}}")
        }
        let source = SearchKnowledgeSource(
            endpoint: endpoint,
            queries: ["Acme defect FR", "Acme return FR"],
            topK: 5,
            session: stubSession()
        )
        let records = try await source.fetch()
        XCTAssertEqual(Set(records.map(\.id)), ["a", "b", "c"])
    }

    func testHTTPErrorSurfaces() async {
        let url = URL(string: "https://example.com/knowledge.json")!
        StubURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
             Data(#"{"error":"unauthorized"}"#.utf8))
        }
        let source = SnapshotKnowledgeSource(url: url, session: stubSession())
        do {
            _ = try await source.fetch()
            XCTFail("expected HTTP error")
        } catch let error as KnowledgeError {
            guard case .http(let status, _) = error else { return XCTFail("wrong error: \(error)") }
            XCTAssertEqual(status, 401)
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }
}
