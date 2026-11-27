import AppIntents

// Ready-made shortcuts that appear under WrapPin in the Shortcuts app, Spotlight
// and Siri without any setup. Chinese phrases are in AppShortcuts.strings.
struct WrapPinShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartFavouriteSimulationIntent(),
            phrases: [
                "Simulate a favourite with \(.applicationName)",
                "Simulate \(\.$place) with \(.applicationName)"
            ],
            shortTitle: "Simulate Favourite",
            systemImageName: "mappin.and.ellipse"
        )
        AppShortcut(
            intent: RestoreRealLocationIntent(),
            phrases: [
                "Restore my real location with \(.applicationName)",
                "Stop \(.applicationName) simulation"
            ],
            shortTitle: "Restore Real Location",
            systemImageName: "location.slash"
        )
        AppShortcut(
            intent: RunLocationScheduleIntent(),
            phrases: [
                "Run the \(.applicationName) schedule",
                "Apply my \(.applicationName) schedule"
            ],
            shortTitle: "Run Schedule",
            systemImageName: "calendar.badge.clock"
        )
        AppShortcut(
            intent: KeepWrapPinAliveIntent(),
            phrases: [
                "Keep \(.applicationName) alive",
                "Wake up \(.applicationName)"
            ],
            shortTitle: "Keep Alive",
            systemImageName: "bolt.heart"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .blue
}
