# InAppPromotionKit

Public Swift Package for consistent in-app promotion behavior across Apple-platform apps.

## Product boundary

- The package owns campaign state, persistence, fixed display policies, countdown behavior,
  placement coordination, event semantics, and optional SwiftUI surfaces.
- Host apps own eligibility facts, products and prices, purchase logic, analytics backends,
  navigation/presentation coordination, brand content, and full paywalls.
- Fixed policies are intentionally not exposed as arbitrary numeric configuration. Add a
  semantic campaign kind when a genuinely different cross-product policy is approved.
- Custom UI is supplied through small placement-specific Style protocols. Styles may replace
  rendering, but state transitions and event recording remain package-owned.

## Engineering

- Swift 6 strict concurrency.
- Public API supports iOS 17, macOS 14, and visionOS 1.
- Every state-machine change requires focused unit tests, including exact time boundaries.
- Do not add a dependency on RevenueCat, StoreKit product identifiers, or a host app's sheet
  coordinator.
- Use semantic SwiftUI text styles and system controls in the standard UI.
