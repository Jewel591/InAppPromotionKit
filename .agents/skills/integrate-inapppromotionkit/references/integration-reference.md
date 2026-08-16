# InAppPromotionKit integration reference

Verify names against the package's current source before relying on them — the Kit evolves after this reference is written.

## Fixed policies (Kit-owned, not configurable)

| Policy | Value | Applies to |
|---|---|---|
| Standard paywall cooldown | 24 hours since the last `.launchModal` impression | `.standardPaywall` |
| Exclusive offer duration | 72 hours from the **first real impression** at any placement | `.exclusiveOffer` |
| Urgency threshold | remaining time ≤ 6 hours → `PromotionUrgency.urgent` | countdown surfaces |
| Placement support | `.standardPaywall` → `.launchModal` only; `.exclusiveOffer` → all three placements | `evaluate` / `snapshot` |
| Launch modal repeat | an exclusive offer's `.launchModal` shows once; later launches rely on badge/banner | `.exclusiveOffer` |
| Interruptive exclusivity | while a launch modal or opened paywall is active, other placements hide with `.anotherPlacementActive` | all campaigns |

Terminal states: `markConverted` and expiration each permanently hide every placement for that campaign ID. `reset(_:)` erases a campaign's state entirely — debug/QA use only.

## Storage layout (Kit-owned)

All campaign state persists as one JSON blob under a single UserDefaults key:

| Key | Content |
|---|---|
| `InAppPromotionKit.campaignStates.v1` | `[campaignID: {firstPresentedAt, expiresAt, lastLaunchPresentedAt, presentedPlacements, terminalState}]` |

Never write this key directly. State survives launches and app upgrades through `UserDefaults`, but not app deletion.

## Composition-level setup

```swift
import InAppPromotionKit

enum PromotionCampaigns {
    static let standardPaywall = PromotionCampaign(
        id: "standard-paywall-v1",
        kind: .standardPaywall
    )
    static let exclusiveOffer = PromotionCampaign(
        id: "exclusive-offer-2026q3",   // versioned: a new campaign = a new ID
        kind: .exclusiveOffer
    )
}
```

Use `InAppPromotionController.shared` in app code. Construct `InAppPromotionController(userDefaults:tracker:)` yourself only for tests or to attach an analytics tracker at composition level.

## Gating a launch prompt

```swift
let decision = InAppPromotionController.shared.evaluate(
    PromotionCampaigns.standardPaywall,
    for: .launchModal,
    eligibility: isPremium ? .ineligible : .eligible
)
if decision == .present {
    // Enqueue through the app's surface coordinator; the Kit presents nothing itself.
    presentHostPaywall()
}
```

Eligibility mapping rules:

- Premium / already entitled → `.ineligible`
- Entitlement or offering state unknown right now → `.unavailable` (never `.eligible`)
- May purchase → `.eligible`

With async eligibility, conform to `PromotionEligibilityProviding` and use the `evaluate(_:for:using:)` overload; concurrent evaluations of the same campaign return `.hidden(.evaluationInProgress)`.

`snapshot(for:placement:)` answers `.ineligible` until `evaluate` has run for that campaign in the current process — evaluate once per launch before rendering badges or banners.

## Impressions and funnel events

```swift
// Only after the destination is actually visible:
controller.markPresented(campaign, at: .launchModal)

// When the app opens its full paywall for this campaign:
controller.markPaywallOpened(campaign, from: .floatingBadge)

// On successful purchase (terminal):
controller.markConverted(campaign)
```

The first `markPresented` of an `.exclusiveOffer` starts the 72-hour clock. Calling it before real visibility (eligibility check, prefetch, hidden view) silently burns the campaign window.

The bundled SwiftUI surfaces call `markPresented` / `markClicked` / `markDismissed` internally via `onAppear` / action / `onDisappear`. When using them, the app wires only `markPaywallOpened` and `markConverted`.

## Bundled surfaces and custom Styles

```swift
PromotionFloatingBadge(
    campaign: PromotionCampaigns.exclusiveOffer,
    content: PromotionContent(
        title: "72-hour launch offer",        // LocalizedStringKey — host catalog localizes
        subtitle: "50% off your first year",
        callToAction: "Claim offer"
    ),
    style: MyFloatingBadgeStyle()
) {
    openOffer()
}
```

Each surface hides itself when the snapshot is not visible and ticks its countdown once per second. A custom Style implements one placement protocol:

```swift
struct MyFloatingBadgeStyle: PromotionFloatingBadgeStyle {
    func makeBody(
        configuration: PromotionFloatingBadgeConfiguration,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            // configuration.content, configuration.remainingTime, configuration.urgency
        }
    }
}
```

Styles replace rendering only. Do not re-derive expiration, cooldown, or visibility inside a Style; render from the configuration values. For visual direction on paywalls, settings banners, and launch offers, see the private [screenstudies](https://github.com/Jewel591/screenstudies) reference library (`Screens/Paywall/…`).

## Legacy migration

On an existing install the Kit's state is empty, so a `.standardPaywall` campaign presents immediately after the update even if the app showed its old prompt an hour ago. Import the old timestamp once, before the first `evaluate`:

```swift
// Example legacy key: an app-local "launch paywall last shown" date.
let legacyDate = UserDefaults.standard.object(forKey: "launchPaywallLastShownDate") as? Date
InAppPromotionController.shared.importLegacyLaunchPresentationDate(
    legacyDate,
    for: PromotionCampaigns.standardPaywall
)
```

The import is idempotent: it does nothing when the campaign already has a launch-presentation date. Keep the legacy key literal only inside the migration; delete the type that owned it. If a hand-written throttle around the same prompt was already migrated to AppContextKit's `Throttle`, pick one owner — a launch paywall gated by this Kit does not also need an app-side throttle.

## Analytics

```swift
final class PromotionAnalyticsBridge: PromotionEventTracking {
    func track(_ event: PromotionEvent) {
        analytics.log(event.name.rawValue, [
            "campaign": event.campaign.id,
            "placement": event.placement?.rawValue ?? "none",
        ])
    }
}

let controller = InAppPromotionController(tracker: PromotionAnalyticsBridge())
```

Event semantics: `eligible` fires once per process when a campaign first evaluates eligible; `impression` fires per presentation for `.standardPaywall` and once per placement for `.exclusiveOffer`; `expired` fires when expiration is first observed. Do not duplicate these from app code.

## Testing consumers

```swift
let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
let controller = InAppPromotionController(userDefaults: suite)
```

Time injection (`now:`) is internal to the package's own tests; host-app tests isolate through the UserDefaults suite and drive state via the public API (`evaluate` → `markPresented` → assertions on `snapshot`). Never use `.standard` or `InAppPromotionController.shared` in tests. Exact time-boundary behavior (cooldown edge, expiration edge) is covered by the package's own test suite — do not re-test Kit policy from the app; test the app's eligibility mapping and event wiring instead.
