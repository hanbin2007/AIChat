import SwiftUI
import WidgetKit

private enum AIChatWatchWidgetLink {
    static let newConversationURL = URL(string: "aichat://conversation/new")!
}

private struct NewConversationEntry: TimelineEntry {
    let date: Date
}

private struct NewConversationTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> NewConversationEntry {
        NewConversationEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (NewConversationEntry) -> Void) {
        completion(NewConversationEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NewConversationEntry>) -> Void) {
        completion(
            Timeline(
                entries: [NewConversationEntry(date: .now)],
                policy: .never
            )
        )
    }
}

private struct NewConversationWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    Circle()
                        .fill(Color.cyan.opacity(0.2))
                    Image("StartNewChat")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                }
            case .accessoryInline:
                // TODO(L10n): widget target does not yet include `Shared Licensing/L10n.swift`
                // or `Localizable.strings`. Use `NSLocalizedString` keyed strings once the
                // bundle includes the strings table; `widget.new_conversation.*` keys are
                // already defined in `Shared Licensing/{en,zh-Hans}.lproj/Localizable.strings`.
                Label { Text(NSLocalizedString("widget.new_conversation.title", value: "新对话", comment: "")) } icon: { Image("StartNewChat").resizable().scaledToFit() }
            default:
                HStack(spacing: 10) {
                    Image("StartNewChat")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.cyan.opacity(0.18))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("widget.new_conversation.title", value: "新对话", comment: ""))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Text(NSLocalizedString("widget.new_conversation.subtitle", value: "一键打开 AIChat", comment: ""))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        // TODO(activation): when watch is in read-only mode, deep link should land
        // on the activation prompt instead of silently doing nothing. Requires
        // changes in `ChatStore.handleDeepLink` (out of this PR's scope).
        .widgetURL(AIChatWatchWidgetLink.newConversationURL)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct AIChatNewConversationWidget: Widget {
    let kind = "AIChatNewConversationWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: NewConversationTimelineProvider()
        ) { _ in
            NewConversationWidgetView()
        }
        .configurationDisplayName(NSLocalizedString("widget.new_conversation.display_name", value: "新对话", comment: ""))
        .description(NSLocalizedString("widget.new_conversation.description", value: "一键进入 AIChat 并开始一条新会话。", comment: ""))
        .supportedFamilies([
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}

@main
struct AIChatWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        AIChatNewConversationWidget()
    }
}
