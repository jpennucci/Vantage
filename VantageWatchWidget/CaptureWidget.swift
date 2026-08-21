import SwiftUI
import WidgetKit

/// Watch face complication — the spec's "single tap on the watch face captures
/// location instantly" goal, larger target and more glanceable than opening the app.
///
/// Deliberately does NOT use `Button(intent:)` here — that's a documented watchOS
/// platform bug (confirmed via Apple Developer Forums reports matching this exact
/// symptom): interactive AppIntent buttons work fine in the widget gallery/Smart
/// Stack preview but silently do nothing when the widget is actually placed as a
/// watch face complication. Verified directly on-device: the gallery preview showed
/// the correct "Save Spot" widget, but tapping the placed complication produced no
/// haptic, no app launch, and no trace in app-side debug logging — while a full
/// uninstall/reboot/re-add cycle ruled out caching as the cause. Using `widgetURL`
/// instead falls back to plain tap-to-open-app, which is a long-supported, reliable
/// complication mechanism; `WatchCaptureView`'s `onOpenURL` then triggers the same
/// `CaptureAndSaveUseCase` capture immediately on launch, so the user still gets a
/// single-tap capture, just via app launch rather than a background intent run.
struct CaptureWidgetEntry: TimelineEntry {
    let date: Date
}

struct CaptureWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaptureWidgetEntry {
        CaptureWidgetEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (CaptureWidgetEntry) -> Void) {
        completion(CaptureWidgetEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CaptureWidgetEntry>) -> Void) {
        completion(Timeline(entries: [CaptureWidgetEntry(date: .now)], policy: .never))
    }
}

struct CaptureWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label("Save Spot", systemImage: "mappin.circle.fill")
            case .accessoryRectangular:
                Label("Save This Spot", systemImage: "mappin.circle.fill")
            default:
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 28))
            }
        }
        // Most watch faces render complications in a single face-controlled accent
        // color regardless of what an app specifies — that's a deliberate watchOS
        // constraint so every complication on a face looks consistent, not something
        // an app can override. This only takes visible effect on faces/contexts that
        // actually support full-color complications; on faces like Modular/Wayfinder
        // that force a monochrome accent, this has no effect and that's expected.
        .foregroundStyle(AppTheme.cobalt)
        .containerBackground(.clear, for: .widget)
        .widgetURL(URL(string: "vantagewatch://capture"))
    }
}

struct CaptureWidget: Widget {
    let kind = "CaptureWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CaptureWidgetProvider()) { _ in
            CaptureWidgetView()
        }
        .configurationDisplayName("Save Spot")
        .description("One-tap capture from your watch face.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}
