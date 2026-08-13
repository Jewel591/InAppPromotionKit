import Foundation

public enum PromotionEventName: String, Sendable {
    case eligible
    case impression
    case dismiss
    case click
    case paywallOpened
    case converted
    case expired
}

public struct PromotionEvent: Sendable {
    public let name: PromotionEventName
    public let campaign: PromotionCampaign
    public let placement: PromotionPlacement?
    public let date: Date
}

@MainActor
public protocol PromotionEventTracking: AnyObject {
    func track(_ event: PromotionEvent)
}

@MainActor
final class NoOpPromotionEventTracker: PromotionEventTracking {
    func track(_: PromotionEvent) {}
}
