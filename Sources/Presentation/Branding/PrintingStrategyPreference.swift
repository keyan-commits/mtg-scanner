import Foundation
import Observation

/// Persists the user's preferred printing-resolution strategy for
/// deck lists displayed *outside* My Decks (currently the MTGTop8
/// deck detail view, where every card row resolves a bare card name
/// to a concrete printing).
///
/// My Decks intentionally does not consult this preference because
/// those rows already carry user-chosen printings.
@MainActor
@Observable
final class PrintingStrategyPreference {

    static let shared = PrintingStrategyPreference()

    private static let key = "deckDisplay.printingStrategy"

    /// The currently-selected default strategy. Read at view init in
    /// `MTGTop8DeckDetailView`. The view's toolbar still allows a
    /// per-deck override that does NOT persist back here.
    var strategy: PrintingStrategy {
        didSet {
            UserDefaults.standard.set(strategy.rawValue, forKey: Self.key)
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.key) ?? PrintingStrategy.firstPrint.rawValue
        self.strategy = PrintingStrategy(rawValue: raw) ?? .firstPrint
    }
}
