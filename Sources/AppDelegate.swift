import AppKit
import ServiceManagement

/// Lifecycle and the menu bar. Everything with substance lives elsewhere: `SleepMode`
/// owns the two power layers, `UpdateCoordinator` owns updates.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// macOS publishes no notification for `SleepDisabled`: the general IOKit interest
    /// notification on IOPMrootDomain does not fire for it, and IOPMLib exposes nothing
    /// public either. So the app polls — rarely — and puts accuracy where it is noticed:
    /// the menu re-syncs as it opens, and so does waking from sleep.
    private static let syncInterval: TimeInterval = 30

    private let mode = SleepMode()
    private let updates = UpdateCoordinator()
    private let powerSource = PowerSource()

    private var statusItem: NSStatusItem!
    private var syncTimer: Timer?
    private var sigtermSource: DispatchSourceSignal?
    private var isShowingMenu = false
    private var currentSymbol: String?

    /// Set once the battery guard has acted, so a mode it could not fully switch off does
    /// not produce the same notification on every power event.
    private var batteryGuardTripped = false

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        mode.adoptSystemState()
        refreshAppearance()

        if Preferences.enableAtLaunch && !mode.isOn {
            // No password dialog here — it would pop up at every login. If the quiet path
            // fails we stay in partial mode, and the icon says so.
            mode.set(true, askForPassword: false)
            refreshAppearance()
        }

        observeWorkspace()
        installSignalHandler()

        syncTimer = Timer.scheduledTimer(withTimeInterval: Self.syncInterval,
                                         repeats: true) { [weak self] _ in
            self?.syncWithSystem()
        }
        updates.start()
        powerSource.startObserving { [weak self] in self?.checkBattery() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        mode.relinquish(mayAskPassword: true)
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(systemDidWake),
                           name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(systemWillPowerOff),
                           name: NSWorkspace.willPowerOffNotification, object: nil)
    }

    @objc private func systemDidWake() {
        syncWithSystem()
    }

    @objc private func systemWillPowerOff() {
        // A modal password dialog would block the shutdown, so only the quiet path.
        mode.relinquish(mayAskPassword: false)
    }

    /// The app can also be killed around AppKit — the installer runs `pkill` before an
    /// upgrade. Without this handler the system-wide sleep ban would be left behind.
    private func installSignalHandler() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            self?.mode.relinquish(mayAskPassword: false)
            NSApp.terminate(nil)
        }
        source.resume()
        sigtermSource = source
    }

    // MARK: - State

    private func toggleMode() {
        apply(mode.set(!mode.isOn))
    }

    private func apply(_ outcome: SleepMode.Outcome) {
        if case .failed(let message) = outcome {
            Alerts.show(title: L("alert.sleepFailed", "Could not change the sleep setting"),
                        text: message, style: .warning)
        }
        refreshAppearance()
    }

    private func syncWithSystem() {
        mode.syncWithSystem()
        refreshAppearance()
        checkBattery()
    }

    /// Guards against the one mistake this app makes easy: mode on, lid shut, Mac in a bag,
    /// running hot until the battery is flat.
    private func checkBattery() {
        let verdict = BatteryGuard.verdict(for: PowerSource.current,
                                           onlyOnPower: Preferences.onlyOnPower,
                                           floor: Preferences.batteryFloor)

        guard mode.isOn, verdict != .keepRunning else {
            batteryGuardTripped = false
            return
        }
        guard !batteryGuardTripped else { return }
        batteryGuardTripped = true

        apply(mode.set(false))

        let body: String
        switch verdict {
        case .unplugged:
            body = L("notify.unplugged",
                     "The power adapter was unplugged. Your Mac sleeps as configured again.")
        case .lowBattery(let percentage):
            body = String(format: L("notify.lowBattery",
                                    "The battery is down to %d%%. Your Mac sleeps as configured again."),
                          percentage)
        case .keepRunning:
            return
        }
        Notifier.postIfAllowed(title: L("notify.turnedOff", "SleepSwitch turned the mode off"),
                               body: body,
                               identifier: "battery-guard")
    }

    // MARK: - Appearance

    private var statusSymbol: String {
        guard mode.isOn else { return "moon.zzz.fill" }
        return mode.isFullyOn ? "cup.and.saucer.fill" : "exclamationmark.triangle.fill"
    }

    private var statusLine: String {
        guard mode.isOn else {
            return L("status.off", "Normal mode — your Mac sleeps as configured")
        }
        guard mode.isFullyOn else {
            return L("status.partial", "Partial: idle sleep blocked, but the lid still sleeps")
        }
        return L("status.on", "Awake: lid and idle timer are ignored")
    }

    private func refreshAppearance() {
        guard let button = statusItem.button else { return }

        // The sync runs on a timer, so skip the work when nothing moved.
        let symbol = statusSymbol
        guard symbol != currentSymbol else { return }
        currentSymbol = symbol

        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "SleepSwitch")
        image?.isTemplate = true
        button.image = image
        button.toolTip = statusLine
    }

    // MARK: - Menu

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            toggleMode()
        }
    }

    private func showMenu() {
        // performClick triggers the button action again, so without this flag the call
        // recurses into itself.
        guard !isShowingMenu else { return }
        isShowingMenu = true
        defer { isShowingMenu = false }

        syncWithSystem()
        statusItem.menu = buildMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(label(statusLine))
        menu.addItem(action(mode.isOn ? L("menu.turnOff", "Turn the mode off")
                                      : L("menu.turnOn", "Turn the mode on"),
                            #selector(menuToggle), key: "t"))
        menu.addItem(.separator())

        // A Mac without a battery has nothing to guard, so the settings are not shown at
        // all rather than shown and quietly inert.
        if PowerSource.hasInternalBattery {
            menu.addItem(batteryFloorItem())
            menu.addItem(checkbox(L("menu.onlyOnPower", "Keep awake only on power"),
                                  #selector(menuToggleOnlyOnPower),
                                  isOn: Preferences.onlyOnPower))
            menu.addItem(.separator())
        }

        menu.addItem(checkbox(L("menu.enableAtLaunch", "Turn the mode on at launch"),
                              #selector(menuToggleEnableAtLaunch),
                              isOn: Preferences.enableAtLaunch))
        menu.addItem(checkbox(L("menu.loginItem", "Open at login"),
                              #selector(menuToggleLoginItem),
                              isOn: isLoginItemEnabled))
        menu.addItem(.separator())

        if SystemSleepBan.hasPasswordlessRule {
            menu.addItem(action(L("menu.removeRule", "Ask for the password again…"),
                                #selector(menuRemoveRule)))
        } else {
            menu.addItem(action(L("menu.installRule", "Toggle without a password…"),
                                #selector(menuInstallRule)))
        }
        menu.addItem(action(L("menu.lockSettings", "Screen lock settings…"),
                            #selector(menuOpenLockSettings)))
        menu.addItem(.separator())

        menu.addItem(checkbox(L("menu.autoUpdate", "Check for updates automatically"),
                              #selector(menuToggleAutoUpdate),
                              isOn: Preferences.autoCheckUpdates))
        menu.addItem(action(L("menu.checkUpdates", "Check for updates…"),
                            #selector(menuCheckUpdates)))
        menu.addItem(.separator())

        // The version belongs on screen: the app updates itself, and otherwise the only
        // way to tell which build is running is Finder → Get Info.
        menu.addItem(label("SleepSwitch \(Updater.currentVersion)"))
        menu.addItem(action(L("menu.quit", "Quit SleepSwitch"), #selector(menuQuit), key: "q"))
        return menu
    }

    private func batteryFloorItem() -> NSMenuItem {
        let item = NSMenuItem(title: L("menu.batteryFloor", "Turn off on low battery"),
                              action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for floor in BatteryGuard.offeredFloors {
            let title = floor == 0
                ? L("menu.batteryFloor.never", "Never")
                : String(format: L("menu.batteryFloor.at", "At %d%%"), floor)
            let entry = NSMenuItem(title: title,
                                   action: #selector(menuSetBatteryFloor(_:)),
                                   keyEquivalent: "")
            entry.target = self
            entry.tag = floor
            entry.state = Preferences.batteryFloor == floor ? .on : .off
            submenu.addItem(entry)
        }
        item.submenu = submenu
        return item
    }

    private func label(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    private func checkbox(_ title: String, _ selector: Selector, isOn: Bool) -> NSMenuItem {
        let item = action(title, selector)
        item.state = isOn ? .on : .off
        return item
    }

    // MARK: - Menu actions

    @objc private func menuToggle() {
        toggleMode()
    }

    @objc private func menuSetBatteryFloor(_ sender: NSMenuItem) {
        Preferences.batteryFloor = sender.tag
        checkBattery()
    }

    @objc private func menuToggleOnlyOnPower() {
        Preferences.onlyOnPower.toggle()
        checkBattery()
    }

    @objc private func menuToggleAutoUpdate() {
        Preferences.autoCheckUpdates.toggle()
    }

    @objc private func menuCheckUpdates() {
        updates.checkNow()
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }

    @objc private func menuOpenLockSettings() {
        let pane = "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension"
        guard let url = URL(string: pane) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func menuToggleEnableAtLaunch() {
        Preferences.enableAtLaunch.toggle()
        guard Preferences.enableAtLaunch, !SystemSleepBan.hasPasswordlessRule else { return }

        // Without the sudo rule the mode cannot come up quietly, and asking for a password
        // at every login is not acceptable. Say so, and offer to fix it.
        let choice = Alerts.choose(
            title: L("alert.autoEnable.title", "The mode will only turn on partially"),
            text: L("alert.autoEnable.text",
                    "Blocking lid-close sleep needs administrator rights. Without the sudo "
                        + "rule SleepSwitch will not ask for a password at every login — it "
                        + "will start in partial mode instead, where idle sleep is blocked "
                        + "but closing the lid still puts your Mac to sleep."),
            buttons: [
                L("alert.autoEnable.install", "Set up passwordless toggling…"),
                L("alert.autoEnable.keep", "Leave it as is"),
            ]
        )
        if choice == 0 { menuInstallRule() }
    }

    @objc private func menuInstallRule() {
        switch SystemSleepBan.installPasswordlessRule() {
        case .success:
            Alerts.show(title: L("alert.ruleInstalled.title", "Done"),
                        text: L("alert.ruleInstalled.text",
                                "The mode now toggles without a password."),
                        style: .informational)
        case .failure(.cancelled):
            break
        case .failure(.failed(let message)):
            Alerts.show(title: L("alert.ruleInstallFailed", "Could not install the rule"),
                        text: message, style: .warning)
        }
    }

    @objc private func menuRemoveRule() {
        if case .failure(.failed(let message)) = SystemSleepBan.removePasswordlessRule() {
            Alerts.show(title: L("alert.ruleRemoveFailed", "Could not remove the rule"),
                        text: message, style: .warning)
        }
    }

    // MARK: - Login item

    private var isLoginItemEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func menuToggleLoginItem() {
        do {
            if isLoginItemEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Alerts.show(title: L("alert.loginItemFailed", "Could not change the login item"),
                        text: error.localizedDescription, style: .warning)
        }
    }
}
