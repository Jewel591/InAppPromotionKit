import SwiftUI

public struct PromotionLaunchOfferConfiguration {
    public let content: PromotionContent
    public let remainingTime: TimeInterval?
    public let urgency: PromotionUrgency
}

@MainActor
public protocol PromotionLaunchOfferStyle {
    associatedtype Body: View

    @ViewBuilder
    func makeBody(
        configuration: PromotionLaunchOfferConfiguration,
        action: @escaping @MainActor () -> Void
    ) -> Body
}

public struct StandardPromotionLaunchOfferStyle: PromotionLaunchOfferStyle {
    public init() {}

    public func makeBody(
        configuration: PromotionLaunchOfferConfiguration,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        VStack {
            Image(systemName: "gift.fill")
                .font(.largeTitle)
            Text(configuration.content.title)
                .font(.title2)
                .multilineTextAlignment(.center)
            if let subtitle = configuration.content.subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let remainingTime = configuration.remainingTime {
                Text(PromotionCountdownFormatter.string(from: remainingTime))
                    .font(.title3.monospacedDigit())
            }
            Button(configuration.content.callToAction, action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

@MainActor
public struct PromotionLaunchOffer<Style: PromotionLaunchOfferStyle>: View {
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
                placement: .launchModal,
                at: context.date
            )
            if snapshot.isVisible {
                style.makeBody(
                    configuration: PromotionLaunchOfferConfiguration(
                        content: content,
                        remainingTime: snapshot.remainingTime,
                        urgency: snapshot.urgency
                    )
                ) {
                    controller.markClicked(campaign, at: .launchModal)
                    action()
                }
                .onAppear {
                    controller.markPresented(campaign, at: .launchModal)
                }
                .onDisappear {
                    controller.markDismissed(campaign, at: .launchModal)
                }
            }
        }
    }
}

public extension PromotionLaunchOffer where Style == StandardPromotionLaunchOfferStyle {
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
            style: StandardPromotionLaunchOfferStyle(),
            action: action
        )
    }
}
