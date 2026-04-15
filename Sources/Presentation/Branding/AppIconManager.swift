import Foundation
import UIKit
import Observation

/// Manages alternate app icons for MTG Keyan.
///
/// Five icons exist (one per WUBRG mana color). The primary icon (W —
/// white sun orb) is the default; U/B/R/G are registered as alternate
/// icons in `Info.plist` under `CFBundleAlternateIcons`.
///
/// Two modes:
/// - **Daily rotation** (default ON): On every cold launch, if a new
///   day has started since the last rotation, advance to the next color
///   in the W → U → B → R → G → W cycle. iOS will show its system
///   confirmation alert when the icon actually changes.
/// - **Manual** (rotation OFF): The user picks a fixed color and it
///   stays until they pick another or re-enable rotation.
@MainActor
@Observable
final class AppIconManager {

    // MARK: - Singleton

    static let shared = AppIconManager()

    // MARK: - Mana colors

    enum ManaColor: String, CaseIterable, Identifiable {
        case W, U, B, R, G

        var id: String { rawValue }

        /// Human label for the picker.
        var displayName: String {
            switch self {
            case .W: return "White"
            case .U: return "Blue"
            case .B: return "Black"
            case .R: return "Red"
            case .G: return "Green"
            }
        }

        /// SF Symbol matching the orb's symbol — used in the picker UI.
        var symbolName: String {
            switch self {
            case .W: return "sun.max.fill"
            case .U: return "drop.fill"
            case .B: return "moon.fill"
            case .R: return "flame.fill"
            case .G: return "tree.fill"
            }
        }

        /// The alternate icon name registered in Info.plist.
        /// Returns nil for `.W` because that's the *primary* icon —
        /// `setAlternateIconName(nil)` is how iOS reverts to primary.
        var alternateIconName: String? {
            switch self {
            case .W: return nil
            default: return "AppIcon-\(rawValue)"
            }
        }

        /// Next color in the W→U→B→R→G→W cycle.
        var next: ManaColor {
            let all = ManaColor.allCases
            let idx = all.firstIndex(of: self) ?? 0
            return all[(idx + 1) % all.count]
        }
    }

    // MARK: - UserDefaults keys

    private enum Keys {
        static let rotationEnabled = "appIcon.rotationEnabled"
        static let currentColor = "appIcon.currentColor"
        static let lastRotationDay = "appIcon.lastRotationDay"  // YYYY-MM-DD
    }

    // MARK: - Observable state

    /// Whether daily rotation is enabled. Defaults to true.
    var rotationEnabled: Bool {
        didSet {
            UserDefaults.standard.set(rotationEnabled, forKey: Keys.rotationEnabled)
        }
    }

    /// The currently displayed color (best-effort — reflects what we
    /// last asked iOS to show, since iOS itself doesn't expose this
    /// reliably across launches).
    private(set) var currentColor: ManaColor

    // MARK: - Init

    private init() {
        let defaults = UserDefaults.standard
        // Default rotation ON unless user has explicitly opted out
        if defaults.object(forKey: Keys.rotationEnabled) == nil {
            self.rotationEnabled = true
        } else {
            self.rotationEnabled = defaults.bool(forKey: Keys.rotationEnabled)
        }
        let raw = defaults.string(forKey: Keys.currentColor) ?? ManaColor.W.rawValue
        self.currentColor = ManaColor(rawValue: raw) ?? .W
    }

    // MARK: - Public API

    /// Called on app launch. If rotation is enabled and the day has
    /// changed since we last rotated, advance to the next color.
    func rotateIfNeeded() {
        guard rotationEnabled else { return }
        let today = Self.todayKey()
        let lastDay = UserDefaults.standard.string(forKey: Keys.lastRotationDay)
        guard lastDay != today else { return }

        let next = currentColor.next
        setIcon(next, persistRotationDay: true)
    }

    /// User-driven manual selection. Disables rotation as a side effect
    /// (manual choice = "I want this color forever").
    func setManual(_ color: ManaColor) {
        rotationEnabled = false
        setIcon(color, persistRotationDay: false)
    }

    /// Re-enable rotation without changing the current icon. The next
    /// rotation will fire on the next cold launch on a new day.
    func enableRotation() {
        rotationEnabled = true
    }

    // MARK: - Private

    private func setIcon(_ color: ManaColor, persistRotationDay: Bool) {
        let altName = color.alternateIconName
        // Only call UIKit if iOS actually supports alternate icons
        // (always true on iOS 10.3+, which is well below our deploy target).
        guard UIApplication.shared.supportsAlternateIcons else {
            currentColor = color
            persist(color: color, rotationDay: persistRotationDay)
            return
        }
        UIApplication.shared.setAlternateIconName(altName) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    print("[AppIconManager] setAlternateIconName failed: \(error)")
                    return
                }
                self.currentColor = color
                self.persist(color: color, rotationDay: persistRotationDay)
            }
        }
    }

    private func persist(color: ManaColor, rotationDay: Bool) {
        UserDefaults.standard.set(color.rawValue, forKey: Keys.currentColor)
        if rotationDay {
            UserDefaults.standard.set(Self.todayKey(), forKey: Keys.lastRotationDay)
        }
    }

    private static func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }
}
