import AppKit
import IOKit
import IOKit.pwr_mgt
import ServiceManagement

// MARK: - Ключи настроек

enum Defaults {
    static let keepDisplayAwake = "keepDisplayAwake"
    static let enableAtLaunch = "enableAtLaunch"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            keepDisplayAwake: true,
            enableAtLaunch: false,
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
            return .failure(.failed("Недопустимое имя учётной записи: «\(user)»."))
        }

        let lines = [
            "# Создано SleepSwitch. Разрешает переключать запрет сна без ввода пароля.",
            "# Удалить: sudo rm \(sudoersPath)",
            "\(user) ALL=(root) NOPASSWD: \(pmsetPath) -a disablesleep 0",
            "\(user) ALL=(root) NOPASSWD: \(pmsetPath) -a disablesleep 1",
        ]
        guard lines.allSatisfy({ !$0.contains("'") }) else {
            return .failure(.failed("Не удалось безопасно сформировать правило."))
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
            return .failure(.failed("Не удалось собрать запрос прав."))
        }
        script.executeAndReturnError(&errorInfo)

        guard let errorInfo else { return .success(()) }
        // -128 = пользователь нажал «Отмена» в диалоге пароля.
        if (errorInfo[NSAppleScript.errorNumber] as? Int) == -128 {
            return .failure(.cancelled)
        }
        let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Неизвестная ошибка."
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

    private var keepDisplayAwake: Bool {
        get { UserDefaults.standard.bool(forKey: Defaults.keepDisplayAwake) }
        set { UserDefaults.standard.set(newValue, forKey: Defaults.keepDisplayAwake) }
    }

    private var enableAtLaunch: Bool {
        get { UserDefaults.standard.bool(forKey: Defaults.enableAtLaunch) }
        set { UserDefaults.standard.set(newValue, forKey: Defaults.enableAtLaunch) }
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
            showAlert(title: "Не удалось изменить настройку сна",
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
        if !isOn { return "Обычный режим — Mac засыпает как настроено" }
        if isFullyOn { return "Не спит: крышка и бездействие игнорируются" }
        return "Частично: сон по бездействию запрещён, но крышка усыпит Mac"
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

        menu.addItem(item(isOn ? "Выключить режим" : "Включить режим",
                          #selector(menuToggle), key: "t"))
        menu.addItem(.separator())

        menu.addItem(check("Не гасить экран", #selector(menuToggleDisplay), on: keepDisplayAwake))
        menu.addItem(check("Включать режим при запуске", #selector(menuToggleAutoEnable), on: enableAtLaunch))
        menu.addItem(check("Запускать при входе в систему", #selector(menuToggleLoginItem), on: isLoginItemEnabled))
        menu.addItem(.separator())

        if SleepDisable.hasPasswordlessRule {
            menu.addItem(item("Снова спрашивать пароль…", #selector(menuRemoveRule)))
        } else {
            menu.addItem(item("Переключать без пароля…", #selector(menuInstallRule)))
        }
        menu.addItem(item("Настройки блокировки экрана…", #selector(menuOpenLockSettings)))
        menu.addItem(.separator())

        menu.addItem(item("Выйти из SleepSwitch", #selector(menuQuit), key: "q"))
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
            showAlert(title: "Готово",
                      text: "Теперь режим переключается без пароля.",
                      style: .informational)
        case .failure(.cancelled):
            break
        case .failure(let error):
            showAlert(title: "Не удалось установить правило",
                      text: String(describing: error), style: .warning)
        }
    }

    @objc private func menuRemoveRule() {
        switch SleepDisable.removePasswordlessRule() {
        case .success, .failure(.cancelled):
            break
        case .failure(let error):
            showAlert(title: "Не удалось удалить правило",
                      text: String(describing: error), style: .warning)
        }
    }

    @objc private func menuOpenLockSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension")!
        NSWorkspace.shared.open(url)
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
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
            showAlert(title: "Не удалось изменить автозапуск",
                      text: error.localizedDescription, style: .warning)
        }
    }

    // MARK: вспомогательное

    private func showAlert(title: String, text: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
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
