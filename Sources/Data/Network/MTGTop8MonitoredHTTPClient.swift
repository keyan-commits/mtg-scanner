import Foundation

/// Wraps an `HTTPClientProtocol` so every MTGTop8 request reports its
/// outcome to the shared `MTGTop8AvailabilityMonitor`.
///
/// Record success when the inner client returns a 2xx/3xx response.
/// Record failure on:
///   - thrown errors (connection refused, timeout, no internet, etc.)
///   - 5xx server responses
///   - 4xx-but-not-404 responses (MTGTop8 uses 200 for "no results"; a
///     4xx here means routing/auth/blocking, not an empty result)
///
/// 404 is treated as a success — it means the page parsed and returned
/// "not found," not that the service is down.
struct MTGTop8MonitoredHTTPClient: HTTPClientProtocol {
    let inner: HTTPClientProtocol
    let monitor: MTGTop8AvailabilityMonitor

    init(
        inner: HTTPClientProtocol = URLSessionHTTPClient(),
        monitor: MTGTop8AvailabilityMonitor = .shared
    ) {
        self.inner = inner
        self.monitor = monitor
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            let (data, response) = try await inner.data(for: request)
            if let http = response as? HTTPURLResponse, Self.shouldCountAsFailure(status: http.statusCode) {
                await monitor.recordFailure()
            } else {
                await monitor.recordSuccess()
            }
            return (data, response)
        } catch {
            await monitor.recordFailure()
            throw error
        }
    }

    private static func shouldCountAsFailure(status: Int) -> Bool {
        if status == 404 { return false }
        return status >= 500 || (status >= 400 && status < 500)
    }
}
