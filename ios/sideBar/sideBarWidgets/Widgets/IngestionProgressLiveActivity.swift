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
                    IngestionActivityBrandMark(status: context.state.status, size: 18)
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
                IngestionActivityBrandMark(status: context.state.status, size: 16)
            } compactTrailing: {
                if let progress = context.state.progress {
                    Text(progress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption2.monospacedDigit())
                } else {
                    IngestionActivityStatusGlyph(status: context.state.status)
                }
            } minimal: {
                IngestionActivityStatusGlyph(status: context.state.status)
            }
        }
    }
}

private struct IngestionProgressLiveActivityView: View {
    let context: ActivityViewContext<IngestionProgressActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                IngestionActivityBrandMark(status: context.state.status, size: 18)

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

private struct IngestionActivityBrandMark: View {
    let status: String
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image("AppLogo")
                .resizable()
                .widgetAccentedRenderingMode(.accentedDesaturated)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)

            if let badgeSymbol {
                Image(systemName: badgeSymbol)
                    .font(.system(size: badgeFontSize, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(badgePadding)
                    .background(badgeBackground, in: Circle())
                    .offset(x: badgeOffset, y: badgeOffset)
            }
        }
    }

    private var badgeSymbol: String? {
        switch status {
        case "failed":
            return "exclamationmark"
        case "canceled":
            return "xmark"
        default:
            return nil
        }
    }

    private var badgeBackground: Color {
        switch status {
        case "failed":
            return .orange
        case "canceled":
            return .secondary
        default:
            return .clear
        }
    }

    private var badgeFontSize: CGFloat {
        max(7, size * 0.36)
    }

    private var badgePadding: CGFloat {
        max(1.5, size * 0.08)
    }

    private var badgeOffset: CGFloat {
        max(1, size * 0.06)
    }
}

private struct IngestionActivityStatusGlyph: View {
    let status: String

    var body: some View {
        if let symbolName = symbolName {
            Image(systemName: symbolName)
                .foregroundStyle(symbolColor)
        } else {
            Image("AppLogo")
                .resizable()
                .widgetAccentedRenderingMode(.accentedDesaturated)
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
        }
    }

    private var symbolName: String? {
        switch status {
        case "uploading":
            return "arrow.up.circle.fill"
        case "queued":
            return "clock.fill"
        case "validating", "converting", "extracting":
            return "gearshape.fill"
        case "ai_md", "transcribing":
            return "pencil.line"
        case "thumb", "finalizing":
            return "tray.and.arrow.down.fill"
        case "ready":
            return "checkmark.circle.fill"
        case "failed":
            return "exclamationmark.triangle.fill"
        case "canceled":
            return "xmark.circle.fill"
        default:
            return nil
        }
    }

    private var symbolColor: Color {
        switch status {
        case "failed":
            return .orange
        case "canceled":
            return .secondary
        default:
            return .primary
        }
    }
}
#endif
