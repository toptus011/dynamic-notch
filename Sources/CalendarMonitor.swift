// CalendarMonitor.swift – wydarzenia z Kalendarza na najbliższe 7 dni i przypomnienia na dziś
// O dostęp pyta przy starcie (gdy funkcje są włączone w Ustawieniach).

import Cocoa
import EventKit

struct CalendarItem: Equatable, Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let color: NSColor
    /// Link do spotkania online (Zoom, Meet, Teams, FaceTime, Webex), jeśli jest.
    let meetingURL: URL?
}

struct ReminderItem: Equatable, Identifiable {
    let id: String
    let title: String
    let due: Date?
    let overdue: Bool
}

final class CalendarMonitor {

    /// Wydarzenia z najbliższych 7 dni (najbliższe pierwsze)
    var onEvents: (([CalendarItem]) -> Void)?
    var onReminders: (([ReminderItem]) -> Void)?

    private let store = EKEventStore()
    private var askedEvents = false
    private var askedReminders = false
    private var eventsGranted = false
    private var remindersGranted = false
    private var reminderCache: [String: EKReminder] = [:]

    init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) {
            [weak self] _ in self?.refresh()
        }
    }

    /// Prosi o dostęp (jednorazowo) i odświeża dane.
    func refresh() {
        refreshEvents()
        refreshReminders()
    }

    // MARK: - Wydarzenia

    private func refreshEvents() {
        guard Prefs.on(Prefs.calendar) else { onEvents?([]); return }
        guard eventsGranted else {
            guard !askedEvents else { return }
            askedEvents = true
            let handler: (Bool, Error?) -> Void = { [weak self] ok, _ in
                DispatchQueue.main.async {
                    self?.eventsGranted = ok
                    Log.write("Kalendarz: dostęp \(ok ? "przyznany" : "nieprzyznany")")
                    if ok { self?.refreshEvents() }
                }
            }
            if #available(macOS 14.0, *) {
                store.requestFullAccessToEvents(completion: handler)
            } else {
                store.requestAccess(to: .event, completion: handler)
            }
            return
        }

        let now = Date()
        let calendar = Calendar.current
        guard let weekAhead = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now)) else { return }
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-600), end: weekAhead, calendars: nil)
        let items = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .prefix(20)
            .map { event in
                CalendarItem(id: event.eventIdentifier ?? UUID().uuidString,
                             title: event.title ?? "Wydarzenie",
                             start: event.startDate,
                             end: event.endDate,
                             color: event.calendar?.color ?? .systemRed,
                             meetingURL: Self.meetingURL(in: event))
            }
        onEvents?(Array(items))
    }

    /// Szuka linku do spotkania w adresie, miejscu i notatkach wydarzenia.
    private static func meetingURL(in event: EKEvent) -> URL? {
        let hosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
                     "facetime.apple.com", "webex.com", "whereby.com", "jit.si"]
        var texts: [String] = []
        if let url = event.url { texts.append(url.absoluteString) }
        if let location = event.location { texts.append(location) }
        if let notes = event.notes { texts.append(notes) }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for text in texts {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector.matches(in: text, options: [], range: range) {
                guard let url = match.url, let host = url.host?.lowercased() else { continue }
                if hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return url }
            }
        }
        return nil
    }

    // MARK: - Przypomnienia

    private func refreshReminders() {
        guard Prefs.on(Prefs.reminders) else { onReminders?([]); return }
        guard remindersGranted else {
            guard !askedReminders else { return }
            askedReminders = true
            let handler: (Bool, Error?) -> Void = { [weak self] ok, _ in
                DispatchQueue.main.async {
                    self?.remindersGranted = ok
                    Log.write("Przypomnienia: dostęp \(ok ? "przyznany" : "nieprzyznany")")
                    if ok { self?.refreshReminders() }
                }
            }
            if #available(macOS 14.0, *) {
                store.requestFullAccessToReminders(completion: handler)
            } else {
                store.requestAccess(to: .reminder, completion: handler)
            }
            return
        }

        let now = Date()
        let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: now)
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: endOfDay, calendars: nil)
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            let list = (reminders ?? [])
                .sorted { ($0.dueDateComponents?.date ?? .distantFuture) < ($1.dueDateComponents?.date ?? .distantFuture) }
                .prefix(6)
            DispatchQueue.main.async {
                guard let self else { return }
                self.reminderCache = [:]
                let items: [ReminderItem] = list.map { reminder in
                    let id = reminder.calendarItemIdentifier
                    self.reminderCache[id] = reminder
                    let due = reminder.dueDateComponents?.date
                    return ReminderItem(id: id, title: reminder.title ?? "Przypomnienie", due: due,
                                        overdue: (due ?? now) < Calendar.current.startOfDay(for: now))
                }
                self.onReminders?(items)
            }
        }
    }

    /// Odhacza przypomnienie (zapisuje w aplikacji Przypomnienia).
    func complete(_ id: String) {
        guard let reminder = reminderCache[id] else { return }
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
            Log.write("Przypomnienie odhaczone: \(reminder.title ?? "")")
        } catch {
            Log.write("Przypomnienie – błąd zapisu: \(error.localizedDescription)")
        }
        refreshReminders()
    }
}
