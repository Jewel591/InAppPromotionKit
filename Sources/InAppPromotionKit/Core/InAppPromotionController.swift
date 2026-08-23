import Foundation
import Observation

@MainActor
@Observable
public final class InAppPromotionController {
    public static let shared = InAppPromotionController()

    /// Changes whenever persisted or runtime promotion state changes.
    public private(set) var revision = 0

    @ObservationIgnored private let store: PromotionStateStore
    @ObservationIgnored private let tracker: any PromotionEventTracking
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var eligibleCampaignIDs: Set<String> = []
    @ObservationIgnored private var evaluatingCampaignIDs: Set<String> = []
    @ObservationIgnored private var activeInterruptiveCampaignID: String?

    public convenience init(
        userDefaults: UserDefaults = .standard,
        tracker: (any PromotionEventTracking)? = nil
    ) {
        self.init(
            userDefaults: userDefaults,
            tracker: tracker,
            now: Date.init
        )
    }

    init(
        userDefaults: UserDefaults,
        tracker: (any PromotionEventTracking)? = nil,
        now: @escaping () -> Date
    ) {
        store = PromotionStateStore(defaults: userDefaults)
        self.tracker = tracker ?? NoOpPromotionEventTracker()
        self.now = now
    }

    /// Records the app's first launch for the package-owned launch-promotion
    /// quiet period. Call once from the app composition root on every launch;
    /// repeated calls are idempotent.
    public func registerLaunch() {
        ensureLaunchRegistered(at: now())
    }

    public func evaluate(
        _ campaign: PromotionCampaign,
        for placement: PromotionPlacement,
        using provider: any PromotionEligibilityProviding
    ) async -> PromotionDecision {
        guard evaluatingCampaignIDs.insert(campaign.id).inserted else {
            return .hidden(.evaluationInProgress)
        }
        defer { evaluatingCampaignIDs.remove(campaign.id) }

        let eligibility = await provider.eligibility(for: campaign)
        return evaluate(campaign, for: placement, eligibility: eligibility)
    }

    public func evaluate(
        _ campaign: PromotionCampaign,
        for placement: PromotionPlacement,
        eligibility: PromotionEligibility
    ) -> PromotionDecision {
        guard PromotionPolicy.supports(placement, for: campaign.kind) else {
            return .hidden(.unsupportedPlacement)
        }

        if placement == .launchModal {
            ensureLaunchRegistered(at: now())
        }

        switch eligibility {
        case .ineligible:
            eligibleCampaignIDs.remove(campaign.id)
            clearActivePresentation(for: campaign)
            revision += 1
            return .hidden(.ineligible)
        case .unavailable:
            eligibleCampaignIDs.remove(campaign.id)
            clearActivePresentation(for: campaign)
            revision += 1
            return .hidden(.unavailable)
        case .eligible:
            if eligibleCampaignIDs.insert(campaign.id).inserted {
                track(.eligible, campaign: campaign, placement: placement)
            }
            revision += 1
        }

        return decision(
            for: campaign,
            placement: placement,
            date: now(),
            persistExpiration: true
        )
    }

    public func snapshot(
        for campaign: PromotionCampaign,
        placement: PromotionPlacement,
        at date: Date? = nil
    ) -> PromotionSnapshot {
        guard eligibleCampaignIDs.contains(campaign.id) else {
            return PromotionSnapshot(isVisible: false, hiddenReason: .ineligible)
        }

        let evaluationDate = date ?? now()
        let result = decision(
            for: campaign,
            placement: placement,
            date: evaluationDate,
            persistExpiration: true
        )

        switch result {
        case .present:
            let state = store.state(for: campaign.id)
            let remaining = state.expiresAt.map {
                max(0, $0.timeIntervalSince(evaluationDate))
            }
            return PromotionSnapshot(
                isVisible: true,
                remainingTime: remaining,
                urgency: remaining.map { $0 <= PromotionPolicy.urgentThreshold ? .urgent : .normal }
                    ?? .normal
            )
        case .hidden(let reason):
            return PromotionSnapshot(isVisible: false, hiddenReason: reason)
        }
    }

    public func markPresented(
        _ campaign: PromotionCampaign,
        at placement: PromotionPlacement
    ) {
        guard eligibleCampaignIDs.contains(campaign.id) else { return }
        guard decision(
            for: campaign,
            placement: placement,
            date: now(),
            persistExpiration: true
        ) == .present else { return }

        let presentationDate = now()
        let existingState = store.state(for: campaign.id)
        let shouldTrackImpression = campaign.kind == .standardPaywall
            || !existingState.presentedPlacements.contains(placement)
        store.update(campaignID: campaign.id) { state in
            if state.firstPresentedAt == nil {
                state.firstPresentedAt = presentationDate
                if campaign.kind == .exclusiveOffer {
                    state.expiresAt = presentationDate.addingTimeInterval(
                        PromotionPolicy.exclusiveOfferDuration
                    )
                }
            }
            if placement == .launchModal {
                state.lastLaunchPresentedAt = presentationDate
            }
            state.presentedPlacements.insert(placement)
        }
        revision += 1
        if shouldTrackImpression {
            track(.impression, campaign: campaign, placement: placement)
        }
        if placement == .launchModal {
            activeInterruptiveCampaignID = campaign.id
        }
    }

    public func markClicked(
        _ campaign: PromotionCampaign,
        at placement: PromotionPlacement
    ) {
        guard snapshot(for: campaign, placement: placement).isVisible else { return }
        track(.click, campaign: campaign, placement: placement)
    }

    public func markPaywallOpened(
        _ campaign: PromotionCampaign,
        from placement: PromotionPlacement
    ) {
        activeInterruptiveCampaignID = campaign.id
        revision += 1
        track(.paywallOpened, campaign: campaign, placement: placement)
    }

    public func markDismissed(
        _ campaign: PromotionCampaign,
        at placement: PromotionPlacement
    ) {
        if placement == .launchModal {
            clearActivePresentation(for: campaign)
            revision += 1
        }
        track(.dismiss, campaign: campaign, placement: placement)
    }

    public func markConverted(_ campaign: PromotionCampaign) {
        store.update(campaignID: campaign.id) { state in
            state.terminalState = .converted
        }
        eligibleCampaignIDs.remove(campaign.id)
        clearActivePresentation(for: campaign)
        revision += 1
        track(.converted, campaign: campaign, placement: nil)
    }

    /// Imports a host app's previous launch-prompt timestamp without resetting its cooldown.
    public func importLegacyLaunchPresentationDate(
        _ date: Date?,
        for campaign: PromotionCampaign
    ) {
        guard let date else { return }
        let importDate = min(date, now())
        store.registerFirstLaunch(noLaterThan: importDate)
        let state = store.state(for: campaign.id)
        guard state.lastLaunchPresentedAt == nil else { return }
        store.update(campaignID: campaign.id) { importedState in
            importedState.firstPresentedAt = importedState.firstPresentedAt ?? importDate
            importedState.lastLaunchPresentedAt = importDate
            importedState.presentedPlacements.insert(.launchModal)
        }
        revision += 1
    }

    public func reset(_ campaign: PromotionCampaign) {
        store.remove(campaignID: campaign.id)
        eligibleCampaignIDs.remove(campaign.id)
        clearActivePresentation(for: campaign)
        revision += 1
    }

    private func decision(
        for campaign: PromotionCampaign,
        placement: PromotionPlacement,
        date: Date,
        persistExpiration: Bool
    ) -> PromotionDecision {
        guard PromotionPolicy.supports(placement, for: campaign.kind) else {
            return .hidden(.unsupportedPlacement)
        }

        var state = store.state(for: campaign.id)
        switch state.terminalState {
        case .converted:
            return .hidden(.converted)
        case .expired:
            return .hidden(.expired)
        case nil:
            break
        }

        if let expiresAt = state.expiresAt, date >= expiresAt {
            if persistExpiration {
                state.terminalState = .expired
                store.update(campaignID: campaign.id) { $0 = state }
                track(.expired, campaign: campaign, placement: nil, date: date)
            }
            return .hidden(.expired)
        }

        if let activeInterruptiveCampaignID {
            if activeInterruptiveCampaignID == campaign.id,
               placement == .launchModal {
                return .present
            }
            return .hidden(.anotherPlacementActive)
        }

        if placement == .launchModal, state.lastLaunchPresentedAt == nil {
            guard let firstLaunchRegisteredAt = store.firstLaunchRegisteredAt else {
                return .hidden(.initialCooldown)
            }
            guard date.timeIntervalSince(firstLaunchRegisteredAt)
                >= PromotionPolicy.standardPaywallCooldown else {
                return .hidden(.initialCooldown)
            }
        }

        switch campaign.kind {
        case .standardPaywall:
            guard let lastLaunchPresentedAt = state.lastLaunchPresentedAt else {
                return .present
            }
            return date.timeIntervalSince(lastLaunchPresentedAt)
                >= PromotionPolicy.standardPaywallCooldown
                ? .present
                : .hidden(.cooldown)

        case .exclusiveOffer:
            if placement == .launchModal,
               state.presentedPlacements.contains(.launchModal) {
                return .hidden(.alreadyPresented)
            }
            return .present
        }
    }

    private func track(
        _ name: PromotionEventName,
        campaign: PromotionCampaign,
        placement: PromotionPlacement?,
        date: Date? = nil
    ) {
        tracker.track(
            PromotionEvent(
                name: name,
                campaign: campaign,
                placement: placement,
                date: date ?? now()
            )
        )
    }

    private func clearActivePresentation(for campaign: PromotionCampaign) {
        if activeInterruptiveCampaignID == campaign.id {
            activeInterruptiveCampaignID = nil
        }
    }

    private func ensureLaunchRegistered(at date: Date) {
        let registrationDate = store.earliestLaunchPresentationAt.map {
            min($0, date)
        } ?? date
        let existing = store.firstLaunchRegisteredAt
        store.registerFirstLaunch(noLaterThan: registrationDate)
        if existing != store.firstLaunchRegisteredAt {
            revision += 1
        }
    }
}
