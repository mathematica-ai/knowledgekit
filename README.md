# KnowledgeKit

> Fetch a knowledge corpus (brand policies, FAQs, statutory text) and cache it **on-device** for fully-offline retrieval.

A small, dependency-free Swift package that pulls knowledge records from a snapshot, a bearer-gated proxy, or a search endpoint, persists them locally, and hands them back for on-device RAG. Pairs with [FlowKit](https://github.com/mathematica-ai/flowkit)'s retriever, but depends on nothing.

> Built & tested on Swift 6.3 / Xcode 26. 10 tests, no external dependencies.

## Why

On-device LLM flows need their grounding corpus **on the device**. But the privileged Knowledge-backend credentials (P1 / Knowledge: `P1_API_URL`, `P1_API_KEY`, org/project slugs) are `server-only` and must never ship in an app binary. KnowledgeKit is built around that constraint: it never holds those creds — it fetches from a **published snapshot** or a **bearer-gated proxy** (narrow token), then caches locally.

## Install

```swift
.package(url: "https://github.com/mathematica-ai/knowledgekit.git", from: "0.1.0"),
// target dependency:
.product(name: "KnowledgeKit", package: "knowledgekit")
```

## Use

```swift
import KnowledgeKit

let store = try KnowledgeStore()                 // caches in Application Support

// Sync once (e.g. on launch / when stale), then it's available offline forever.
if await store.isEmpty {
    try await store.sync(from: SnapshotKnowledgeSource(
        url: URL(string: "https://your-host/knowledge/export.json")!,
        bearerToken: narrowAgentToken                 // optional
    ))
}

let records = try await store.records()          // [KnowledgeRecord]
```

### Sources

| Source | When to use |
|---|---|
| `SnapshotKnowledgeSource(url:bearerToken:)` | A published JSON export of the corpus — the recommended path for full coverage. Accepts `[KnowledgeRecord]`, `{ "records": [...] }`, or any shape the tolerant extractor reads. |
| `SearchKnowledgeSource(endpoint:queries:topK:)` | The backend only exposes search — harvest the corpus by querying with seed queries and de-duplicating chunks. |
| `BundledKnowledgeSource(data:)` | Ship a seed JSON in-app as the offline default before any sync. |

### Bridge to FlowKit's retriever

`KnowledgeRecord` maps 1:1 to FlowKit's `KnowledgeDocument`:

```swift
import FlowKit

let docs = try await store.records().map {
    KnowledgeDocument(id: $0.id, text: $0.text, metadata: $0.metadata)
}
let retriever = EmbeddingRetriever(documents: docs)   // on-device RAG
```

## Model

```swift
struct KnowledgeRecord: Codable, Sendable, Identifiable {
    let id: String
    var text: String
    var metadata: [String: String]
    var source: String?
}
```

`KnowledgeStore` is an `actor` (race-free cache), persisting records + sync metadata (`lastSyncedAt`, `count`) as JSON.

## Security note

KnowledgeKit deliberately has no notion of the privileged Knowledge backend. Keep `P1_API_KEY` / Knowledge credentials server-side; expose the corpus to the device as a static snapshot or behind a narrow, bearer-gated endpoint.

## License

[Apache License 2.0](LICENSE). KnowledgeKit is unofficial and not affiliated with Langflow / DataStax / Knowledge — see [NOTICE](NOTICE).
