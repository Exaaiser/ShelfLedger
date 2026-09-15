import Foundation

protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> Data
}

enum NetworkError: LocalizedError {
    case status(Int), rateLimited, invalidResponse, invalidURL
    var errorDescription: String? {
        switch self {
        case .status(let code): return "The service is unavailable (\(code)). Try again later."
        case .rateLimited: return "The service's request limit was reached. Please try again later."
        case .invalidResponse: return "The service returned an unexpected response."
        case .invalidURL: return "The request could not be created."
        }
    }
}

actor URLSessionHTTPClient: HTTPClient {
    private let session: URLSession
    private var blockedUntil: [String: Date] = [:]
    init(session: URLSession = .shared) { self.session = session }

    func data(for input: URLRequest) async throws -> Data {
        var request = input
        let host = request.url?.host ?? ""
        if let until = blockedUntil[host], until > Date() { throw NetworkError.rateLimited }
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ShelfLedger/1.0 (iOS; personal development)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw NetworkError.invalidResponse }
        if response.statusCode == 429 {
            let delay = Double(response.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60
            blockedUntil[host] = Date().addingTimeInterval(max(6, delay))
            throw NetworkError.rateLimited
        }
        guard (200..<300).contains(response.statusCode) else { throw NetworkError.status(response.statusCode) }
        return data
    }
}

func makeRequest(_ base: String, query: [URLQueryItem] = []) throws -> URLRequest {
    guard var components = URLComponents(string: base) else { throw NetworkError.invalidURL }
    components.queryItems = query.isEmpty ? nil : query
    guard let url = components.url, url.scheme == "https" else { throw NetworkError.invalidURL }
    return URLRequest(url: url)
}

extension String {
    var nonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
    var secureURL: URL? {
        guard let url = URL(string: self), url.scheme == "https" else { return nil }
        return url
    }
}

struct FetchResult<Value: Sendable>: Sendable {
    let value: Value?
    let failure: String?
}

func fetchResult<T: Sendable>(_ label: String, operation: () async throws -> T) async throws -> FetchResult<T> {
    do { return FetchResult(value: try await operation(), failure: nil) }
    catch {
        if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
        return FetchResult(value: nil, failure: "\(label): \(error.localizedDescription)")
    }
}
