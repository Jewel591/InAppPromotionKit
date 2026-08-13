import SwiftUI

public struct PromotionContent {
    public let title: LocalizedStringKey
    public let subtitle: LocalizedStringKey?
    public let callToAction: LocalizedStringKey

    public init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        callToAction: LocalizedStringKey
    ) {
        self.title = title
        self.subtitle = subtitle
        self.callToAction = callToAction
    }
}
