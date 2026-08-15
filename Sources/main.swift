import AppKit

// Entry point. `.accessory` keeps the app out of the Dock and the app switcher — it lives
// in the menu bar only, which is also what LSUIElement in Info.plist declares.
let application = NSApplication.shared
let delegate = AppDelegate()

application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
