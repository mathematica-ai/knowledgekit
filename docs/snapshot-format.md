# Knowledge snapshot — export format & endpoint

This is the contract KnowledgeKit's `SnapshotKnowledgeSource` consumes: a single JSON document that is the **full corpus**, fetched once and cached on-device. It's how you replace a bundled seed with your real knowledge-base corpus without touching app code.

## The JSON shape

Any of these are accepted (the bare array is canonical):

```jsonc
// 1. canonical — a bare array of records
[
  {
    "id": "acme-fr-manufacturing-defect",      // stable, unique; KnowledgeKit de-dupes on it
    "text": "Acme France: 2-year legal guarantee of conformity…",
    "metadata": {                                // all optional, all string→string
      "brand": "Acme",
      "country": "FR",
      "issue": "manufacturing-defect",
      "source_url": "https://example.com/terms-2025.html",
      "last_updated": "2026-04-10"
    },
    "source": "knowledge-cms"                    // optional provenance label
  }
]
```

```jsonc
// 2. wrapped — equivalent, if your endpoint prefers an envelope
{ "records": [ … ] }      // or { "documents": [ … ] }
```

> If your backend emits a different shape, KnowledgeKit's tolerant extractor will still lift any object carrying a text-like field (`text` / `content` / `chunk` / `page_content` / …). But emitting the canonical shape above is strongly preferred — it's lossless and predictable.

Field rules:
- **`id`** — required, stable across exports (so re-syncs are idempotent). Use your backend's chunk/document id.
- **`text`** — required, the chunk content the retriever embeds.
- **`metadata`** — optional `string → string`. Put facets the agent queries on here (`brand`, `country`, `issue`, `source_url`). Non-string values are dropped.
- **`source`** — optional label for provenance/debugging.

## Mapping a knowledge backend → records

For each chunk/document in your knowledge backend (CMS, vector store, docs pipeline):

| Backend concept | → `KnowledgeRecord` |
|---|---|
| chunk id / document id | `id` |
| chunk content | `text` |
| facets (brand / category / geography / topic) | `metadata.brand` / `…country` / `…issue` |
| source document URL | `metadata.source_url` |

Include every corpus the on-device agent should ground on (e.g. brand/product policy **and** any statutory or reference text relevant to your domain) so on-device grounding matches your server flow.

## Suggested server endpoint

If your knowledge backend's credentials are server-only, produce the export server-side. Add a narrow, bearer-gated route on your backend:

```
GET /api/knowledge/export
Authorization: Bearer <API_TOKEN>
→ 200 { "records": [ … ], "version": "2026-06-20", "count": 412 }
```

Server-side it enumerates the knowledge base and serializes every chunk to the format above. Cache it (it changes rarely) and optionally support:
- `ETag` / `If-None-Match` → `304 Not Modified` so the device skips re-downloading an unchanged corpus.
- `?updated_since=YYYY-MM-DD` for incremental syncs.

Alternatively, publish a **static snapshot** (a versioned JSON in object storage / a CDN) and point the device at its URL — no endpoint needed, and it can be public if the corpus isn't sensitive.

## Device side

```swift
let store = try KnowledgeStore(name: "corpus")
try await store.sync(from: SnapshotKnowledgeSource(
    url: URL(string: "https://api.example.com/api/knowledge/export")!,
    bearerToken: apiToken
))
// thereafter, fully offline:
let records = try await store.records()
```

In a consuming app, abstract this behind a small provider type: seed from a bundled corpus on first run, and flipping to the live snapshot is a one-line `sync(from:)` call once the endpoint exists.
