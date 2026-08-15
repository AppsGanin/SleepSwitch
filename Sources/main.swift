import AppKit
import IOKit
import IOKit.pwr_mgt
import ServiceManagement

// MARK: - Локализация

/// Короткая обёртка над NSLocalizedString. Второй аргумент — английский текст:
/// он же используется как запасной вариант, если .lproj по какой-то причине не нашёлся.
func L(_ key: String, _ english: String) -> String {
    NSLocalizedString(key, tableName: nil, bundle: .main, value: english, comment: "")
}

// MARK: - Ключи настроек

enum Defaults {
    static let keepDisplayAwake = "keepDisplayAwake"
    static let enableAtLaunch = "enableAtLaunch"
    static let autoCheckUpdates = "autoCheckUpdates"
    static let lastUpdateCheck = "lastUpdateCheck"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            keepDisplayAwake: true,
            enableAtLaunch: false,
            autoCheckUpdates: true,
        ])
    }
}

// MARK: - Ассершены питания (работают без root)

/// Держит IOKit-ассершены: запрет сна по бездействию и (опционально) запрет гашения экрана.
/// Ассершены автоматически снимаются, если процесс умрёт, — это безопасный слой.
final class PowerAssertions {
    private var systemID: IOPMAssertionID = 0
    private var displayID: IOPMAssertionID = 0

    private(set) var holdsSystem = false
    private(set) var holdsDisplay = false

    func apply(active: Bool, keepDisplayAwake: Bool) {
        setSystem(active)
        setDisplay(active && keepDisplayAwake)
    }

    func releaseAll() {
        apply(active: false, keepDisplayAwake: false)
    }

    private func setSystem(_ wanted: Bool) {
        guard wanted != holdsSystem else { return }
        if wanted {
            // Имена ассершенов латиницей: pmset -g assertions печатает их как ASCII.
            if let id = create(kIOPMAssertionTypePreventUserIdleSystemSleep,
                               "SleepSwitch: no idle sleep") {
                systemID = id
                holdsSystem = true
            }
        } else {
            IOPMAssertionRelease(systemID)
            systemID = 0
            holdsSystem = false
        }
    }

    private func setDisplay(_ wanted: Bool) {
        guard wanted != holdsDisplay else { return }
        if wanted {
            if let id = create(kIOPMAssertionTypePreventUserIdleDisplaySleep,
                               "SleepSwitch: no display sleep") {
                displayID = id
                holdsDisplay = true
            }
        } else {
            IOPMAssertionRelease(displayID)
            displayID = 0
            holdsDisplay = false
        }
    }

    private func create(_ type: String, _ reason: String) -> IOPMAssertionID? {
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        return result == kIOReturnSuccess ? id : nil
    }
}

// MARK: - pmset disablesleep (нужен root)

enum SleepDisable {
    static let pmsetPath = "/usr/bin/pmset"
    static let sudoersPath = "/etc/sudoers.d/sleepswitch"

    /// Текущее состояние читается прямо из IOPMrootDomain — без sudo.
    static var isActive: Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }

        guard let raw = IORegistryEntryCreateCFProperty(service,
                                                        "SleepDisabled" as CFString,
                                                        kCFAllocatorDefault, 0)?
            .takeRetainedValue() else { return false }
        return (raw as? NSNumber)?.boolValue ?? false
    }

    /// true, если sudo-правило установлено и pmset можно дёргать без пароля.
    static var hasPasswordlessRule: Bool {
        FileManager.default.fileExists(atPath: sudoersPath)
    }

    enum Failure: Error {
        case cancelled
        case failed(String)
    }

    /// Пробует без пароля через sudoers, иначе показывает системный диалог администратора.
    static func set(_ on: Bool) -> Result<Void, Failure> {
        let value = on ? "1" : "0"
        if runSilently("/usr/bin/sudo", ["-n", pmsetPath, "-a", "disablesleep", value]) {
            return .success(())
        }
        return runAsAdmin("\(pmsetPath) -a disablesleep \(value)")
    }

    /// Аварийный сброс при выходе: только тихая попытка, без диалогов пароля.
    static func resetQuietly() {
        _ = runSilently("/usr/bin/sudo", ["-n", pmsetPath, "-a", "disablesleep", "0"])
    }

    // MARK: sudo-правило

    static func installPasswordlessRule() -> Result<Void, Failure> {
        let user = NSUserName()
        guard isSafeUserName(user) else {
            let format = L("error.badUserName", "Unsupported account name: “%@”.")
            return .failure(.failed(String(format: format, user)))
        }

        // Комментарии в sudoers оставляем английскими: это системный файл,
        // и читать его будет тот, кто разбирается в конфигурации машины.
        let lines = [
            "# Installed by SleepSwitch. Allows toggling the sleep ban without a password.",
            "# Remove with: sudo rm \(sudoersPath)",
            "\(user) ALL=(root) NOPASSWD: \(pmsetPath) -a disablesleep 0",
            "\(user) ALL=(root) NOPASSWD: \(pmsetPath) -a disablesleep 1",
        ]
        guard lines.allSatisfy({ !$0.contains("'") }) else {
            return .failure(.failed(L("error.ruleBuild", "Could not build the rule safely.")))
        }

        // Файл готовится, проверяется и ставится целиком под root во временной папке
        // с правами 0700. Промежуточного файла, доступного на запись пользователю,
        // в цепочке нет: иначе его можно было бы подменить между visudo и install
        // и записать в sudoers что угодно.
        let quoted = lines.map { "'\($0)'" }.joined(separator: " ")
        let command = "d=$(/usr/bin/mktemp -d) && "
            + "/usr/bin/printf '%s\\n' \(quoted) > \"$d/sleepswitch\" && "
            + "/usr/sbin/visudo -cf \"$d/sleepswitch\" && "
            + "/usr/bin/install -m 0440 -o root -g wheel \"$d/sleepswitch\" \(sudoersPath); "
            + "r=$?; /bin/rm -rf \"$d\"; exit $r"
        return runAsAdmin(command)
    }

    /// Имя учётной записи попадает и в sudoers, и в shell-команду, поэтому допускаем
    /// только символы, которые macOS вообще разрешает в коротком имени.
    private static func isSafeUserName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 63, name.first != "-" else { return false }
        return name.allSatisfy { character in
            character.isASCII &&
                (character.isLetter || character.isNumber || "._-".contains(character))
        }
    }

    static func removePasswordlessRule() -> Result<Void, Failure> {
        runAsAdmin("/bin/rm -f \(sudoersPath)")
    }

    // MARK: запуск процессов

    private static func runSilently(_ launchPath: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// Системный диалог macOS с запросом пароля администратора.
    /// Пароль вводится в окно самой системы — приложение его не видит.
    private static func runAsAdmin(_ shellCommand: String) -> Result<Void, Failure> {
        // Порядок важен: сначала обратные слэши, иначе экранирование съест само себя.
        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        let source = "do shell script \"\(escaped)\" with administrator privileges"

        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            return .failure(.failed(L("error.scriptBuild", "Could not build the privilege request.")))
        }
        script.executeAndReturnError(&errorInfo)

        guard let errorInfo else { return .success(()) }
        // -128 = пользователь нажал «Отмена» в диалоге пароля.
        if (errorInfo[NSAppleScript.errorNumber] as? Int) == -128 {
            return .failure(.cancelled)
        }
        let message = errorInfo[NSAppleScript.errorMessage] as? String
            ?? L("error.unknown", "Unknown error.")
        return .failure(.failed(message))
    }
}

// MARK: - Приложение

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let assertions = PowerAssertions()
    private var refreshTimer: Timer?

    /// Режим включён пользователем.
    private var isOn = false
    /// Запрет сна на уровне системы включили мы — значит мы обязаны его снять.
    private var weDisabledSleep = false
    private var isShowingMenu = false
    private var currentSymbol: String?
    private var sigtermSource: DispatchSourceSignal?
    private var updateTimer: Timer?

    private var keepDisplayAwake: Bool {
        get { UserDefaults.standard.bool(forKey: Defaults.keepDisplayAwake) }
        set { UserDefaults.standard.set(newValue, forKey: Defaults.keepDisplayAwake) }
    }

    private var enableAtLaunch: Bool {
        get { UserDefaults.standard.bool(forKey: Defaults.enableAtLaunch) }
        set { UserDefaults.standard.set(newValue, forKey: Defaults.enableAtLaunch) }
    }

    private var autoCheckUpdates: Bool {
        get { UserDefaults.standard.bool(forKey: Defaults.autoCheckUpdates) }
        set { UserDefaults.standard.set(newValue, forKey: Defaults.autoCheckUpdates) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Defaults.registerDefaults()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Если запрет сна уже стоял до нас (например, после падения) — показываем это честно.
        isOn = SleepDisable.isActive
        applyState()

        if enableAtLaunch && !isOn {
            setOn(true)
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemWillPowerOff),
            name: NSWorkspace.willPowerOffNotification, object: nil
        )

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.syncWithSystem()
        }

        installSignalHandler()
        scheduleUpdateChecks()
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanUp(mayAskPassword: true)
    }

    @objc private func systemWillPowerOff() {
        // Во время выключения нельзя показывать модальный диалог — он заблокирует
        // завершение сеанса. Пробуем только тихий путь.
        cleanUp(mayAskPassword: false)
    }

    /// Приложение можно погасить и мимо AppKit — например, установщик делает pkill
    /// перед обновлением. Без этого обработчика системный запрет сна остался бы висеть.
    private func installSignalHandler() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            self?.cleanUp(mayAskPassword: false)
            NSApp.terminate(nil)
        }
        source.resume()
        sigtermSource = source
    }

    private func cleanUp(mayAskPassword: Bool) {
        assertions.releaseAll()
        guard weDisabledSleep else { return }
        weDisabledSleep = false

        SleepDisable.resetQuietly()
        // Тихий путь работает только с правилом sudo. Без него запрет сна переживёт
        // выход из приложения, поэтому спрашиваем пароль — иначе Mac останется
        // навсегда бодрым, а переключателя на экране уже не будет.
        if mayAskPassword && SleepDisable.isActive {
            _ = SleepDisable.set(false)
        }
    }

    // MARK: состояние

    private func setOn(_ wanted: Bool) {
        isOn = wanted
        assertions.apply(active: wanted, keepDisplayAwake: keepDisplayAwake)

        switch SleepDisable.set(wanted) {
        case .success:
            weDisabledSleep = wanted
        case .failure(.cancelled):
            // Пользователь отказался вводить пароль: при включении остаёмся
            // в частичном режиме, при выключении — см. сверку ниже.
            break
        case .failure(.failed(let message)):
            showAlert(title: L("alert.sleepFailed", "Could not change the sleep setting"),
                      text: message,
                      style: .warning)
        }

        // Выключить не вышло, а системный запрет сна остался — значит режим на самом
        // деле не выключен. Показываем правду сразу, не дожидаясь сверки по таймеру.
        if !wanted && SleepDisable.isActive {
            isOn = true
        }
        applyState()
    }

    /// Подхватывает изменения, сделанные мимо приложения (терминал, другой софт).
    private func syncWithSystem() {
        let actual = SleepDisable.isActive
        if !isOn && actual {
            isOn = true
            assertions.apply(active: true, keepDisplayAwake: keepDisplayAwake)
            applyState()
        } else if isOn && !actual && !assertions.holdsSystem {
            isOn = false
            applyState()
        } else {
            updateAppearance()
        }
    }

    private func applyState() {
        assertions.apply(active: isOn, keepDisplayAwake: keepDisplayAwake)
        updateAppearance()
    }

    private var isFullyOn: Bool { isOn && SleepDisable.isActive }

    private func updateAppearance() {
        guard let button = statusItem.button else { return }
        let symbol: String
        if !isOn {
            symbol = "moon.zzz.fill"
        } else if isFullyOn {
            symbol = "cup.and.saucer.fill"
        } else {
            symbol = "exclamationmark.triangle.fill"
        }
        // Сверка идёт раз в пять секунд — не пересобираем картинку, если ничего не менялось.
        guard symbol != currentSymbol else { return }
        currentSymbol = symbol

        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "SleepSwitch")
        image?.isTemplate = true
        button.image = image
        button.toolTip = statusLine
    }

    private var statusLine: String {
        if !isOn {
            return L("status.off", "Normal mode — your Mac sleeps as configured")
        }
        if isFullyOn {
            return L("status.on", "Awake: lid and idle timer are ignored")
        }
        return L("status.partial", "Partial: idle sleep blocked, but the lid still sleeps")
    }

    // MARK: меню

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            setOn(!isOn)
        }
    }

    private func showMenu() {
        // performClick повторно дёргает action кнопки — без флага можно уйти в рекурсию.
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

        let header = NSMenuItem(title: statusLine, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        menu.addItem(item(isOn ? L("menu.turnOff", "Turn the mode off")
                               : L("menu.turnOn", "Turn the mode on"),
                          #selector(menuToggle), key: "t"))
        menu.addItem(.separator())

        menu.addItem(check(L("menu.keepDisplay", "Keep the screen on"),
                           #selector(menuToggleDisplay), on: keepDisplayAwake))
        menu.addItem(check(L("menu.enableAtLaunch", "Turn the mode on at launch"),
                           #selector(menuToggleAutoEnable), on: enableAtLaunch))
        menu.addItem(check(L("menu.loginItem", "Open at login"),
                           #selector(menuToggleLoginItem), on: isLoginItemEnabled))
        menu.addItem(.separator())

        if SleepDisable.hasPasswordlessRule {
            menu.addItem(item(L("menu.removeRule", "Ask for the password again…"),
                              #selector(menuRemoveRule)))
        } else {
            menu.addItem(item(L("menu.installRule", "Toggle without a password…"),
                              #selector(menuInstallRule)))
        }
        menu.addItem(item(L("menu.lockSettings", "Screen lock settings…"),
                          #selector(menuOpenLockSettings)))
        menu.addItem(.separator())

        menu.addItem(check(L("menu.autoUpdate", "Check for updates automatically"),
                           #selector(menuToggleAutoUpdate), on: autoCheckUpdates))
        menu.addItem(item(L("menu.checkUpdates", "Check for updates…"),
                          #selector(menuCheckUpdates)))
        menu.addItem(.separator())

        menu.addItem(item(L("menu.quit", "Quit SleepSwitch"), #selector(menuQuit), key: "q"))
        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        return menuItem
    }

    private func check(_ title: String, _ action: Selector, on: Bool) -> NSMenuItem {
        let menuItem = item(title, action)
        menuItem.state = on ? .on : .off
        return menuItem
    }

    // MARK: действия меню

    @objc private func menuToggle() { setOn(!isOn) }

    @objc private func menuToggleDisplay() {
        keepDisplayAwake.toggle()
        applyState()
    }

    @objc private func menuToggleAutoEnable() { enableAtLaunch.toggle() }

    @objc private func menuInstallRule() {
        switch SleepDisable.installPasswordlessRule() {
        case .success:
            showAlert(title: L("alert.ruleInstalled.title", "Done"),
                      text: L("alert.ruleInstalled.text",
                              "The mode now toggles without a password."),
                      style: .informational)
        case .failure(.cancelled):
            break
        case .failure(.failed(let message)):
            showAlert(title: L("alert.ruleInstallFailed", "Could not install the rule"),
                      text: message, style: .warning)
        }
    }

    @objc private func menuRemoveRule() {
        switch SleepDisable.removePasswordlessRule() {
        case .success, .failure(.cancelled):
            break
        case .failure(.failed(let message)):
            showAlert(title: L("alert.ruleRemoveFailed", "Could not remove the rule"),
                      text: message, style: .warning)
        }
    }

    @objc private func menuOpenLockSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension")!
        NSWorkspace.shared.open(url)
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }

    // MARK: обновления

    @objc private func menuToggleAutoUpdate() { autoCheckUpdates.toggle() }

    @objc private func menuCheckUpdates() { checkForUpdates(quietWhenCurrent: false) }

    private func scheduleUpdateChecks() {
        // Первую проверку откладываем: сразу после входа в систему сети может ещё не быть.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.checkForUpdatesIfDue()
        }
        updateTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.checkForUpdatesIfDue()
        }
    }

    private func checkForUpdatesIfDue() {
        guard autoCheckUpdates else { return }
        let last = UserDefaults.standard.object(forKey: Defaults.lastUpdateCheck) as? Date
        if let last, Date().timeIntervalSince(last) < 24 * 3600 { return }
        checkForUpdates(quietWhenCurrent: true)
    }

    private func checkForUpdates(quietWhenCurrent: Bool) {
        UserDefaults.standard.set(Date(), forKey: Defaults.lastUpdateCheck)
        Updater.fetchLatest { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let release)
                where Updater.isNewer(release.version, than: Updater.currentVersion):
                self.offerUpdate(release)
            case .success:
                guard !quietWhenCurrent else { return }
                self.showAlert(
                    title: L("update.upToDate.title", "You are up to date"),
                    text: String(format: L("update.upToDate.text",
                                           "SleepSwitch %@ is the latest version."),
                                 Updater.currentVersion),
                    style: .informational)
            case .failure(let error):
                guard !quietWhenCurrent else { return }
                self.showAlert(title: L("update.failed.title", "Could not check for updates"),
                               text: self.describe(error), style: .warning)
            }
        }
    }

    private func offerUpdate(_ release: Updater.Release) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(format: L("update.available.title",
                                             "SleepSwitch %@ is available"),
                                   release.version)
        alert.informativeText = String(format: L("update.available.text",
                                                 "You have version %@. Download the installer?"),
                                       Updater.currentVersion)
        alert.addButton(withTitle: L("update.download", "Download"))
        alert.addButton(withTitle: L("update.notes", "Release notes"))
        alert.addButton(withTitle: L("update.later", "Later"))
        NSApp.activate(ignoringOtherApps: true)

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if let package = release.package {
                startDownload(package)
            } else {
                NSWorkspace.shared.open(release.page)
            }
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(release.page)
        default:
            break
        }
    }

    private func startDownload(_ url: URL) {
        Updater.download(url) { [weak self] result in
            switch result {
            case .success(let file):
                // Приложение не подменяет себя само: пакет открывается системным
                // установщиком, там пользователь и проходит авторизацию.
                NSWorkspace.shared.open(file)
            case .failure(let error):
                self?.showAlert(
                    title: L("update.downloadFailed.title", "Could not download the update"),
                    text: self?.describe(error) ?? "", style: .warning)
            }
        }
    }

    private func describe(_ error: Updater.Failure) -> String {
        switch error {
        case .network(let message):
            return message
        case .malformed:
            return L("update.error.malformed", "GitHub returned an unexpected response.")
        case .noPackage:
            return L("update.error.noPackage", "This release has no installer package.")
        }
    }

    // MARK: автозапуск

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
            showAlert(title: L("alert.loginItemFailed", "Could not change the login item"),
                      text: error.localizedDescription, style: .warning)
        }
    }

    // MARK: вспомогательное

    private func showAlert(title: String, text: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: L("alert.ok", "OK"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

// MARK: - Точка входа

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
