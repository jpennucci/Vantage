import SwiftUI
import WidgetKit

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
    var body: some View {
        Button(intent: SaveSpotIntent()) {
            Image(systemName: "mappin.circle.fill")
        }
    }
}

struct CaptureWidget: Widget {
    let kind = "CaptureWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CaptureWidgetProvider()) { _ in
            CaptureWidgetView()
        }
        .configurationDisplayName("Save Spot")
        .description("One-tap capture from the Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}
