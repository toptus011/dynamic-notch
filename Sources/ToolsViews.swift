// ToolsViews.swift – minutnik, stoper, półka na pliki (z AirDrop) i historia schowka
// Bez @State – stan trzyma NotchModel (w macOS Tahoe @State wymaga pełnego Xcode).

import Cocoa
import SwiftUI
import UniformTypeIdentifiers

private let dimText = Color(white: 0.62)

// MARK: - Przeciąganie plików nad wcięcie

struct NotchDropDelegate: DropDelegate {
    let model: NotchModel

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.fileURL])
    }

    func dropEntered(info: DropInfo) {
        if !model.expanded { model.dropTargeted = true }
        update(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        model.dropTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        let toAirDrop = model.dropTargeted && model.dropZone == 1
        let wasExpanded = model.expanded
        model.dropTargeted = false
        let providers = info.itemProviders(for: [UTType.fileURL])
        Self.loadURLs(providers) { urls in
            guard !urls.isEmpty else { return }
            if toAirDrop {
                ShelfTools.airDrop(urls)
                return
            }
            model.addToShelf(urls)
            if wasExpanded {
                model.panelTab = 3
            } else {
                model.showAlert(NotchAlert(symbol: "tray.full.fill", tint: .controlAccentColor,
                                           title: tr("Odłożono na półkę", "Added to shelf"),
                                           subtitle: ShelfTools.filesText(urls.count) + tr(" · kliknij wcięcie → Półka", " · click the notch → Shelf")),
                                duration: 3)
            }
        }
        return true
    }

    /// Lewa połowa karty – półka, prawa – AirDrop.
    private func update(_ info: DropInfo) {
        let width = model.size(for: .drop).width + 2 * model.ear
        let zone = info.location.x < width / 2 ? 0 : 1
        if model.dropZone != zone { model.dropZone = zone }
    }

    static func loadURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let direct = item as? URL {
                    url = direct
                }
                if let url {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
            }
        }
        group.notify(queue: .main) { completion(urls) }
    }
}

/// Karta podczas przeciągania: „Odłóż na półkę” | „Wyślij AirDrop”.
struct DropCard: View {
    @ObservedObject var model: NotchModel
    let topInset: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            zone(index: 0, symbol: "tray.and.arrow.down.fill", title: tr("Odłóż na półkę", "Add to shelf"), tint: systemAccent)
            zone(index: 1, symbol: "dot.radiowaves.left.and.right", title: tr("Wyślij AirDrop", "Send via AirDrop"), tint: .cyan)
        }
        .padding(.horizontal, 12)
        .padding(.top, topInset)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundColor(.white)
    }

    private func zone(index: Int, symbol: String, title: String, tint: Color) -> some View {
        let active = model.dropZone == index
        return VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(active ? tint : dimText)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(active ? .white : dimText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(active ? 0.14 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: active ? [] : [4, 3]))
                .foregroundColor(active ? tint.opacity(0.8) : Color.white.opacity(0.2))
        )
        .animation(.easeInOut(duration: 0.15), value: active)
    }
}

// MARK: - Kompaktowy minutnik / stoper

struct TimerRow: View {
    @ObservedObject var model: NotchModel
    let secondaryDot: Bool
    let height: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 7) {
                if let end = model.timerEnd {
                    Image(systemName: "timer").foregroundColor(.orange).frame(width: 18)
                    Text(tr("Minutnik", "Timer"))
                    Spacer(minLength: 4)
                    Text(NotchModel.clockText(end.timeIntervalSince(context.date) + 0.999))
                        .foregroundColor(.orange)
                } else {
                    Image(systemName: "stopwatch").foregroundColor(.orange).frame(width: 18)
                    Text(tr("Stoper", "Stopwatch"))
                    Spacer(minLength: 4)
                    Text(NotchModel.clockText(model.stopwatchElapsed(at: context.date)))
                        .foregroundColor(.orange)
                }
                if secondaryDot {
                    Circle().fill(Color.green).frame(width: 6, height: 6).accessibilityLabel(tr("Muzyka gra", "Music playing"))
                }
            }
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .frame(height: height)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Zakładka „Narzędzia”: minutnik i stoper (po lewej), lista „Do zrobienia” (po prawej)

struct ToolsView: View {
    @ObservedObject var model: NotchModel

    private let presets: [[Double]] = [[1, 3, 5, 10, 15], [20, 25, 30, 45, 60]]

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                timer
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                stopwatch
            }
            .frame(width: 196, alignment: .leading)
            checklist
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11, weight: .medium))
    }

    // Minutnik: nagłówek z czasem po prawej, pod spodem przyciski minut albo „+1 min / Zatrzymaj”
    private var timer: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                label(tr("Minutnik", "Timer"), symbol: "timer")
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(model.timerEnd.map { NotchModel.clockText($0.timeIntervalSince(context.date) + 0.999) } ?? "0:00")
                        .font(.system(size: 20, weight: .semibold).monospacedDigit())
                        .foregroundColor(model.timerEnd == nil ? dimText : .orange)
                }
            }
            if model.timerEnd != nil {
                HStack(spacing: 6) {
                    pill("+1 min", tint: Color(white: 0.2)) { model.addTimerMinute() }
                    pill(tr("Zatrzymaj", "Stop"), tint: Color.red.opacity(0.7)) { model.stopTimer() }
                }
            } else {
                ForEach(Array(presets.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 4) {
                        ForEach(row, id: \.self) { minutes in
                            pill("\(Int(minutes))", tint: Color(white: 0.2)) { model.startTimer(minutes: minutes) }
                                .help(tr("Minutnik", "Timer") + ": \(Int(minutes)) min")
                        }
                    }
                }
            }
        }
    }

    private var stopwatch: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                label(tr("Stoper", "Stopwatch"), symbol: "stopwatch")
                Spacer()
                TimelineView(.periodic(from: .now, by: model.stopwatchRunning ? 0.1 : 60)) { context in
                    Text(Self.stopwatchText(model.stopwatchElapsed(at: context.date)))
                        .font(.system(size: 20, weight: .semibold).monospacedDigit())
                        .foregroundColor(model.stopwatchRunning ? .orange
                                         : (model.stopwatchAccumulated > 0 ? .white : dimText))
                }
            }
            HStack(spacing: 6) {
                pill(model.stopwatchRunning ? tr("Pauza", "Pause") : (model.stopwatchAccumulated > 0 ? tr("Wznów", "Resume") : "Start"),
                     tint: model.stopwatchRunning ? Color.orange.opacity(0.75) : Color.green.opacity(0.7)) {
                    model.toggleStopwatch()
                }
                pill(tr("Zeruj", "Reset"), tint: Color(white: 0.2)) { model.resetStopwatch() }
                    .opacity(model.stopwatchAccumulated > 0 || model.stopwatchRunning ? 1 : 0.4)
            }
        }
    }

    // Lista „Do zrobienia”: pole do wpisania (Enter dodaje), kółko odhacza, × usuwa
    private var checklist: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                label(tr("Do zrobienia", "To do"), symbol: "checklist")
                Spacer()
                if model.todos.contains(where: { $0.done }) {
                    Button(action: { model.clearDoneTodos() }) {
                        Text(tr("Usuń zrobione", "Clear done")).font(.system(size: 10)).foregroundColor(dimText)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 5) {
                TextField(tr("Dodaj zadanie…", "Add a task…"), text: Binding(get: { model.newTodoText },
                                                          set: { model.newTodoText = $0 }))
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .onSubmit { model.addTodo() }
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(TileBackground())
                Button(action: { model.addTodo() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(systemAccent.opacity(model.newTodoText.isEmpty ? 0.3 : 0.85)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("Dodaj zadanie", "Add task"))
            }
            if model.todos.isEmpty {
                Text(tr("Wpisz zadanie i naciśnij Enter. Lista zostaje po ponownym uruchomieniu.", "Type a task and press Return. The list is kept after restart."))
                    .font(.system(size: 10))
                    .foregroundColor(dimText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(model.todos) { todo in
                            todoRow(todo)
                        }
                    }
                }
            }
        }
    }

    private func todoRow(_ todo: TodoItem) -> some View {
        HStack(spacing: 6) {
            Button(action: { model.toggleTodo(todo.id) }) {
                Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundColor(todo.done ? .green : .orange)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(todo.done ? tr("Oznacz jako niezrobione", "Mark as not done") : tr("Odhacz", "Complete"))
            Text(todo.title)
                .strikethrough(todo.done)
                .foregroundColor(todo.done ? dimText : .white)
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 2)
            Button(action: { model.deleteTodo(todo.id) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(dimText)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("Usuń zadanie", "Delete task"))
        }
        .padding(.horizontal, 5)
        .frame(height: 26)
        .background(TileBackground())
    }

    private func label(_ title: String, symbol: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(title)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(dimText)
    }

    private func pill(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundColor(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .frame(minWidth: 32)
                .background(Capsule().fill(tint))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// „1:05,3”
    static func stopwatchText(_ t: TimeInterval) -> String {
        let tenths = Int((t * 10).rounded(.down))
        let s = tenths / 10
        return String(format: "%d:%02d,%d", s / 60, s % 60, tenths % 10)
    }
}

// MARK: - Zakładka „Półka”: pliki i historia schowka

struct ShelfView: View {
    @ObservedObject var model: NotchModel
    let actions: NotchActions

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            shelf.frame(maxWidth: .infinity, alignment: .leading)
            clipboard.frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11, weight: .medium))
    }

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                header(tr("Półka", "Shelf"))
                Spacer()
                if !model.shelf.isEmpty {
                    smallButton("dot.radiowaves.left.and.right", help: tr("Wyślij wszystko przez AirDrop", "Send all via AirDrop")) {
                        actions.collapse()
                        ShelfTools.airDrop(model.shelf)
                    }
                    smallButton("trash", help: tr("Wyczyść półkę", "Clear shelf")) { model.clearShelf() }
                }
            }
            if model.shelf.isEmpty {
                hint(tr("Przeciągnij pliki na wcięcie – zostaną tu, aż będą potrzebne.", "Drag files onto the notch – they stay here until you need them."))
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 5) {
                        ForEach(model.shelf.reversed(), id: \.self) { url in
                            fileTile(url)
                        }
                    }
                }
            }
        }
    }

    private func fileTile(_ url: URL) -> some View {
        HStack(spacing: 7) {
            Image(nsImage: ShelfTools.icon(url))
                .resizable()
                .frame(width: 20, height: 20)
            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 2)
            Button(action: { model.removeFromShelf(url) }) {
                Image(systemName: "xmark.circle.fill").foregroundColor(dimText)
                    .frame(width: 18, height: 18).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("Usuń z półki", "Remove from shelf"))
        }
        .padding(.horizontal, 7)
        .frame(height: 30)
        .background(TileBackground())
        .contentShape(Rectangle())
        .onTapGesture {
            actions.collapse()
            ShelfTools.open(url)
        }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu {
            Button(tr("Otwórz", "Open")) { ShelfTools.open(url) }
            Button(tr("Pokaż w Finderze", "Show in Finder")) { ShelfTools.reveal(url) }
            Button(tr("Wyślij przez AirDrop", "Send via AirDrop")) { ShelfTools.airDrop([url]) }
            Divider()
            Button(tr("Usuń z półki", "Remove from shelf")) { model.removeFromShelf(url) }
        }
        .help(tr("Kliknij, aby otworzyć · przeciągnij, aby wstawić lub przenieść", "Click to open · drag to insert or move"))
    }

    private var clipboard: some View {
        VStack(alignment: .leading, spacing: 6) {
            header(tr("Ostatnio skopiowane", "Recently copied"))
            if !Prefs.on(Prefs.clipboardHistory) {
                hint(tr("Historia schowka jest wyłączona (prywatność). Włączysz ją w Ustawieniach → Narzędzia.",
                        "Clipboard history is off (privacy). Turn it on in Settings → Tools."))
            } else if model.clipboardHistory.isEmpty {
                hint(tr("Skopiuj tekst (⌘C) – pojawi się tutaj. Historia nie jest zapisywana na dysku.",
                        "Copy text (⌘C) – it appears here. History is never saved to disk."))
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 5) {
                        ForEach(model.clipboardHistory, id: \.self) { text in
                            Text(text.replacingOccurrences(of: "\n", with: " "))
                                .lineLimit(1).truncationMode(.tail)
                                .padding(.horizontal, 8)
                                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                                .background(TileBackground())
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    ClipboardMonitor.shared.copy(text)
                                    model.rememberClip(text)
                                    actions.collapse()
                                }
                                .help(tr("Kliknij, aby skopiować ponownie", "Click to copy again"))
                        }
                    }
                }
            }
        }
    }

    private func header(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .medium)).foregroundColor(dimText)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundColor(dimText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundColor(Color.white.opacity(0.18))
            )
    }

    private func smallButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(dimText)
                .frame(width: 20, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
