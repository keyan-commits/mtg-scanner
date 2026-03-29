import Foundation

struct IdentifyCardUseCase: Sendable {
    private let repository: CardRepositoryProtocol

    init(repository: CardRepositoryProtocol) {
        self.repository = repository
    }

    func execute(recognizedText: String) async throws -> Card {
        try await repository.identifyCard(name: recognizedText)
    }
}
