import Foundation

/// Shared error type for all network services.
enum NetworkError: Error, Equatable, Sendable {
    case networkError(String)
    case decodingError(String)
    case serverError(statusCode: Int)
    case notFound
    case rateLimited
    case invalidURL(String)

    static func == (lhs: NetworkError, rhs: NetworkError) -> Bool {
        switch (lhs, rhs) {
        case (.networkError(let a), .networkError(let b)): return a == b
        case (.decodingError(let a), .decodingError(let b)): return a == b
        case (.serverError(let a), .serverError(let b)): return a == b
        case (.notFound, .notFound): return true
        case (.rateLimited, .rateLimited): return true
        case (.invalidURL(let a), .invalidURL(let b)): return a == b
        default: return false
        }
    }
}
