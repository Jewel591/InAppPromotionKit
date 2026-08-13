import Foundation
import Testing
@testable import InAppPromotionKit

@MainActor
struct InAppPromotionControllerTests {
    @Test
    func standardPaywallUsesFixedTwentyFourHourCooldown() throws {
        let fixture = try Fixture()
        let campaign = PromotionCampaign(id: "standard", kind: .standardPaywall)

        #expect(
            fixture.controller.evaluate(
                campaign,
                for: .launchModal,
                eligibility: .eligible
            ) == .present
        )
        fixture.controller.markPresented(campaign, at: .launchModal)
        fixture.controller.markDismissed(campaign, at: .launchModal)

        fixture.clock.date = fixture.clock.date.addingTimeInterval(24 * 60 * 60 - 1)
        #expect(
            fixture.controller.evaluate(
                campaign,
                for: .launchModal,
                eligibility: .eligible
            ) == .hidden(.cooldown)
        )

        fixture.clock.date = fixture.clock.date.addingTimeInterval(1)
        #expect(
            fixture.controller.evaluate(
                campaign,
                for: .launchModal,
                eligibility: .eligible
            ) == .present
        )
    }

    @Test
    func exclusiveOfferStartsSeventyTwoHourClockOnFirstRealImpression() throws {
        let fixture = try Fixture()
        let campaign = PromotionCampaign(id: "exclusive", kind: .exclusiveOffer)

        #expect(
            fixture.controller.evaluate(
                campaign,
                for: .floatingBadge,
                eligibility: .eligible
            ) == .present
        )
        #expect(
            fixture.controller.snapshot(
                for: campaign,
                placement: .floatingBadge
            ).remainingTime == nil
        )

        fixture.controller.markPresented(campaign, at: .floatingBadge)

        #expect(
            fixture.controller.snapshot(
                for: campaign,
                placement: .floatingBadge
            ).remainingTime == TimeInterval(72 * 60 * 60)
        )
    }

    @Test
    func exclusiveOfferLaunchIsOnceButPassivePlacementsRemainVisible() throws {
        let fixture = try Fixture()
        let campaign = PromotionCampaign(id: "exclusive", kind: .exclusiveOffer)

        _ = fixture.controller.evaluate(
            campaign,
            for: .launchModal,
            eligibility: .eligible
        )
        fixture.controller.markPresented(campaign, at: .launchModal)

        #expect(
            fixture.controller.snapshot(
                for: campaign,
                placement: .launchModal
            ).isVisible
        )
        #expect(
            fixture.controller.snapshot(
                for: campaign,
                placement: .floatingBadge
            ).hiddenReason == .anotherPlacementActive
        )

        fixture.controller.markDismissed(campaign, at: .launchModal)

        #expect(
            fixture.controller.evaluate(
                campaign,
                for: .launchModal,
                eligibility: .eligible
            ) == .hidden(.alreadyPresented)
        )
        #expect(
            fixture.controller.evaluate(
                campaign,
                for: .floatingBadge,
                eligibility: .eligible
            ) == .present
        )
        #expect(
            fixture.controller.evaluate(
                campaign,
                for: .settingsBanner,
                eligibility: .eligible
            ) == .present
        )
    }

    @Test
    func exclusiveOfferExpiresPermanentlyAtExactDeadline() throws {
        let fixture = try Fixture()
        let campaign = PromotionCampaign(id: "exclusive", kind: .exclusiveOffer)

        _ = fixture.controller.evaluate(
            campaign,
            for: .floatingBadge,
            eligibility: .eligible
        )
        fixture.controller.markPresented(campaign, at: .floatingBadge)
        fixture.clock.date = fixture.clock.date.addingTimeInterval(72 * 60 * 60)

        #expect(
            fixture.controller.evaluate(
                campaign,
                for: .floatingBadge,
                eligibility: .eligible
            ) == .hidden(.expired)
        )

        fixture.clock.date = fixture.clock.date.addingTimeInterval(-60 * 60)
        let relaunchedController = fixture.makeController()
        #expect(
            relaunchedController.evaluate(
                campaign,
                for: .floatingBadge,
                eligibility: .eligible
            ) == .hidden(.expired)
        )
    }

    @Test
    func unavailableEligibilityDoesNotStartCampaign() throws {
        let fixture = try Fixture()
        let campaign = PromotionCampaign(id: "exclusive", kind: .exclusiveOffer)

        #expect(
            fixture.controller.evaluate(
                campaign,
                for: .floatingBadge,
                eligibility: .unavailable
            ) == .hidden(.unavailable)
        )

        fixture.clock.date = fixture.clock.date.addingTimeInterval(30 * 24 * 60 * 60)
        #expect(
            fixture.controller.evaluate(
                campaign,
                for: .floatingBadge,
                eligibility: .eligible
            ) == .present
        )
        #expect(
            fixture.controller.snapshot(
                for: campaign,
                placement: .floatingBadge
            ).remainingTime == nil
        )
    }

    @Test
    func conversionEndsEveryPlacement() throws {
        let fixture = try Fixture()
        let campaign = PromotionCampaign(id: "exclusive", kind: .exclusiveOffer)

        _ = fixture.controller.evaluate(
            campaign,
            for: .floatingBadge,
            eligibility: .eligible
        )
        fixture.controller.markPresented(campaign, at: .floatingBadge)
        fixture.controller.markConverted(campaign)

        for placement in PromotionPlacement.allCases {
            #expect(
                fixture.controller.evaluate(
                    campaign,
                    for: placement,
                    eligibility: .eligible
                ) == .hidden(.converted)
            )
        }
    }

    @Test
    func legacyLaunchDatePreservesExistingCooldown() throws {
        let fixture = try Fixture()
        let campaign = PromotionCampaign(id: "standard", kind: .standardPaywall)
        let previousPresentation = fixture.clock.date.addingTimeInterval(-60 * 60)

        fixture.controller.importLegacyLaunchPresentationDate(
            previousPresentation,
            for: campaign
        )

        #expect(
            fixture.controller.evaluate(
                campaign,
                for: .launchModal,
                eligibility: .eligible
            ) == .hidden(.cooldown)
        )
    }
}

@MainActor
private final class Fixture {
    let defaults: UserDefaults
    let clock = TestClock(date: Date(timeIntervalSince1970: 1_800_000_000))
    lazy var controller = makeController()

    init() throws {
        let suiteName = "InAppPromotionKitTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    func makeController() -> InAppPromotionController {
        InAppPromotionController(
            userDefaults: defaults,
            now: { [clock] in clock.date }
        )
    }
}

@MainActor
private final class TestClock {
    var date: Date

    init(date: Date) {
        self.date = date
    }
}
