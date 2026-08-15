import AppKit

/// Alert plumbing, kept out of the controllers.
enum Alerts {
    static func show(title: String, text: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: L("alert.ok", "OK"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// Runs a modal with several buttons and returns the index of the one pressed.
    ///
    /// `NSAlert` only names the first three responses; further buttons continue
    /// sequentially from the same base, so the index is the honest way to read the answer
    /// once there are four of them.
    static func choose(title: String, text: String, buttons: [String]) -> Int {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = text
        for button in buttons {
            alert.addButton(withTitle: button)
        }
        NSApp.activate(ignoringOtherApps: true)

        let response = alert.runModal().rawValue
        return response - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
    }
}
