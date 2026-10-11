// SystemNotifier.swift – powiadomienia w Centrum powiadomień i sprawdzanie aktualizacji na GitHubie

import Cocoa
import UserNotifications

enum SystemNotifier {

    /// Prośba o zgodę na powiadomienia (raz, przy starcie).
    static func requestAuthorization() {
        guard Prefs.on(Prefs.systemNotifications) else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Log.write("Powiadomienia systemowe: \(granted ? "zgoda" : "brak zgody")")
        }
    }

    /// Ile sekund minęło od ostatniego ruchu myszą lub klawisza.
    static var secondsSinceInput: Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                eventType: CGEventType(rawValue: UInt32.max)!)
    }

    /// Ważne powiadomienie trafia też do Centrum powiadomień – ale tylko wtedy, gdy wcięcia
    /// mogłeś nie zauważyć (od minuty nie używasz Maca albo ekran jest uśpiony).
    /// Gdy siedzisz przy komputerze, wystarczy karta we wcięciu – bez podwójnych komunikatów.
    static func post(id: String, title: String, body: String, always: Bool = false) {
        guard Prefs.on(Prefs.systemNotifications) else { return }
        guard always || secondsSinceInput > 60 || CGDisplayIsAsleep(CGMainDisplayID()) != 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { Log.write("Powiadomienie systemowe – błąd: \(error.localizedDescription)") }
        }
    }
}

/// Raz dziennie sprawdza, czy na GitHubie jest nowsza wersja, i na chwilę pokazuje to we wcięciu.
enum UpdateChecker {

    static let repo = "toptus011/dynamic-notch"

    static func checkIfDue(_ model: NotchModel) {
        guard Prefs.on(Prefs.updates) else { return }
        let key = "ostatnieSprawdzenieAktualizacji"
        let last = UserDefaults.standard.double(forKey: key)
        let now = Date().timeIntervalSince1970
        guard now - last > 24 * 3600 else { return }
        UserDefaults.standard.set(now, forKey: key)

        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let tag = json["tag_name"] as? String else { return }
            let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            Log.write("Aktualizacje: na GitHubie \(latest), zainstalowana \(current)")
            guard isNewer(latest, than: current) else { return }
            let page = (json["html_url"] as? String).flatMap { URL(string: $0) }
                ?? URL(string: "https://github.com/\(repo)/releases")
            DispatchQueue.main.async {
                model.showAlert(NotchAlert(symbol: "arrow.down.circle.fill", tint: .controlAccentColor,
                                           title: tr("Dostępna wersja \(latest)", "Version \(latest) available"),
                                           subtitle: tr("Nowe wydanie Dynamic Notch na GitHubie",
                                                        "New Dynamic Notch release on GitHub"),
                                           actionTitle: tr("Pobierz", "Download"), actionURL: page),
                                duration: 10)
            }
        }.resume()
    }

    /// „1.10” > „1.9”, „1.7.1” > „1.7”
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
