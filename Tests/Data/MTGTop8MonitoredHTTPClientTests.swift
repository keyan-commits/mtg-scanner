import Testing
import Foundation
@testable import MTGCardScanner

@Suite("MTGTop8MonitoredHTTPClient Tests")
struct MTGTop8MonitoredHTTPClientTests {

    private static let url = URL(string: "https://mtgtop8.com/search")!

    private static func makeMonitor(
        failureThreshold: Int = 3
    ) -> MTGTop8AvailabilityMonitor {
        MTGTop8AvailabilityMonitor(
            failureThreshold: failureThreshold,
            unavailableDuration: 60
        )
    }

    @Test("2xx response records success")
    func successRecordsSuccess() async throws {
        let monitor = Self.makeMonitor()
        await monitor.recordFailure()
        await monitor.recordFailure()  // 2 failures in the bank

        let client = MTGTop8MonitoredHTTPClient(
            inner: MockHTTPClient.success(data: Data(), statusCode: 200, url: Self.url),
            monitor: monitor
        )
        _ = try await client.data(for: URLRequest(url: Self.url))

        #expect(await monitor.isAvailable == true)
    }

    @Test("Thrown error records failure")
    func thrownErrorRecordsFailure() async {
        let monitor = Self.makeMonitor(failureThreshold: 1)
        let client = MTGTop8MonitoredHTTPClient(
            inner: MockHTTPClient.failure(URLError(.notConnectedToInternet)),
            monitor: monitor
        )

        _ = try? await client.data(for: URLRequest(url: Self.url))

        #expect(await monitor.isAvailable == false)
    }

    @Test("5xx response records failure")
    func serverErrorRecordsFailure() async throws {
        let monitor = Self.makeMonitor(failureThreshold: 1)
        let client = MTGTop8MonitoredHTTPClient(
            inner: MockHTTPClient.success(data: Data(), statusCode: 503, url: Self.url),
            monitor: monitor
        )

        _ = try await client.data(for: URLRequest(url: Self.url))

        #expect(await monitor.isAvailable == false)
    }

    @Test("404 is treated as success — page parsed, just empty")
    func notFoundIsSuccess() async throws {
        let monitor = Self.makeMonitor(failureThreshold: 1)
        let client = MTGTop8MonitoredHTTPClient(
            inner: MockHTTPClient.success(data: Data(), statusCode: 404, url: Self.url),
            monitor: monitor
        )

        _ = try await client.data(for: URLRequest(url: Self.url))

        #expect(await monitor.isAvailable == true)
    }

    @Test("4xx (except 404) records failure — usually routing/blocking")
    func clientErrorRecordsFailure() async throws {
        let monitor = Self.makeMonitor(failureThreshold: 1)
        let client = MTGTop8MonitoredHTTPClient(
            inner: MockHTTPClient.success(data: Data(), statusCode: 403, url: Self.url),
            monitor: monitor
        )

        _ = try await client.data(for: URLRequest(url: Self.url))

        #expect(await monitor.isAvailable == false)
    }
}
