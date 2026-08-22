import Foundation
import OSLog

enum PromotionTerminalState: String, Codable {
    case converted
    case expired
}

struct StoredPromotionState: Codable, Equatable {
    var firstPresentedAt: Date?
    var expiresAt: Date?
    var lastLaunchPresentedAt: Date?
    var presentedPlacements: Set<PromotionPlacement> = []
    var terminalState: PromotionTerminalState?
}

@MainActor
final class PromotionStateStore {
    static let storageKey = "InAppPromotionKit.campaignStates.v1"
    static let firstLaunchRegisteredAtKey = "InAppPromotionKit.firstLaunchRegisteredAt.v1"

    private let defaults: UserDefaults
    private var states: [String: StoredPromotionState]
    private let logger = Logger(
        subsystem: "InAppPromotionKit",
        category: "PromotionStateStore"
    )

    init(defaults: UserDefaults) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.storageKey) else {
            states = [:]
            return
        }
        do {
            states = try JSONDecoder().decode(
                [String: StoredPromotionState].self,
                from: data
            )
        } catch {
            states = [:]
            logger.error("Unable to decode promotion state: \(error.localizedDescription, privacy: .public)")
        }
    }

    func state(for campaignID: String) -> StoredPromotionState {
        states[campaignID] ?? StoredPromotionState()
    }

    var firstLaunchRegisteredAt: Date? {
        defaults.object(forKey: Self.firstLaunchRegisteredAtKey) as? Date
    }

    var earliestLaunchPresentationAt: Date? {
        states.values.compactMap(\.lastLaunchPresentedAt).min()
    }

    func registerFirstLaunch(noLaterThan date: Date) {
        if let existing = firstLaunchRegisteredAt, existing <= date {
            return
        }
        defaults.set(date, forKey: Self.firstLaunchRegisteredAtKey)
    }

    func update(
        campaignID: String,
        _ mutation: (inout StoredPromotionState) -> Void
    ) {
        var state = state(for: campaignID)
        mutation(&state)
        states[campaignID] = state
        persist()
    }

    func remove(campaignID: String) {
        states.removeValue(forKey: campaignID)
        persist()
    }

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(states), forKey: Self.storageKey)
        } catch {
            logger.error("Unable to encode promotion state: \(error.localizedDescription, privacy: .public)")
        }
    }
}
