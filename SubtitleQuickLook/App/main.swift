import AppKit

@main
private enum SubtitleQuickLookHost {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = SubtitleQuickLookAppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
