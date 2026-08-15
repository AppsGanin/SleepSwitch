import Foundation

// Тесты для Sources/Updater.swift. Компилируется вместе с ним:
//   swiftc -o /tmp/t Sources/Updater.swift Tools/test-updater.swift && /tmp/t [--network]
// Без --network проверяются только чистые функции — их и гоняет CI.

var failures = 0

func expect(_ condition: Bool, _ description: String) {
    if condition {
        print("  ок   \(description)")
    } else {
        print("  ПРОВАЛ \(description)")
        failures += 1
    }
}

print("Сравнение версий")
expect(Updater.isNewer("1.0.1", than: "1.0.0"), "1.0.1 новее 1.0.0")
expect(Updater.isNewer("1.10.0", than: "1.9.3"), "1.10.0 новее 1.9.3 (не строковое сравнение)")
expect(Updater.isNewer("2.0", than: "1.99.99"), "2.0 новее 1.99.99")
expect(Updater.isNewer("1.1", than: "1.0.9"), "разная длина: 1.1 новее 1.0.9")
expect(!Updater.isNewer("1.0.0", than: "1.0.0"), "равные версии не считаются новее")
expect(!Updater.isNewer("1.0.0", than: "1.0.1"), "старая версия не считается новее")
expect(!Updater.isNewer("1.0", than: "1.0.0"), "1.0 не новее 1.0.0")
expect(!Updater.isNewer("мусор", than: "1.0.0"), "мусор не выдаёт себя за новую версию")

print("Проверка источника загрузки")
expect(Updater.isTrusted(URL(string: "https://github.com/AppsGanin/SleepSwitch/releases/x.pkg")!),
       "github.com разрешён")
expect(Updater.isTrusted(URL(string: "https://objects.githubusercontent.com/a/b.pkg")!),
       "objects.githubusercontent.com разрешён")
expect(!Updater.isTrusted(URL(string: "http://github.com/a.pkg")!),
       "http отклонён")
expect(!Updater.isTrusted(URL(string: "https://evil.com/a.pkg")!),
       "посторонний хост отклонён")
expect(!Updater.isTrusted(URL(string: "https://github.com.evil.com/a.pkg")!),
       "хост-подделка github.com.evil.com отклонён")
expect(!Updater.isTrusted(URL(string: "file:///tmp/a.pkg")!),
       "локальный файл отклонён")

if CommandLine.arguments.contains("--network") {
    print("Живой запрос к GitHub")
    var done = false
    Updater.fetchLatest { result in
        switch result {
        case .success(let release):
            expect(!release.version.isEmpty, "версия получена: \(release.version)")
            expect(release.version.first?.isNumber == true, "тег очищен от «v»")
            expect(release.package != nil, "в релизе есть .pkg: \(release.package?.lastPathComponent ?? "нет")")
            if let package = release.package {
                expect(Updater.isTrusted(package), "ссылка на пакет ведёт на GitHub")
            }
        case .failure(let error):
            expect(false, "запрос не удался: \(error)")
        }
        done = true
    }
    let deadline = Date().addingTimeInterval(30)
    while !done && Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
    }
    expect(done, "ответ получен за 30 секунд")
}

print(failures == 0 ? "\nВсе проверки пройдены." : "\nПровалов: \(failures)")
exit(failures == 0 ? 0 : 1)
