import UserNotifications

/// One-way informational notices.
enum Notifier {
    /// Posts only if notifications were already allowed. This deliberately never asks for
    /// permission: a system prompt appearing because the battery got low would be absurd,
    /// and the menu bar icon already carries the state either way.
    static func postIfAllowed(title: String, body: String, identifier: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(identifier: identifier,
                                             content: content,
                                             trigger: nil))
        }
    }
}
