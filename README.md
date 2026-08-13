# InAppPromotionKit

`InAppPromotionKit` is a public Swift Package for consistent in-app promotion behavior on
Apple platforms. It provides fixed campaign policies, durable state, event semantics, and
optional SwiftUI surfaces whose rendering can be replaced through placement-specific styles.

## Fixed policies

- `standardPaywall`: launch-only, with a fixed 24-hour cooldown.
- `exclusiveOffer`: a one-time 72-hour campaign supporting launch modal, floating badge, and
  settings banner placements.
- An exclusive offer starts its clock on the first real impression, not eligibility evaluation.
- Conversion and expiration are terminal for a campaign ID.
- Campaign state survives launches and app upgrades through `UserDefaults`, but not deletion.
- Only one interruptive promotion presentation can be active at a time.

Apps provide eligibility facts, campaign identity, content, navigation, products, purchase
logic, and analytics backends. The package intentionally has no RevenueCat dependency and does
not own a host app's paywall.

## Core usage

```swift
import InAppPromotionKit

let campaign = PromotionCampaign(
    id: "standard-paywall-v1",
    kind: .standardPaywall
)

let decision = InAppPromotionController.shared.evaluate(
    campaign,
    for: .launchModal,
    eligibility: isPremium ? .ineligible : .eligible
)

if decision == .present {
    presentHostPaywall()
}
```

Record an impression only after the destination is actually visible:

```swift
controller.markPresented(campaign, at: .launchModal)
```

## Optional SwiftUI

The package includes standard `PromotionFloatingBadge`, `PromotionSettingsBanner`, and
`PromotionLaunchOffer` surfaces. Each accepts a placement-specific Style implementation, so
apps can replace rendering without reimplementing campaign state transitions.

```swift
PromotionFloatingBadge(
    campaign: campaign,
    content: content,
    style: MyFloatingBadgeStyle()
) {
    openOffer()
}
```

## Requirements

- iOS 17+
- macOS 14+
- visionOS 1+
- Swift 6
