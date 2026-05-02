import Testing
import Foundation
@testable import MTGCardScanner

@Suite("MTGTop8WaybackFallbackClient Tests")
struct MTGTop8WaybackFallbackClientTests {

    /// Programmable mock that returns a different result for each
    /// distinct URL. Default behavior is "throw not-connected" so any
    /// unexpected URL fails loudly.
    final class RoutedMock: HTTPClientProtocol, @unchecked Sendable {
        private let lock = NSLock()
        private var routes: [String: () throws -> (Data, URLResponse)] = [:]
        private(set) var requestedURLs: [URL] = []

        func register(url: String, _ handler: @escaping () throws -> (Data, URLResponse)) {
            lock.lock(); defer { lock.unlock() }
            routes[url] = handler
        }

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            lock.lock()
            if let url = request.url {
                requestedURLs.append(url)
            }
            let handler = request.url.flatMap { routes[$0.absoluteString] }
            lock.unlock()
            guard let handler else {
                throw URLError(.notConnectedToInternet)
            }
            return try handler()
        }
    }

    private static let liveURL = URL(string: "https://mtgtop8.com/search?archetype_sel%5BMO%5D=42")!

    private static func okResponse(url: URL = liveURL, body: String) -> () throws -> (Data, URLResponse) {
        return {
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
    }

    private static func errorResponse(url: URL, statusCode: Int) -> () throws -> (Data, URLResponse) {
        return {
            let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        }
    }

    private static let availabilityJSON = """
    {
      "archived_snapshots": {
        "closest": {
          "url": "https://web.archive.org/web/20260101120000/https://mtgtop8.com/search?archetype_sel%5BMO%5D=42",
          "timestamp": "20260101120000",
          "available": true
        }
      }
    }
    """

    private static let emptyAvailabilityJSON = """
    { "archived_snapshots": {} }
    """

    // MARK: - Pass-through

    @Test("Live success passes through unchanged")
    func liveSuccessPassesThrough() async throws {
        let inner = RoutedMock()
        inner.register(url: Self.liveURL.absoluteString, Self.okResponse(body: "<html>live</html>"))
        let wayback = RoutedMock()
        let client = MTGTop8WaybackFallbackClient(inner: inner, waybackClient: wayback)

        let (data, _) = try await client.data(for: URLRequest(url: Self.liveURL))

        #expect(String(data: data, encoding: .utf8) == "<html>live</html>")
        #expect(wayback.requestedURLs.isEmpty)  // Wayback never queried
    }

    // MARK: - Throw fallback

    @Test("Falls back to Wayback when inner throws")
    func throwTriggersFallback() async throws {
        let inner = RoutedMock()  // any URL throws
        let wayback = RoutedMock()

        let availabilityURL = "https://archive.org/wayback/available?url=https%3A%2F%2Fmtgtop8.com%2Fsearch%3Farchetype_sel%255BMO%255D%3D42"
        wayback.register(url: availabilityURL, Self.okResponse(
            url: URL(string: availabilityURL)!,
            body: Self.availabilityJSON
        ))

        let snapshotURL = "https://web.archive.org/web/20260101120000id_/https://mtgtop8.com/search?archetype_sel%5BMO%5D=42"
        wayback.register(url: snapshotURL, Self.okResponse(
            url: URL(string: snapshotURL)!,
            body: "<html>archived</html>"
        ))

        let client = MTGTop8WaybackFallbackClient(inner: inner, waybackClient: wayback)
        let (data, _) = try await client.data(for: URLRequest(url: Self.liveURL))

        #expect(String(data: data, encoding: .utf8) == "<html>archived</html>")
    }

    // MARK: - 5xx fallback

    @Test("5xx response triggers Wayback fallback")
    func serverErrorTriggersFallback() async throws {
        let inner = RoutedMock()
        inner.register(url: Self.liveURL.absoluteString, Self.errorResponse(url: Self.liveURL, statusCode: 503))

        let wayback = RoutedMock()
        let availabilityURL = "https://archive.org/wayback/available?url=https%3A%2F%2Fmtgtop8.com%2Fsearch%3Farchetype_sel%255BMO%255D%3D42"
        wayback.register(url: availabilityURL, Self.okResponse(
            url: URL(string: availabilityURL)!,
            body: Self.availabilityJSON
        ))
        let snapshotURL = "https://web.archive.org/web/20260101120000id_/https://mtgtop8.com/search?archetype_sel%5BMO%5D=42"
        wayback.register(url: snapshotURL, Self.okResponse(
            url: URL(string: snapshotURL)!,
            body: "<html>archived</html>"
        ))

        let client = MTGTop8WaybackFallbackClient(inner: inner, waybackClient: wayback)
        let (data, _) = try await client.data(for: URLRequest(url: Self.liveURL))

        #expect(String(data: data, encoding: .utf8) == "<html>archived</html>")
    }

    // MARK: - 404 stays as success

    @Test("404 does not trigger Wayback — page parsed, just empty")
    func notFoundDoesNotFallBack() async throws {
        let inner = RoutedMock()
        inner.register(url: Self.liveURL.absoluteString, Self.errorResponse(url: Self.liveURL, statusCode: 404))
        let wayback = RoutedMock()

        let client = MTGTop8WaybackFallbackClient(inner: inner, waybackClient: wayback)
        let (_, response) = try await client.data(for: URLRequest(url: Self.liveURL))

        #expect((response as? HTTPURLResponse)?.statusCode == 404)
        #expect(wayback.requestedURLs.isEmpty)
    }

    // MARK: - No snapshot available

    @Test("Original error rethrown when Wayback has no snapshot")
    func noSnapshotRethrowsOriginalError() async {
        let inner = RoutedMock()  // throws .notConnectedToInternet
        let wayback = RoutedMock()
        let availabilityURL = "https://archive.org/wayback/available?url=https%3A%2F%2Fmtgtop8.com%2Fsearch%3Farchetype_sel%255BMO%255D%3D42"
        wayback.register(url: availabilityURL, Self.okResponse(
            url: URL(string: availabilityURL)!,
            body: Self.emptyAvailabilityJSON
        ))

        let client = MTGTop8WaybackFallbackClient(inner: inner, waybackClient: wayback)

        do {
            _ = try await client.data(for: URLRequest(url: Self.liveURL))
            Issue.record("Expected throw")
        } catch {
            // Expected — original error from inner client surfaces.
            #expect((error as? URLError)?.code == .notConnectedToInternet)
        }
    }
}
