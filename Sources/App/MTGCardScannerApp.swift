import SwiftUI
import SwiftData

@main
struct MTGCardScannerApp: App {

    @State private var setupState: SetupState = .checking
    @State private var viewModel: CardScannerViewModel?
    // Stored as concrete types wrapped in Any to avoid @State protocol issues
    @State private var storedPipeline: CardIdentificationPipeline?
    @State private var storedRepository: LocalCardRepository?
    @State private var storedDeckRepository: DeckListRepository?
    @State private var priceRefreshService: PriceRefreshService?

    private let databaseManager: DatabaseManager?
    private let downloader: ScryfallBulkDataDownloader

    init() {
        self.downloader = ScryfallBulkDataDownloader()
        self.databaseManager = try? DatabaseManager()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let viewModel,
                   let storedPipeline,
                   let storedRepository,
                   let storedDeckRepository,
                   setupState == .ready {
                    RootView(
                        viewModel: viewModel,
                        pipeline: storedPipeline,
                        repository: storedRepository,
                        deckRepository: storedDeckRepository
                    )
                } else {
                    SetupScreen(setupState: $setupState)
                }
            }
            .background(MD3Theme.background)
            .task {
                await setupDatabase()
                // Daily price refresh — runs in background after app is ready
                if let databaseManager {
                    DynamicListService.shared.configure(databaseManager: databaseManager)
                    let service = PriceRefreshService(downloader: downloader, databaseManager: databaseManager)
                    PriceRefreshService.shared = service
                    priceRefreshService = service
                    // Fire-and-forget: don't block home screen with price refresh
                    Task.detached(priority: .utility) {
                        await service.refreshIfStale()
                        await MainActor.run {
                            DynamicListService.shared.invalidateCache()
                        }
                    }
                }
            }
            .task {
                // Daily WUBRG icon rotation. No-op if rotation is
                // disabled or the day hasn't changed.
                AppIconManager.shared.rotateIfNeeded()
            }
        }
    }

    @MainActor
    private func setupDatabase() async {
        // Download ML assets from GitHub Releases if not bundled or already downloaded
        let assetDownloader = EmbeddingDownloader.shared
        if await !assetDownloader.allAssetsReady {
            setupState = .downloadingAssets(progress: 0, label: "ML assets")
            await assetDownloader.downloadIfNeeded(onProgress: { progress, label in
                Task { @MainActor in
                    self.setupState = .downloadingAssets(progress: progress, label: label)
                }
            })
            let finalState = await assetDownloader.currentState
            if case .failed(let msg) = finalState {
                setupState = .error(msg)
                return
            }
        }

        guard let databaseManager else {
            setupState = .error("Failed to initialize database.")
            return
        }

        do {
            // Version 2 = default_cards (all printings). Version 1 was oracle_cards.
            // Version 8 = DFC image URI fallback to card_faces[0].image_uris
            // (without this, double-faced cards render as gray
            // placeholders in the deck grid view).
            let dbVersion = UserDefaults.standard.integer(forKey: "dbVersion")
            // Version 9 = language metadata (lang, printed_name) encoded
            // in imageURIsJSON sentinel keys for Japanese card support.
            let currentVersion = 9
            let cardCount = try await databaseManager.cardCount()

            if cardCount > 0 && dbVersion >= currentVersion {
                wireViewModel(databaseManager: databaseManager)
                setupState = .ready
                return
            }

            // Clear old data if upgrading
            if cardCount > 0 && dbVersion < currentVersion {
                let context = ModelContext(databaseManager.modelContainer)
                try context.delete(model: CardRecord.self)
                try context.save()
            }

            setupState = .downloading
            let fileURL = try await downloader.downloadBulkData()

            setupState = .importing(progress: 0)

            // Memory-map the file to avoid loading ~200MB into heap.
            // Parse individual JSON objects (not the whole array) to
            // keep peak memory low on older devices.
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            let context = ModelContext(databaseManager.modelContainer)
            let batchSize = 500
            var count = 0
            let totalBytes = data.count
            var i = data.startIndex

            while i < data.endIndex {
                // Skip to next '{'
                while i < data.endIndex && data[i] != UInt8(ascii: "{") { i = data.index(after: i) }
                guard i < data.endIndex else { break }

                // Find matching '}' — properly handle braces inside strings
                let start = i
                var depth = 0
                var inString = false
                var escaped = false

                while i < data.endIndex {
                    let b = data[i]
                    if escaped {
                        escaped = false
                    } else if b == UInt8(ascii: "\\") && inString {
                        escaped = true
                    } else if b == UInt8(ascii: "\"") {
                        inString = !inString
                    } else if !inString {
                        if b == UInt8(ascii: "{") { depth += 1 }
                        else if b == UInt8(ascii: "}") {
                            depth -= 1
                            if depth == 0 {
                                i = data.index(after: i)
                                break
                            }
                        }
                    }
                    i = data.index(after: i)
                }

                // Parse this single card object
                let objectSlice = data[start..<i]
                autoreleasepool {
                    if let json = try? JSONSerialization.jsonObject(with: Data(objectSlice)) as? [String: Any],
                       let record = CardRecord.fromBulkJSON(json) {
                        context.insert(record)
                        count += 1
                    }
                }

                if count > 0 && count % batchSize == 0 {
                    try context.save()
                    let byteOffset = data.distance(from: data.startIndex, to: i)
                    setupState = .importing(progress: Double(byteOffset) / Double(totalBytes))
                }
            }

            if count % batchSize != 0 {
                try context.save()
            }

            // Clean up temp file
            try? FileManager.default.removeItem(at: fileURL)

            UserDefaults.standard.set(currentVersion, forKey: "dbVersion")

            wireViewModel(databaseManager: databaseManager)
            setupState = .ready

        } catch {
            setupState = .error("Setup failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func wireViewModel(databaseManager: DatabaseManager) {
        let repository = LocalCardRepository(databaseManager: databaseManager)
        let recognizer = VisionTextRecognizer()
        let nameExtractor = CardNameExtractor()

        // Load visual search index (optional — pipeline falls back to OCR if nil)
        let visualEngine = loadVisualSearchEngine()

        // Create FeaturePrint cache in Application Support (grows as user scans cards)
        let featurePrintCache = createFeaturePrintCache()

        // Clear stale cache from development testing (one-time)
        let cacheVersion = UserDefaults.standard.integer(forKey: "fpCacheVersion")
        if cacheVersion < 5, let cache = featurePrintCache {
            Task { await cache.clear() }
            UserDefaults.standard.set(5, forKey: "fpCacheVersion")
        }

        // Create persistent embedding store (k-NN classifier that learns from corrections)
        let embeddingStore = VisualEmbeddingStore()

        // Create correction service (requires FeaturePrint cache)
        let correctionService: CardCorrectionService? = featurePrintCache.map {
            CardCorrectionService(featurePrintCache: $0, embeddingStore: embeddingStore)
        }

        let pipeline = CardIdentificationPipeline(
            recognizer: recognizer,
            repository: repository,
            visualSearchEngine: visualEngine,
            featurePrintCache: featurePrintCache,
            embeddingStore: embeddingStore
        )

        self.storedPipeline = pipeline
        self.storedRepository = repository
        self.storedDeckRepository = DeckListRepository(modelContainer: databaseManager.modelContainer)
        self.viewModel = CardScannerViewModel(pipeline: pipeline, correctionService: correctionService)
        print("[MTGScanner] Wired: pipeline=\(pipeline), repo=\(repository), correction=\(String(describing: correctionService))")
    }

    /// Creates a FeaturePrint cache stored in Application Support.
    /// The cache grows organically as the user scans cards.
    private func createFeaturePrintCache() -> FeaturePrintCache? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let appDir = appSupport.appendingPathComponent("MTGCardScanner", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        let cacheURL = appDir.appendingPathComponent("featureprint_cache.json")
        print("[MTGScanner] FeaturePrint cache at: \(cacheURL.path)")
        return FeaturePrintCache(fileURL: cacheURL)
    }

    /// Attempts to load the visual search engine from the bundle or Application Support.
    /// Returns nil if no visual index is available yet.
    private func loadVisualSearchEngine() -> VisualSearchEngine? {
        // Try bundle first (shipped with app)
        if let engine = VisualSearchEngine.loadFromBundle() {
            print("[MTGScanner] Visual index loaded from bundle")
            return engine
        }

        // Try Application Support (downloaded/generated at runtime)
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let visualIndexURL = appSupport
                .appendingPathComponent("MTGCardScanner", isDirectory: true)
                .appendingPathComponent("visual_index.json")
            if let engine = VisualSearchEngine.load(from: visualIndexURL) {
                print("[MTGScanner] Visual index loaded from Application Support")
                return engine
            }
        }

        print("[MTGScanner] No visual index available — using OCR-only pipeline")
        return nil
    }
}
