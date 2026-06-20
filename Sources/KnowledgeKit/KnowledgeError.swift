import Foundation

public enum KnowledgeError: Error, CustomStringConvertible {
    case http(status: Int, body: String)
    case decoding(String)
    case io(String)
    case notConfigured(String)

    public var description: String {
        switch self {
        case .http(let status, let body):
            return "Knowledge HTTP \(status): \(body.prefix(200))"
        case .decoding(let why):
            return "Knowledge decode failed: \(why)"
        case .io(let why):
            return "Knowledge store I/O failed: \(why)"
        case .notConfigured(let why):
            return "Knowledge not configured: \(why)"
        }
    }
}
