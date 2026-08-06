import SwiftUI
import AppKit

public struct EmptyStateView: View {
    public let imageName: String
    public let title: String
    public let subtitle: String
    public let primaryActionTitle: String?
    public let primaryActionIcon: String?
    public let primaryAction: (() -> Void)?
    public let hintText: String?

    public init(
        imageName: String,
        title: String,
        subtitle: String,
        primaryActionTitle: String? = nil,
        primaryActionIcon: String? = nil,
        primaryAction: (() -> Void)? = nil,
        hintText: String? = nil
    ) {
        self.imageName = imageName
        self.title = title
        self.subtitle = subtitle
        self.primaryActionTitle = primaryActionTitle
        self.primaryActionIcon = primaryActionIcon
        self.primaryAction = primaryAction
        self.hintText = hintText
    }

    public var body: some View {
        VStack(spacing: 16) {
            Spacer()

            if let url = Bundle.module.url(forResource: imageName, withExtension: "jpg"),
               let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 220, maxHeight: 220)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            if let primaryActionTitle = primaryActionTitle, let primaryAction = primaryAction {
                Button(action: primaryAction) {
                    HStack(spacing: 6) {
                        if let icon = primaryActionIcon {
                            Image(systemName: icon)
                        }
                        Text(primaryActionTitle)
                    }
                    .padding(.horizontal, 6)
                }
                .focusable(false)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if let hintText = hintText {
                Text(hintText)
                    .font(.caption)
                    .monospaced()
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
