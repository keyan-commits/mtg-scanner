import Foundation

/// Downloads ML assets (embeddings, model) from GitHub Releases on first launch.
/// Assets are stored in the Documents directory and loaded by VisualEmbeddingStore
/// and MLCardDetector when not found in the app bundle.
actor EmbeddingDownloader {
    static let shared = EmbeddingDownloader()

    enum DownloadState: Equatable {
        case notStarted
        case downloading(progress: Double, label: String)
        case completed
        case failed(String)
    }

    private(set) var currentState: DownloadState = .notStarted

    // GitHub Releases URLs
    private let embeddingsURL = "https://github.com/keyan-commits/mtg-scanner/releases/download/v0.1.0/base_embeddings.json"
    private let modelURL = "https://github.com/keyan-commits/mtg-scanner/releases/download/v0.1.0/MTGCardDetector.mlmodel"

    var embeddingsExist: Bool {
        // Check bundle first, then Documents/
        Bundle.main.url(forResource: "base_embeddings", withExtension: "json") != nil ||
        FileManager.default.fileExists(atPath: Self.embeddingsDocumentsURL.path)
    }

    var modelExists: Bool {
        // Check for compiled model in bundle first, then downloaded
        Bundle.main.url(forResource: "MTGCardDetector", withExtension: "mlmodelc") != nil ||
        FileManager.default.fileExists(atPath: Self.modelDocumentsURL.path)
    }

    /// Whether all required assets are available (either bundled or downloaded).
    var allAssetsReady: Bool {
        embeddingsExist && modelExists
    }

    static var embeddingsDocumentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("base_embeddings.json")
    }

    static var modelDocumentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MTGCardDetector.mlmodel")
    }

    /// Downloads any missing assets. Calls `onProgress` on each progress update.
    func downloadIfNeeded(onProgress: (@Sendable (Double, String) -> Void)? = nil) async {
        guard !allAssetsReady else {
            currentState = .completed
            return
        }

        // Download embeddings if not present
        if !embeddingsExist {
            let success = await download(
                from: embeddingsURL,
                to: Self.embeddingsDocumentsURL,
                label: "card embeddings",
                onProgress: onProgress
            )
            guard success else { return }
        }

        // Download model if not in bundle
        if !modelExists {
            let success = await download(
                from: modelURL,
                to: Self.modelDocumentsURL,
                label: "ML model",
                onProgress: onProgress
            )
            guard success else { return }
        }

        currentState = .completed
    }

    private func download(
        from urlString: String,
        to destination: URL,
        label: String,
        onProgress: (@Sendable (Double, String) -> Void)?
    ) async -> Bool {
        guard let url = URL(string: urlString) else {
            currentState = .failed("Invalid URL for \(label)")
            return false
        }

        currentState = .downloading(progress: 0, label: label)
        onProgress?(0, label)

        do {
            let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)
            let totalBytes = response.expectedContentLength

            var data = Data()
            if totalBytes > 0 {
                data.reserveCapacity(Int(totalBytes))
            }

            var downloaded: Int64 = 0
            for try await byte in asyncBytes {
                data.append(byte)
                downloaded += 1
                if totalBytes > 0 && downloaded % 100_000 == 0 {
                    let progress = Double(downloaded) / Double(totalBytes)
                    currentState = .downloading(progress: progress, label: label)
                    onProgress?(progress, label)
                }
            }

            try data.write(to: destination)
            print("[EmbeddingDownloader] Downloaded \(label): \(data.count / 1_024 / 1_024) MB")
            return true
        } catch {
            let message = "Failed to download \(label): \(error.localizedDescription)"
            currentState = .failed(message)
            print("[EmbeddingDownloader] \(message)")
            return false
        }
    }
}
