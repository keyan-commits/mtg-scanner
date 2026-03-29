import SwiftUI
import SwiftData

@main
struct MTGCardScannerApp: App {

    @State private var setupState: SetupState = .checking
    @State private var viewModel: CardScannerViewModel?

    private let databaseManager: DatabaseManager?
    private let downloader: ScryfallBulkDataDownloader

    init() {
        self.downloader = ScryfallBulkDataDownloader()
        self.databaseManager = try? DatabaseManager()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let viewModel, setupState == .ready {
                    NavigationStack {
                        ScannerScreen(viewModel: viewModel)
                    }
                } else {
                    SetupScreen(setupState: $setupState)
                }
            }
            .background(MD3Theme.background)
            .task {
                await setupDatabase()
            }
        }
    }

    @MainActor
    private func setupDatabase() async {
        guard let databaseManager else {
            setupState = .error("Failed to initialize database.")
            return
        }

        do {
            // Version 2 = default_cards (all printings). Version 1 was oracle_cards.
            let dbVersion = UserDefaults.standard.integer(forKey: "dbVersion")
            let currentVersion = 5
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

        self.viewModel = CardScannerViewModel(
            recognizer: recognizer,
            nameExtractor: nameExtractor,
            repository: repository
        )
    }
}
