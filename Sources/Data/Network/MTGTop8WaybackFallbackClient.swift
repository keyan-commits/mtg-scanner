import Foundation

/// HTTP client decorator that falls back to the Wayback Machine when
/// the inner client fails. Used as an outer wrapper around
/// `MTGTop8MonitoredHTTPClient` so live failures still update the
/// availability monitor before Wayback takes over.
///
/// Wrap order:
/// ```
/// MTGTop8Service
///   └── MTGTop8WaybackFallbackClient   (catches throws, queries Wayback)
///         └── MTGTop8MonitoredHTTPClient (records live success/failure)
///               └── URLSessionHTTPClient (live network)
/// ```
///
/// Wayback's `archive.org/wayback/available?url=...` endpoint returns
/// metadata about the closest archived snapshot. We then fetch the
/// snapshot using the `<timestamp>id_/` form so the response bytes are
/// the original archived HTML — without Wayback's overlay UI — so the
/// existing MTGTop8 parsers work unmodified.
///
/// Failures of Wayback itself surface as errors to the caller; the
/// upstream cache layer will then fall back to its stale entry.
struct MTGTop8WaybackFallbackClient: HTTPClientProtocol {
    let inner: HTTPClientProtocol
    let waybackClient: HTTPClientProtocol

    /// Optional override: lets tests inject a different host (e.g. a
    /// mock) and lets us swap out archive.org if it ever moves.
    let availabilityEndpoint: String

    init(
        inner: HTTPClientProtocol,
        waybackClient: HTTPClientProtocol = URLSessionHTTPClient(),
        availabilityEndpoint: String = "https://archive.org/wayback/available"
    ) {
        self.inner = inner
        self.waybackClient = waybackClient
        self.availabilityEndpoint = availabilityEndpoint
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            let (data, response) = try await inner.data(for: request)
            // Treat 5xx / 4xx-not-404 as "live failed, try Wayback."
            // Same classification as the monitor uses, kept in sync
            // here so a flaky 5xx still gets the Wayback shot.
            if let http = response as? HTTPURLResponse,
               Self.shouldFallback(status: http.statusCode) {
                if let waybackResult = try? await fetchFromWayback(originalURL: request.url) {
                    return waybackResult
                }
            }
            return (data, response)
        } catch {
            guard let url = request.url,
                  let waybackResult = try? await fetchFromWayback(originalURL: url) else {
                throw error
            }
            return waybackResult
        }
    }

    // MARK: - Wayback lookup

    private struct WaybackAvailabilityResponse: Decodable {
        struct ArchivedSnapshots: Decodable {
            struct Closest: Decodable {
                let url: String
                let timestamp: String
                let available: Bool
            }
            let closest: Closest?
        }
        let archived_snapshots: ArchivedSnapshots
    }

    /// RFC 3986 unreserved characters — the only chars we leave
    /// literal when embedding a URL inside another URL's query value.
    /// `urlQueryAllowed` is too permissive (leaves `:`, `/`, `?`, `=`
    /// untouched) which would produce an ambiguous lookup URL.
    private static let unreservedCharacters: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    private func fetchFromWayback(originalURL: URL?) async throws -> (Data, URLResponse) {
        guard let originalURL else { throw URLError(.badURL) }

        guard let encoded = originalURL.absoluteString.addingPercentEncoding(
            withAllowedCharacters: Self.unreservedCharacters
        ),
        let lookupURL = URL(string: "\(availabilityEndpoint)?url=\(encoded)") else {
            throw URLError(.badURL)
        }

        var lookupRequest = URLRequest(url: lookupURL)
        lookupRequest.timeoutInterval = 10

        let (lookupData, _) = try await waybackClient.data(for: lookupRequest)
        let parsed = try JSONDecoder().decode(WaybackAvailabilityResponse.self, from: lookupData)
        guard let closest = parsed.archived_snapshots.closest, closest.available else {
            throw URLError(.fileDoesNotExist)
        }

        // Transform "/web/<ts>/" → "/web/<ts>id_/" to get raw archived
        // bytes (no Wayback chrome). The `id_` flag is documented at
        // https://archive.org/details/wayback_modifier_flags.
        let rawSnapshotURLString = closest.url.replacingOccurrences(
            of: "/web/\(closest.timestamp)/",
            with: "/web/\(closest.timestamp)id_/"
        )
        guard let snapshotURL = URL(string: rawSnapshotURLString) else {
            throw URLError(.badURL)
        }
        var snapshotRequest = URLRequest(url: snapshotURL)
        snapshotRequest.timeoutInterval = 15
        return try await waybackClient.data(for: snapshotRequest)
    }

    private static func shouldFallback(status: Int) -> Bool {
        if status == 404 { return false }
        return status >= 500 || (status >= 400 && status < 500)
    }
}
