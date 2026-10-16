import SwiftUI

public struct SettingsSheet: View {
    @ObservedObject var store: PostStore
    @Environment(\.dismiss) private var dismiss

    public init(store: PostStore) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Preferences & Editor Settings", systemImage: "gearshape.fill")
                    .font(.headline)
                Spacer()
            }
            .padding(16)
            .background(.bar)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Editor Capabilities Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Multiline Code Editors")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)

                        settingCard(
                            title: "Enable Slash Commands (/json, /pretty, /uuid, /op, /vim)",
                            subtitle: "Type '/' at the start of any line in a payload editor to open the dynamic slash command bar. Press Tab or arrow keys to cycle pills and Enter/Space to insert.",
                            icon: "slash.circle.fill",
                            iconColor: .purple,
                            isOn: $store.enableSlashCommands
                        )

                        settingCard(
                            title: "Enable Vim Mode Support",
                            subtitle: "Displays the subtle ':_' watermark toggle in the bottom-right corner of multiline editors (and enables '/vim'). Text areas always start in standard editing mode (VIM=OFF) until toggled.",
                            icon: "terminal.fill",
                            iconColor: .green,
                            isOn: $store.enableVimEditor
                        )

                        settingCard(
                            title: "Enable Code Syntax Highlighting",
                            subtitle: "Applies dark syntax highlighting to JSON payloads, cURL snippets, {{environment}} variables, and op:// 1Password secret references.",
                            icon: "paintbrush.pointed.fill",
                            iconColor: .blue,
                            isOn: $store.enableSyntaxHighlighting
                        )
                    }

                    Divider()

                    // Quick Reference Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Available Slash Commands")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                            ForEach(SlashCommand.availableCommands(vimEnabled: store.enableVimEditor)) { cmd in
                                HStack(spacing: 6) {
                                    Text(cmd.trigger)
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.purple)
                                        .frame(width: 72, alignment: .leading)
                                    Text(cmd.description)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }
                .padding(16)
            }

            Divider()

            HStack {
                Button("Reset to Defaults") {
                    store.enableSlashCommands = true
                    store.enableVimEditor = true
                    store.enableSyntaxHighlighting = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .focusable(false)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .focusable(false)
            }
            .padding(14)
            .background(.bar)
        }
        .frame(width: 540, height: 470)
    }

    private func settingCard(
        title: String,
        subtitle: String,
        icon: String,
        iconColor: Color,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(iconColor)
                .frame(width: 24, height: 24)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
    }
}
