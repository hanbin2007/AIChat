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
                Label { Text("新对话") } icon: { Image("StartNewChat").resizable().scaledToFit() }
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
                        Text("新对话")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Text("一键打开 AIChat")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
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
        .configurationDisplayName("新对话")
        .description("一键进入 AIChat 并开始一条新会话。")
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
