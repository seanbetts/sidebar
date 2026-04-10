#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit
import sideBarShared

struct IngestionProgressLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: IngestionProgressActivityAttributes.self) { context in
            IngestionProgressLiveActivityView(context: context)
                .activityBackgroundTint(Color(.systemBackground))
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "doc.badge.gearshape")
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let progress = context.state.progress {
                        Text(progress.formatted(.percent.precision(.fractionLength(0))))
                            .font(.caption.monospacedDigit())
                    } else {
                        Text(context.state.statusText)
                            .font(.caption)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.attributes.displayName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(context.state.statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let progress = context.state.progress {
                        ProgressView(value: progress)
                    } else if let detailText = context.state.detailText {
                        Text(detailText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } compactLeading: {
                Image(systemName: "doc.badge.gearshape")
            } compactTrailing: {
                if let progress = context.state.progress {
                    Text(progress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption2.monospacedDigit())
                } else {
                    Image(systemName: iconName(for: context.state.status))
                }
            } minimal: {
                Image(systemName: iconName(for: context.state.status))
            }
        }
    }

    private func iconName(for status: String) -> String {
        switch status {
        case "completed":
            return "checkmark.circle.fill"
        case "failed":
            return "exclamationmark.triangle.fill"
        case "canceled":
            return "xmark.circle.fill"
        default:
            return "doc.badge.gearshape"
        }
    }
}

private struct IngestionProgressLiveActivityView: View {
    let context: ActivityViewContext<IngestionProgressActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "doc.badge.gearshape")
                    .font(.headline)
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(context.state.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let detailText = context.state.detailText {
                        Text(detailText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                if let progress = context.state.progress {
                    Text(progress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let progress = context.state.progress {
                ProgressView(value: progress)
            }
        }
        .padding()
    }
}
#endif
