# Knowledge snapshot — export format & endpoint

This is the contract KnowledgeKit's `SnapshotKnowledgeSource` consumes: a single JSON document that is the **full corpus**, fetched once and cached on-device. It's how you replace a bundled seed with the real Knowledge 314 corpus without touching app code.

## The JSON shape

Any of these are accepted (the bare array is canonical):

```jsonc
// 1. canonical — a bare array of records
[
  {
    "id": "maje-fr-manufacturing-defect",      // stable, unique; KnowledgeKit de-dupes on it
    "text": "Maje France: 2-year legal guarantee of conformity…",
    "metadata": {                                // all optional, all string→string
      "brand": "Maje",
      "country": "FR",
      "issue": "manufacturing-defect",
      "source_url": "https://fr.maje.com/…/terms-2025.html",
      "last_updated": "2026-04-10"
    },
    "source": "knowledge-314"                    // optional provenance label
  }
]
```

```jsonc
// 2. wrapped — equivalent, if your endpoint prefers an envelope
{ "records": [ … ] }      // or { "documents": [ … ] }
```

> If your backend emits a different shape, KnowledgeKit's tolerant extractor will still lift any object carrying a text-like field (`text` / `content` / `chunk` / `page_content` / …). But emitting the canonical shape above is strongly preferred — it's lossless and predictable.

Field rules:
- **`id`** — required, stable across exports (so re-syncs are idempotent). Use the Knowledge chunk/KUI id.
- **`text`** — required, the chunk content the retriever embeds.
- **`metadata`** — optional `string → string`. Put facets the agent queries on here (`brand`, `country`, `issue`, `source_url`). Non-string values are dropped.
- **`source`** — optional label for provenance/debugging.

## Mapping Knowledge 314 → records

For each chunk/KUI in the Knowledge 314 project (`save-your-wardrobe-ltd/complaints-manager`):

| Knowledge 314 | → `KnowledgeRecord` |
|---|---|
| chunk id / KUI id | `id` |
| chunk content | `text` |
| brand / category / geography / issue type | `metadata.brand` / `…country` / `…issue` |
| source document URL | `metadata.source_url` |

Include both brand-policy chunks **and** the statutory/legal text (EU 2019/771, French Civil Code, etc.) so on-device grounding matches the server flow.

## Suggested server endpoint

The privileged P1/Polymorph creds are `server-only`, so the export must be produced server-side. Add a narrow, bearer-gated route on the complaint-manager (mirrors the existing `/api/agent/complaints/triage` auth — the app already carries `SYW_COMPLAINT_API_KEY`):

```
GET /api/agent/knowledge/export
Authorization: Bearer <SYW_COMPLAINT_API_KEY>
→ 200 { "records": [ … ], "version": "2026-06-20", "count": 412 }
```

Server-side it enumerates Knowledge 314 (via the same MCP/P1 path the retriever uses) and serializes every chunk to the format above. Cache it (it changes rarely) and optionally support:
- `ETag` / `If-None-Match` → `304 Not Modified` so the device skips re-downloading an unchanged corpus.
- `?updated_since=YYYY-MM-DD` for incremental syncs.

Alternatively, publish a **static snapshot** (a versioned JSON in object storage / a CDN) and point the device at its URL — no endpoint needed, and it can be public if the corpus isn't sensitive.

## Device side

```swift
let store = try KnowledgeStore(name: "complaints")
try await store.sync(from: SnapshotKnowledgeSource(
    url: URL(string: "https://syw-complaint-manager.mathematica.ai/api/agent/knowledge/export")!,
    bearerToken: agentToken
))
// thereafter, fully offline:
let records = try await store.records()
```

In the SYW showcase app this is already abstracted behind `KnowledgeProvider`: it seeds from the bundled corpus today, and flipping to the snapshot is a one-line `syncSnapshot(url:bearerToken:)` call once this endpoint exists.
