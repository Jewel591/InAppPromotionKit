import SwiftUI

public struct PromotionFloatingBadgeConfiguration {
    public let content: PromotionContent
    public let remainingTime: TimeInterval?
    public let urgency: PromotionUrgency
}

@MainActor
public protocol PromotionFloatingBadgeStyle {
    associatedtype Body: View

    @ViewBuilder
    func makeBody(
        configuration: PromotionFloatingBadgeConfiguration,
        action: @escaping @MainActor () -> Void
    ) -> Body
}

public struct StandardPromotionFloatingBadgeStyle: PromotionFloatingBadgeStyle {
    public init() {}

    public func makeBody(
        configuration: PromotionFloatingBadgeConfiguration,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: "gift.fill")
                VStack(alignment: .leading) {
                    Text(configuration.content.title)
                        .font(.headline)
                    if let remainingTime = configuration.remainingTime {
                        Text(PromotionCountdownFormatter.string(from: remainingTime))
                            .font(.caption.monospacedDigit())
                    }
                }
            }
        }
        .buttonStyle(.borderedProminent)
    }
}

@MainActor
public struct PromotionFloatingBadge<Style: PromotionFloatingBadgeStyle>: View {
    private let campaign: PromotionCampaign
    private let content: PromotionContent
    private let controller: InAppPromotionController
    private let style: Style
    private let action: @MainActor () -> Void

    public init(
        campaign: PromotionCampaign,
        content: PromotionContent,
        controller: InAppPromotionController = .shared,
        style: Style,
        action: @escaping @MainActor () -> Void
    ) {
        self.campaign = campaign
        self.content = content
        self.controller = controller
        self.style = style
        self.action = action
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let _ = controller.revision
            let snapshot = controller.snapshot(
                for: campaign,
                placement: .floatingBadge,
                at: context.date
            )
            if snapshot.isVisible {
                style.makeBody(
                    configuration: PromotionFloatingBadgeConfiguration(
                        content: content,
                        remainingTime: snapshot.remainingTime,
                        urgency: snapshot.urgency
                    )
                ) {
                    controller.markClicked(campaign, at: .floatingBadge)
                    action()
                }
                .onAppear {
                    controller.markPresented(campaign, at: .floatingBadge)
                }
            }
        }
    }
}

public extension PromotionFloatingBadge where Style == StandardPromotionFloatingBadgeStyle {
    init(
        campaign: PromotionCampaign,
        content: PromotionContent,
        controller: InAppPromotionController = .shared,
        action: @escaping @MainActor () -> Void
    ) {
        self.init(
            campaign: campaign,
            content: content,
            controller: controller,
            style: StandardPromotionFloatingBadgeStyle(),
            action: action
        )
    }
}
