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
                    let service = PriceRefreshService(downloader: downloader, databaseManager: databaseManager)
                    PriceRefreshService.shared = service
                    priceRefreshService = service
                    await service.refreshIfStale()
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
            let currentVersion = 8
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

            // Import in background, updating progress
            let data = try Data(contentsOf: fileURL)
            guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                setupState = .error("Downloaded data is invalid.")
                return
            }

            let context = ModelContext(databaseManager.modelContainer)
            let total = jsonArray.count
            let batchSize = 500
            var count = 0

            for json in jsonArray {
                guard let record = CardRecord.fromBulkJSON(json) else { continue }
                context.insert(record)
                count += 1

                if count % batchSize == 0 {
                    try context.save()
                    setupState = .importing(progress: Double(count) / Double(total))
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
