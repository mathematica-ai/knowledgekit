import Foundation

/// Tolerant extraction of `KnowledgeRecord`s from an arbitrary JSON value.
///
/// Knowledge backends (and the MCP `knowledge_search` result) return varied
/// shapes — arrays of chunks, `{ result: { chunks: [...] } }`, JSON-in-string,
/// etc. Rather than pin one schema, we walk the tree and lift any object that
/// carries a non-empty text-like field into a record.
enum KnowledgeExtractor {
    private static let textKeys = ["text", "content", "chunk", "page_content", "body", "passage", "snippet"]
    private static let idKeys = ["id", "chunk_id", "document_id", "doc_id", "uuid", "_id", "key"]

    static func records(from any: Any) -> [KnowledgeRecord] {
        var out: [KnowledgeRecord] = []
        collect(any, into: &out)
        return out
    }

    private static func collect(_ any: Any, into out: inout [KnowledgeRecord]) {
        switch any {
        case let dict as [String: Any]:
            if let record = record(from: dict) {
                out.append(record)            // a chunk object — don't recurse into its own fields
            } else {
                for value in dict.values { collect(value, into: &out) }
            }
        case let array as [Any]:
            for value in array { collect(value, into: &out) }
        case let string as String:
            // JSON embedded in a string (common with MCP tool results).
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("{") || trimmed.hasPrefix("["),
                  let data = trimmed.data(using: .utf8),
                  let nested = try? JSONSerialization.jsonObject(with: data) else { return }
            collect(nested, into: &out)
        default:
            break
        }
    }

    private static func record(from dict: [String: Any]) -> KnowledgeRecord? {
        guard let key = textKeys.first(where: { (dict[$0] as? String)?.isEmpty == false }),
              let text = dict[key] as? String else { return nil }

        let id = idKeys.compactMap { dict[$0] as? String }.first(where: { !$0.isEmpty })
            ?? stableID(text)

        var metadata: [String: String] = [:]
        if let meta = dict["metadata"] as? [String: Any] {
            for (k, v) in meta { if let s = stringify(v) { metadata[k] = s } }
        }
        // Lift a few common top-level facets into metadata if present.
        for facet in ["brand", "country", "jurisdiction", "issue", "issue_type", "lang", "source_url"] {
            if metadata[facet] == nil, let s = dict[facet].flatMap(stringify) { metadata[facet] = s }
        }
        return KnowledgeRecord(id: id, text: text, metadata: metadata, source: "search")
    }

    private static func stringify(_ value: Any?) -> String? {
        switch value {
        case let s as String: return s.isEmpty ? nil : s
        case let n as NSNumber: return n.stringValue
        case let b as Bool: return String(b)
        default: return nil
        }
    }

    /// Deterministic content id (FNV-1a 64-bit) so the same chunk de-dupes across
    /// runs even when the backend omits an id.
    static func stableID(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return "k_" + String(hash, radix: 16)
    }
}
