import Foundation

enum PromotionPolicy {
    static let standardPaywallCooldown: TimeInterval = 24 * 60 * 60
    static let exclusiveOfferDuration: TimeInterval = 72 * 60 * 60
    static let urgentThreshold: TimeInterval = 6 * 60 * 60

    static func supports(_ placement: PromotionPlacement, for kind: PromotionKind) -> Bool {
        switch kind {
        case .standardPaywall:
            placement == .launchModal
        case .exclusiveOffer:
            true
        }
    }
}
