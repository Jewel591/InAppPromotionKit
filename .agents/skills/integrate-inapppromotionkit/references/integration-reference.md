# InAppPromotionKit integration reference

Verify names against the package's current source before relying on them — the Kit evolves after this reference is written.

## Fixed policies (Kit-owned, not configurable)

| Policy | Value | Applies to |
|---|---|---|
| First-launch quiet period | 24 hours from the first `registerLaunch()`; install-level, not configurable | every `.launchModal` campaign |
| Standard paywall cooldown | 24 hours since the last `.launchModal` impression | `.standardPaywall` |
| Exclusive offer duration | 72 hours from the **first real impression** at any placement | `.exclusiveOffer` |
| Urgency threshold | remaining time ≤ 6 hours → `PromotionUrgency.urgent` | countdown surfaces |
| Placement support | `.standardPaywall` → `.launchModal` only; `.exclusiveOffer` → all three placements | `evaluate` / `snapshot` |
| Launch modal repeat | an exclusive offer's `.launchModal` shows once; later launches rely on badge/banner | `.exclusiveOffer` |
| Interruptive exclusivity | while a launch modal or opened paywall is active, other placements hide with `.anotherPlacementActive` | all campaigns |

Terminal states: `markConverted` and expiration each permanently hide every placement for that campaign ID. `reset(_:)` erases a campaign's state entirely — debug/QA use only. It deliberately does not clear the install-level first-launch quiet period.

## Storage layout (Kit-owned)

Campaign state and the install-level launch gate persist under package-owned UserDefaults keys:

| Key | Content |
|---|---|
| `InAppPromotionKit.campaignStates.v1` | `[campaignID: {firstPresentedAt, expiresAt, lastLaunchPresentedAt, presentedPlacements, terminalState}]` |
| `InAppPromotionKit.firstLaunchRegisteredAt.v1` | first app-launch timestamp used by the fixed 24-hour launch-modal quiet period |

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

After the one-time legacy import below, register every app launch at composition startup:

```swift
InAppPromotionController.shared.registerLaunch()
```

The call is idempotent. `evaluate` records a launch defensively if this hook was missed, but that starts the 24-hour clock late and is not a valid replacement. Badge/banner evaluation and `snapshot` never register a launch.

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

Only confirmed non-members are `.eligible`. Grace-period access remains premium. When an entitlement refresh changes a visible launch promotion to `.ineligible` or `.unavailable`, dismiss the host-owned cover and ask the surface coordinator to arbitrate again.

With async eligibility, conform to `PromotionEligibilityProviding` and use the `evaluate(_:for:using:)` overload; concurrent evaluations of the same campaign return `.hidden(.evaluationInProgress)`.

`snapshot(for:placement:)` answers `.ineligible` until `evaluate` has run for that campaign in the current process — evaluate once per launch before rendering badges or banners, and **re-evaluate whenever an eligibility input changes** (entitlement resolves, offering loads, purchase/restore completes). A `.unavailable` result is not retried by the Kit; without a fresh `evaluate` the campaign stays hidden for the whole process.

## Impressions and funnel events

```swift
// Only after the destination is actually visible:
controller.markPresented(campaign, at: .launchModal)

// When the app opens its full paywall for this campaign:
controller.markPaywallOpened(campaign, from: .floatingBadge)

// On successful purchase (terminal; also releases the interruptive lock):
controller.markConverted(campaign) // only when conversion came through this campaign

// When the paywall closes WITHOUT a purchase — release the interruptive lock,
// or every other placement reports .anotherPlacementActive until process exit.
// Side effect: this also emits a dismiss event with placement fixed to
// .launchModal (even for badge/banner-originated paywalls), and can double up
// with PromotionLaunchOffer's own on-disappear dismiss — account for it in
// funnel analysis:
controller.markDismissed(campaign, at: .launchModal)
```

The first `markPresented` of an `.exclusiveOffer` starts the 72-hour clock. Calling it before real visibility (eligibility check, prefetch, hidden view) silently burns the campaign window.

The bundled SwiftUI surfaces call `markPresented` (on appear) and `markClicked` (on action) internally; `PromotionLaunchOffer` additionally calls `markDismissed` on disappear — `PromotionFloatingBadge` and `PromotionSettingsBanner` do not. When using them, the app wires `markPaywallOpened`, `markConverted`, and the unconverted-close `markDismissed(_:at: .launchModal)` release shown above.

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

On an existing install, import the old timestamp once before `registerLaunch()` and the first `evaluate`:

```swift
// Example legacy key: an app-local "launch paywall last shown" date.
let legacyDate = UserDefaults.standard.object(forKey: "launchPaywallLastShownDate") as? Date
InAppPromotionController.shared.importLegacyLaunchPresentationDate(
    legacyDate,
    for: PromotionCampaigns.standardPaywall
)
InAppPromotionController.shared.registerLaunch()
```

The import is idempotent and also backdates the install gate when needed, regardless of whether registration accidentally happened first. Existing Kit launch-presentation evidence similarly prevents a second initial wait. With neither Kit evidence nor a legacy date, an upgraded install starts one 24-hour quiet period from its first launch on the new build. Keep the legacy key literal only inside the one-time migration; delete the type that owned it. If a hand-written throttle around the same prompt was already migrated to AppContextKit's `Throttle`, remove that duplicate — a launch paywall gated by this Kit does not also need an app-side throttle.

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

Event semantics: `eligible` fires at the start of each continuous eligible stretch — an `.ineligible` or `.unavailable` evaluation clears the dedup mark, so re-evaluating back to eligible emits it again; `impression` fires per presentation for `.standardPaywall` and once per placement for `.exclusiveOffer`; `expired` fires when expiration is first observed. Do not duplicate these from app code.

## Testing consumers

```swift
let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
let controller = InAppPromotionController(userDefaults: suite)
```

Time injection (`now:`) is internal to the package's own tests; host-app tests isolate through the UserDefaults suite and drive state via the public API (`evaluate` → `markPresented` → assertions on `snapshot`). Never use `.standard` or `InAppPromotionController.shared` in tests. Exact time-boundary behavior (cooldown edge, expiration edge) is covered by the package's own test suite — do not re-test Kit policy from the app; test the app's eligibility mapping and event wiring instead.
