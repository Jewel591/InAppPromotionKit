import Foundation

public struct PromotionCampaign: Hashable, Codable, Sendable {
    public let id: String
    public let kind: PromotionKind

    public init(id: String, kind: PromotionKind) {
        self.id = id
        self.kind = kind
    }
}

public enum PromotionKind: String, Codable, Sendable {
    /// An evergreen paywall prompt. Launch presentation begins only after the
    /// install-level first-launch quiet period and then occurs no more than once
    /// every 24 hours.
    case standardPaywall

    /// A one-time, 72-hour offer shared by launch, floating-badge, and settings placements.
    case exclusiveOffer
}

public enum PromotionPlacement: String, CaseIterable, Codable, Sendable {
    case launchModal
    case floatingBadge
    case settingsBanner
}

public enum PromotionEligibility: Sendable {
    case eligible
    case ineligible
    case unavailable
}

public enum PromotionDecision: Equatable, Sendable {
    case present
    case hidden(PromotionHiddenReason)
}

public enum PromotionHiddenReason: String, Equatable, Sendable {
    case ineligible
    case unavailable
    case unsupportedPlacement
    case initialCooldown
    case cooldown
    case alreadyPresented
    case expired
    case converted
    case evaluationInProgress
    case anotherPlacementActive
}

public enum PromotionUrgency: Equatable, Sendable {
    case normal
    case urgent
}

public struct PromotionSnapshot: Equatable, Sendable {
    public let isVisible: Bool
    public let remainingTime: TimeInterval?
    public let urgency: PromotionUrgency
    public let hiddenReason: PromotionHiddenReason?

    init(
        isVisible: Bool,
        remainingTime: TimeInterval? = nil,
        urgency: PromotionUrgency = .normal,
        hiddenReason: PromotionHiddenReason? = nil
    ) {
        self.isVisible = isVisible
        self.remainingTime = remainingTime
        self.urgency = urgency
        self.hiddenReason = hiddenReason
    }
}

@MainActor
public protocol PromotionEligibilityProviding: AnyObject {
    func eligibility(for campaign: PromotionCampaign) async -> PromotionEligibility
}
