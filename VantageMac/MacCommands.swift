import SwiftUI

/// What the menu-bar commands can do in the frontmost main window. Published by
/// MacContentView via `focusedSceneValue`, so the menu items are enabled only while a
/// main window is key (not, say, when the Trip Planner or Help window is in front).
struct MacCommandActions {
    var addLocation: () -> Void
    var importFromFile: () -> Void
    var importViaAI: () -> Void
    var manageTrips: () -> Void
    /// nil when there are no trips yet — the menu item disables instead of doing nothing.
    var planTripDay: (() -> Void)?
    var gearLibrary: () -> Void
}

extension FocusedValues {
    @Entry var macCommandActions: MacCommandActions?
}

/// Menu bar: File gets the ways to add spots, a Trips menu gets trip management and
/// the planner, and Help opens the in-app help window instead of macOS's default
/// "Help isn't available" alert.
struct MacCommands: Commands {
    @FocusedValue(\.macCommandActions) private var actions
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // Replaces "New Window" — one main window is all this app needs.
        CommandGroup(replacing: .newItem) {
            Button("New Spot…") { actions?.addLocation() }
                .keyboardShortcut("n")
                .disabled(actions == nil)
            Divider()
            Button("Import from File…") { actions?.importFromFile() }
                .keyboardShortcut("o")
                .disabled(actions == nil)
            Button("Import via AI Chat…") { actions?.importViaAI() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(actions == nil)
        }

        CommandMenu("Trips") {
            Button("Manage Trips…") { actions?.manageTrips() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(actions == nil)
            Button("Plan Trip Day…") { actions?.planTripDay?() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(actions?.planTripDay == nil)
            Divider()
            Button("Gear Library…") { actions?.gearLibrary() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(actions == nil)
        }

        CommandGroup(replacing: .help) {
            Button("Photo Point Help") { openWindow(id: MacHelpView.windowID) }
                .keyboardShortcut("?", modifiers: .command)
        }
    }
}
