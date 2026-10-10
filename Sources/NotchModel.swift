// NotchModel.swift – stan wcięcia: co pokazać i w jakim rozmiarze

import Cocoa
import Combine

/// Chwilowe zdarzenie, pokazywane przez ok. 2 sekundy.
enum Activity: Equatable {
    case power(level: Int, charging: Bool, onAC: Bool)
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
}

enum NotchMode: Equatable {
    case idle        // małe, puste wcięcie
    case alert       // powiększona karta: urządzenie, wydarzenie, bateria
    case activity    // chwilowe zdarzenie (głośność, jasność, zasilacz)
    case event       // wydarzenie za ≤ 15 minut (odliczanie)
    case music       // gra muzyka – to, co działa w tle, ma pierwszeństwo
    case agenda      // najbliższe wydarzenie z najbliższych 7 dni (gdy nic nie gra)
    case expanded    // rozwinięty panel
}

final class NotchModel: ObservableObject {

    @Published var activity: Activity?
    @Published var alert: NotchAlert?
    @Published var nowPlaying: NowPlaying?
    @Published var expanded = false
    @Published var hovering = false
    /// Zakładka rozwiniętego panelu: 0 – Teraz, 1 – Dziś
    @Published var panelTab = 0

    @Published var volume: Float = 0
    @Published var muted = false
    @Published var brightness: Float?
    @Published var batteryLevel = 100
    @Published var charging = false
    @Published var onAC = false
    @Published var devices: [DeviceInfo] = []
    @Published var todayEvents: [CalendarItem] = [] { didSet { checkEventAlerts() } }
    @Published var reminders: [ReminderItem] = []
    @Published var micInUse = false
    @Published var cameraInUse = false

    /// Wysokość paska menu – wcięcie ma dokładnie tyle.
    @Published var barHeight: CGFloat = 24
    /// Brak miejsca w pasku – wcięcie pokazuje się jako kapsułka pod paskiem.
    @Published var dropped = false
    /// Ciemny pas menu – wtedy pokazujemy „uszka” jak w prawdziwym wcięciu.
    @Published var darkMenuBar = false
    /// Odświeżany co 30 s – do odliczania minut do wydarzenia.
    @Published var clock = Date() { didSet { checkEventAlerts() } }

    private var activityTimer: DispatchWorkItem?
    private var alertTimer: DispatchWorkItem?
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
        if alert != nil { return .alert }
        if activity != nil { return .activity }
        if upcomingEvent != nil { return .event }
        if musicActive { return .music }
        if Prefs.on(Prefs.calendar) && nextEvent != nil { return .agenda }
        return .idle
    }

    /// Druga aktywność (muzyka gra, a na wcięciu jest coś innego) – mała kropka, jak w iPhonie.
    var showsSecondaryDot: Bool {
        [.activity, .event].contains(mode) && musicActive
    }

    /// Rozmiar samego kształtu wcięcia (bez „uszek”).
    func size(for mode: NotchMode) -> CGSize {
        switch mode {
        case .idle: return CGSize(width: 72, height: barHeight)
        case .alert: return CGSize(width: 340, height: barHeight + 56)
        case .activity, .music, .event, .agenda: return CGSize(width: 196, height: barHeight)
        case .expanded: return CGSize(width: 460, height: 252)
        }
    }

    var ear: CGFloat { (darkMenuBar && !dropped) ? 4 : 0 }

    // MARK: - Powiadomienia

    /// Pokazuje powiększoną kartę na `duration` sekund (nowsza zastępuje starszą).
    func showAlert(_ new: NotchAlert, duration: Double) {
        guard !expanded else { return }
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

    /// Wydarzenie zapowiadamy raz, gdy wchodzi w okno 15 minut, i drugi raz w chwili rozpoczęcia.
    private func checkEventAlerts() {
        guard let event = upcomingEvent else { return }
        let seconds = event.start.timeIntervalSince(clock)
        let key = "\(event.id)|\(Int(event.start.timeIntervalSince1970))"
        let time = event.start.formatted(date: .omitted, time: .shortened)
        let join = event.meetingURL != nil ? "Dołącz" : nil
        if seconds > 60 && !announcedEvents.contains(key) {
            announcedEvents.insert(key)
            let minutes = Int((seconds / 60).rounded(.up))
            showAlert(NotchAlert(symbol: "calendar", tint: event.color, title: event.title,
                                 subtitle: "Za \(minutes) min · \(time)",
                                 badge: join == nil ? "za \(minutes) min" : "", badgeColor: .systemOrange,
                                 actionTitle: join, actionURL: event.meetingURL), duration: 8)
        } else if seconds <= 60 && !announcedEvents.contains(key + "|teraz") {
            announcedEvents.insert(key)
            announcedEvents.insert(key + "|teraz")
            showAlert(NotchAlert(symbol: "calendar", tint: event.color, title: event.title,
                                 subtitle: "Zaczyna się teraz · \(time)",
                                 badge: join == nil ? "teraz" : "", badgeColor: .systemOrange,
                                 actionTitle: join, actionURL: event.meetingURL), duration: 8)
        }
    }

    // MARK: - Zdarzenia

    func show(_ new: Activity) {
        guard !expanded else { return }
        activity = new
        activityTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.activity = nil }
        activityTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }
}
