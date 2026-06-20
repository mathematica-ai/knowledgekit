import Foundation

/// One unit of knowledge persisted on-device — a policy clause, FAQ answer, or
/// statutory excerpt. Structurally compatible with a retriever document, so it
/// bridges to LangflowKit's `KnowledgeDocument` in one line:
///
/// ```swift
/// KnowledgeDocument(id: record.id, text: record.text, metadata: record.metadata)
/// ```
public struct KnowledgeRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var text: String
    public var metadata: [String: String]
    /// Where this record came from (e.g. "snapshot", "search", "bundled").
    public var source: String?

    public init(id: String, text: String, metadata: [String: String] = [:], source: String? = nil) {
        self.id = id
        self.text = text
        self.metadata = metadata
        self.source = source
    }
}
