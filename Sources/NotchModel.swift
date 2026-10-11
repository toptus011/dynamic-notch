// NotchModel.swift – stan wcięcia: co pokazać i w jakim rozmiarze

import Cocoa
import Combine

/// Chwilowe zdarzenie w małym wcięciu (ok. 2 sekundy).
enum Activity: Equatable {
    case power(level: Int, charging: Bool, onAC: Bool)
    /// „Skopiowano” – symbol i krótki opis (tekst, obraz, pliki)
    case copied(symbol: String, preview: String)
}

/// Ważność powiadomienia. Przy włączonym Skupieniu pokazujemy tylko ważne – tak jak robi to macOS.
enum AlertPriority {
    case normal      // urządzenie, zrzut ekranu, „Skopiowano”, zasilacz, ekran
    case important   // spotkanie, koniec minutnika, bateria, kamera i mikrofon
}

/// Powiadomienie wyświetlane w powiększonym wcięciu (jak alert w Dynamic Island).
struct NotchAlert: Equatable {
    var symbol: String
    var tint: NSColor
    var title: String
    var subtitle: String
    var badge: String = ""
    var badgeColor: NSColor = .secondaryLabelColor
    /// Przycisk w karcie, np. „Dołącz” do spotkania online
    var actionTitle: String? = nil
    var actionURL: URL? = nil
    /// Miniatura (zrzut ekranu) zamiast ikony – można ją przeciągnąć do dokumentu
    var image: NSImage? = nil
    var fileURL: URL? = nil
    /// Przycisk odkłada plik na półkę zamiast otwierać link
    var shelfAction = false
}

/// Zadanie na liście „Do zrobienia”.
struct TodoItem: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var done: Bool
}

enum NotchMode: Equatable {
    case idle        // małe, puste wcięcie
    case alert       // powiększona karta: urządzenie, wydarzenie, bateria…
    case activity    // chwilowe zdarzenie (zasilacz, „Skopiowano”)
    case music       // gra muzyka – to, co działa w tle, ma pierwszeństwo
    case timer       // działa minutnik lub stoper
    case drop        // przeciąganie pliku nad wcięcie: półka / AirDrop
    case expanded    // rozwinięty panel
}

final class NotchModel: ObservableObject {

    @Published var activity: Activity?
    @Published var alert: NotchAlert?
    @Published var nowPlaying: NowPlaying?
    @Published var expanded = false
    @Published var hovering = false
    /// Zakładka rozwiniętego panelu: 0 – Teraz, 1 – Tydzień, 2 – Narzędzia, 3 – Półka
    @Published var panelTab = 0

    @Published var volume: Float = 0
    @Published var muted = false
    @Published var brightness: Float?
    @Published var batteryLevel = 100
    @Published var charging = false
    @Published var onAC = false

    // Urządzenia
    @Published var devices: [DeviceInfo] = []
    /// USB i ekrany zewnętrzne (odświeżane przy otwarciu panelu)
    @Published var wiredDevices: [DeviceInfo] = []
    /// Rozwinięta lista urządzeń w zakładce „Teraz”
    @Published var devicesListOpen = false

    // Kalendarz i Przypomnienia
    @Published var todayEvents: [CalendarItem] = [] { didSet { checkEventAlerts() } }
    @Published var reminders: [ReminderItem] = []
    /// Odświeżany co 30 s – do zapowiadania wydarzeń.
    @Published var clock = Date() { didSet { checkEventAlerts() } }

    // Prywatność i stan systemu
    @Published var micInUse = false
    @Published var cameraInUse = false
    @Published var screenRecording = false
    /// Włączone Skupienie – wtedy pokazujemy tylko ważne powiadomienia.
    @Published var focusActive = false

    // Narzędzia: minutnik, stoper, lista zadań, półka, schowek
    @Published var timerEnd: Date?
    @Published var timerTotal: TimeInterval = 0
    @Published var stopwatchStart: Date?
    @Published var stopwatchAccumulated: TimeInterval = 0
    @Published var todos: [TodoItem] = NotchModel.loadTodos()
    @Published var newTodoText = ""
    @Published var shelf: [URL] = NotchModel.loadShelf()
    @Published var clipboardHistory: [String] = []
    /// Plik przeciągany nad wcięciem; strefa: 0 – półka, 1 – AirDrop
    @Published var dropTargeted = false
    @Published var dropZone = 0

    // Wygląd
    /// Wysokość paska menu – wcięcie ma dokładnie tyle.
    @Published var barHeight: CGFloat = 24
    /// Brak miejsca w pasku – wcięcie pokazuje się jako kapsułka pod paskiem.
    @Published var dropped = false
    /// Ciemny pas menu – wtedy pokazujemy „uszka” jak w prawdziwym wcięciu.
    @Published var darkMenuBar = false
    /// Przesunięcie kształtu względem środka okna (gdy menu programu zajmują środek paska).
    @Published var shapeOffset: CGSize = .zero

    private var activityTimer: DispatchWorkItem?
    private var alertTimer: DispatchWorkItem?
    private var timerWork: DispatchWorkItem?
    private var announcedEvents: Set<String> = []

    // MARK: - Tryb i rozmiar

    var musicActive: Bool {
        Prefs.on(Prefs.music) && (nowPlaying?.playing ?? false)
    }

    /// Najbliższe wydarzenie, które jeszcze się nie skończyło.
    var nextEvent: CalendarItem? {
        todayEvents.first { $0.end > clock }
    }

    /// Wydarzenie, które zaczyna się w ciągu 15 minut (albo trwa od najwyżej 5 minut).
    var upcomingEvent: CalendarItem? {
        guard Prefs.on(Prefs.calendar) else { return nil }
        return todayEvents.first { event in
            let seconds = event.start.timeIntervalSince(clock)
            return seconds <= 15 * 60 && seconds >= -5 * 60
        }
    }

    var mode: NotchMode {
        if expanded { return .expanded }
        if dropTargeted { return .drop }
        if alert != nil { return .alert }
        if activity != nil { return .activity }
        if timerEnd != nil || stopwatchStart != nil { return .timer }
        if musicActive { return .music }
        // Wydarzenia nie wiszą stale we wcięciu – pojawiają się na chwilę jako karta.
        return .idle
    }

    /// Druga aktywność (muzyka gra, a na wcięciu jest coś innego) – mała kropka, jak w iPhonie.
    var showsSecondaryDot: Bool {
        [.activity, .timer].contains(mode) && musicActive
    }

    /// Rozmiar samego kształtu wcięcia (bez „uszek”).
    func size(for mode: NotchMode) -> CGSize {
        switch mode {
        case .idle: return CGSize(width: 72, height: barHeight)
        case .alert: return CGSize(width: 340, height: barHeight + 56)
        case .activity, .music, .timer: return CGSize(width: 196, height: barHeight)
        case .drop: return CGSize(width: 340, height: barHeight + 64)
        case .expanded:
            // Rozwinięta lista urządzeń wydłuża panel – nic nie jest ucinane.
            let extra = (panelTab == 0 && devicesListOpen) ? CGFloat(min(allDevices.count, 6)) * 28 : 0
            return CGSize(width: 460, height: 270 + extra)
        }
    }

    var ear: CGFloat { (darkMenuBar && !dropped) ? 4 : 0 }

    // MARK: - Powiadomienia

    /// Pokazuje powiększoną kartę na `duration` sekund (nowsza zastępuje starszą).
    /// Przy włączonym Skupieniu zwykłe powiadomienia są pomijane.
    func showAlert(_ new: NotchAlert, duration: Double, priority: AlertPriority = .normal) {
        guard !expanded else { return }
        if focusActive && priority == .normal {
            Log.write("Skupienie – pominięto: \(new.title)")
            return
        }
        alert = new
        alertTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.alert = nil }
        alertTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
        Log.write("Powiadomienie: \(new.title) – \(new.subtitle)")
        // VoiceOver odczyta powiadomienie na głos
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: "\(new.title), \(new.subtitle)",
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    func show(_ new: Activity, duration: Double = 2.0) {
        guard !expanded, !focusActive else { return }
        activity = new
        activityTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.activity = nil }
        activityTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    /// Wydarzenie zapowiadamy raz, gdy wchodzi w okno 15 minut, i drugi raz w chwili rozpoczęcia.
    private func checkEventAlerts() {
        guard let event = upcomingEvent else { return }
        let seconds = event.start.timeIntervalSince(clock)
        let key = "\(event.id)|\(Int(event.start.timeIntervalSince1970))"
        let time = event.start.formatted(date: .omitted, time: .shortened)
        let join = event.meetingURL != nil ? tr("Dołącz", "Join") : nil
        if seconds > 60 && !announcedEvents.contains(key) {
            announcedEvents.insert(key)
            let minutes = Int((seconds / 60).rounded(.up))
            let inText = tr("za \(minutes) min", "in \(minutes) min")
            showAlert(NotchAlert(symbol: "calendar", tint: event.color, title: event.title,
                                 subtitle: tr("Za \(minutes) min · \(time)", "In \(minutes) min · \(time)"),
                                 badge: join == nil ? inText : "", badgeColor: .systemOrange,
                                 actionTitle: join, actionURL: event.meetingURL),
                      duration: 8, priority: .important)
        } else if seconds <= 60 && !announcedEvents.contains(key + "|teraz") {
            announcedEvents.insert(key)
            announcedEvents.insert(key + "|teraz")
            let subtitle = tr("Zaczyna się teraz · \(time)", "Starting now · \(time)")
            showAlert(NotchAlert(symbol: "calendar", tint: event.color, title: event.title,
                                 subtitle: subtitle,
                                 badge: join == nil ? tr("teraz", "now") : "", badgeColor: .systemOrange,
                                 actionTitle: join, actionURL: event.meetingURL),
                      duration: 8, priority: .important)
            // Także w Centrum powiadomień – nie przepadnie, gdy nie patrzysz na ekran.
            SystemNotifier.post(id: "wydarzenie-\(key)", title: event.title, body: subtitle)
        }
    }

    // MARK: - Minutnik i stoper

    func startTimer(minutes: Double) {
        timerTotal = minutes * 60
        timerEnd = Date().addingTimeInterval(timerTotal)
        scheduleTimerEnd()
        Log.write("Minutnik: \(Int(minutes)) min")
    }

    func addTimerMinute() {
        guard let end = timerEnd else { startTimer(minutes: 1); return }
        timerEnd = end.addingTimeInterval(60)
        timerTotal += 60
        scheduleTimerEnd()
    }

    func stopTimer() {
        timerWork?.cancel()
        timerEnd = nil
    }

    private func scheduleTimerEnd() {
        timerWork?.cancel()
        guard let end = timerEnd else { return }
        let work = DispatchWorkItem { [weak self] in self?.timerFinished() }
        timerWork = work
        // Zegar ścienny – minutnik liczy dalej także podczas uśpienia Maca.
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + max(0, end.timeIntervalSinceNow), execute: work)
    }

    private func timerFinished() {
        let total = timerTotal
        timerEnd = nil
        NSSound(named: "Glass")?.play()
        Log.write("Minutnik zakończony")
        let subtitle = tr("Minęło \(Self.durationText(total))", "\(Self.durationText(total)) elapsed")
        showAlert(NotchAlert(symbol: "timer", tint: .systemOrange, title: tr("Minutnik zakończony", "Timer done"),
                             subtitle: subtitle, badge: tr("koniec", "done"), badgeColor: .systemOrange),
                  duration: 8, priority: .important)
        SystemNotifier.post(id: "minutnik", title: tr("Minutnik zakończony", "Timer done"), body: subtitle)
    }

    var stopwatchRunning: Bool { stopwatchStart != nil }

    func stopwatchElapsed(at date: Date) -> TimeInterval {
        stopwatchAccumulated + (stopwatchStart.map { date.timeIntervalSince($0) } ?? 0)
    }

    func toggleStopwatch() {
        if let start = stopwatchStart {
            stopwatchAccumulated += Date().timeIntervalSince(start)
            stopwatchStart = nil
        } else {
            stopwatchStart = Date()
        }
    }

    func resetStopwatch() {
        stopwatchStart = nil
        stopwatchAccumulated = 0
    }

    /// „5 min”, „1 h 30 min”, „45 s”
    static func durationText(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s) s" }
        let h = s / 3600
        let m = (s % 3600) / 60
        return h > 0 ? (m > 0 ? "\(h) h \(m) min" : "\(h) h") : "\(m) min"
    }

    /// „4:59”, „1:02:03”
    static func clockText(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    // MARK: - Lista „Do zrobienia” (zapamiętywana)

    func addTodo(_ text: String? = nil) {
        let title = (text ?? newTodoText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        todos.append(TodoItem(id: UUID(), title: String(title.prefix(200)), done: false))
        if text == nil { newTodoText = "" }
        saveTodos()
    }

    func toggleTodo(_ id: UUID) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[i].done.toggle()
        saveTodos()
    }

    func deleteTodo(_ id: UUID) {
        todos.removeAll { $0.id == id }
        saveTodos()
    }

    func clearDoneTodos() {
        todos.removeAll { $0.done }
        saveTodos()
    }

    private func saveTodos() {
        if let data = try? JSONEncoder().encode(todos) {
            UserDefaults.standard.set(data, forKey: "listaZadan")
        }
    }

    private static func loadTodos() -> [TodoItem] {
        guard let data = UserDefaults.standard.data(forKey: "listaZadan"),
              let items = try? JSONDecoder().decode([TodoItem].self, from: data) else { return [] }
        return items
    }

    // MARK: - Półka na pliki (pamiętana po ponownym uruchomieniu)

    func addToShelf(_ urls: [URL]) {
        for url in urls where !shelf.contains(url) { shelf.append(url) }
        if shelf.count > 12 { shelf.removeFirst(shelf.count - 12) }
        saveShelf()
        Log.write("Półka: dodano \(urls.count), razem \(shelf.count)")
    }

    func removeFromShelf(_ url: URL) {
        shelf.removeAll { $0 == url }
        saveShelf()
    }

    func clearShelf() {
        shelf = []
        saveShelf()
    }

    private func saveShelf() {
        UserDefaults.standard.set(shelf.map(\.path), forKey: "polka")
    }

    private static func loadShelf() -> [URL] {
        let paths = UserDefaults.standard.stringArray(forKey: "polka") ?? []
        return paths.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    // MARK: - Urządzenia i schowek

    var allDevices: [DeviceInfo] { devices + wiredDevices }

    func rememberClip(_ text: String) {
        clipboardHistory.removeAll { $0 == text }
        clipboardHistory.insert(text, at: 0)
        if clipboardHistory.count > 8 { clipboardHistory.removeLast(clipboardHistory.count - 8) }
    }
}
