import SwiftUI

public struct PromotionSettingsBannerConfiguration {
    public let content: PromotionContent
    public let remainingTime: TimeInterval?
    public let urgency: PromotionUrgency
}

@MainActor
public protocol PromotionSettingsBannerStyle {
    associatedtype Body: View

    @ViewBuilder
    func makeBody(
        configuration: PromotionSettingsBannerConfiguration,
        action: @escaping @MainActor () -> Void
    ) -> Body
}

public struct StandardPromotionSettingsBannerStyle: PromotionSettingsBannerStyle {
    public init() {}

    public func makeBody(
        configuration: PromotionSettingsBannerConfiguration,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: "gift.fill")
                VStack(alignment: .leading) {
                    Text(configuration.content.title)
                        .font(.headline)
                    if let subtitle = configuration.content.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let remainingTime = configuration.remainingTime {
                    Text(PromotionCountdownFormatter.string(from: remainingTime))
                        .font(.caption.monospacedDigit())
                }
                Image(systemName: "chevron.right")
            }
        }
        .buttonStyle(.bordered)
    }
}

@MainActor
public struct PromotionSettingsBanner<Style: PromotionSettingsBannerStyle>: View {
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
                placement: .settingsBanner,
                at: context.date
            )
            if snapshot.isVisible {
                style.makeBody(
                    configuration: PromotionSettingsBannerConfiguration(
                        content: content,
                        remainingTime: snapshot.remainingTime,
                        urgency: snapshot.urgency
                    )
                ) {
                    controller.markClicked(campaign, at: .settingsBanner)
                    action()
                }
                .onAppear {
                    controller.markPresented(campaign, at: .settingsBanner)
                }
            }
        }
    }
}

public extension PromotionSettingsBanner where Style == StandardPromotionSettingsBannerStyle {
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
            style: StandardPromotionSettingsBannerStyle(),
            action: action
        )
    }
}
