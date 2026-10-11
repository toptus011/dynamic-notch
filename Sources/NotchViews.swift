// NotchViews.swift – wygląd wcięcia (SwiftUI): kształt, stany, karty i rozwinięty panel
// Zgodnie z wytycznymi Apple: tło zawsze czarne, symbole SF Symbols, czcionka systemowa,
// cyfry o stałej szerokości, koncentryczne zaokrąglenia, „Ogranicz ruch”, opisy dla VoiceOvera.
// Uwaga: bez @State/@AppStorage – w macOS Tahoe są makrami wymagającymi pełnego Xcode.

import Cocoa
import SwiftUI
import UniformTypeIdentifiers

/// Czynności wywoływane z widoku – realizuje je kontroler okna i AppDelegate.
struct NotchActions {
    var toggle: () -> Void
    var collapse: () -> Void
    var hover: (Bool) -> Void
    var playPause: () -> Void
    var next: () -> Void
    var previous: () -> Void
    var setVolume: (Float) -> Void
    var setBrightness: (Float) -> Void
    var settings: () -> Void
    var log: () -> Void
    var quit: () -> Void
    var openPlayer: () -> Void
    var seek: (Double) -> Void
    var openURL: (URL) -> Void
    var completeReminder: (String) -> Void
    var openCalendar: () -> Void
    var openReminders: () -> Void
    /// Otwiera konkretne wydarzenie w Kalendarzu / przypomnienie w Przypomnieniach
    var openEvent: (CalendarItem) -> Void
    var openReminder: (String) -> Void
}

// MARK: - Kształt wcięcia w stylu MacBooka

/// Płaska góra przyklejona do krawędzi ekranu, zaokrąglony dół i opcjonalne wklęsłe „uszka”.
struct NotchShape: Shape {
    var bottomRadius: CGFloat
    var ear: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, ear) }
        set {
            bottomRadius = newValue.first
            ear = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let e = max(0, min(ear, w / 4))
        let r = max(0, min(bottomRadius, h / 2, (w - 2 * e) / 2))
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        if e > 0 {
            p.addQuadCurve(to: CGPoint(x: e, y: e), control: CGPoint(x: e, y: 0))
        }
        p.addLine(to: CGPoint(x: e, y: h - r))
        p.addQuadCurve(to: CGPoint(x: e + r, y: h), control: CGPoint(x: e, y: h))
        p.addLine(to: CGPoint(x: w - e - r, y: h))
        p.addQuadCurve(to: CGPoint(x: w - e, y: h - r), control: CGPoint(x: w - e, y: h))
        if e > 0 {
            p.addLine(to: CGPoint(x: w - e, y: e))
            p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - e, y: 0))
        } else {
            p.addLine(to: CGPoint(x: w, y: 0))
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - Przejście z rozmyciem (jak w Dynamic Island)

struct BlurFade: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content
            .blur(radius: active ? 6 : 0)
            .opacity(active ? 0 : 1)
            // Treść „spływa” z góry razem z rozwijającym się kształtem
            .scaleEffect(active ? 0.96 : 1, anchor: .top)
            .offset(y: active ? -6 : 0)
    }
}

extension AnyTransition {
    static var blurFade: AnyTransition {
        .modifier(active: BlurFade(active: true), identity: BlurFade(active: false))
    }
}

// MARK: - Widok główny

struct NotchRootView: View {
    @ObservedObject var model: NotchModel
    let actions: NotchActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var highContrast: Bool { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }

    var body: some View {
        let mode = model.mode
        let size = model.size(for: mode)
        let ear = model.ear
        // „Pęcznienie” pod kursorem tylko w małych stanach
        let swell = model.hovering && mode != .expanded && mode != .alert && mode != .drop && !reduceMotion

        let large = mode == .expanded || mode == .alert || mode == .drop

        ZStack(alignment: .top) {
            // Tło z cieniem (cień rośnie razem z kształtem – nie jest przycinany)
            background(mode: mode, size: size, ear: ear)
                .shadow(color: Color.black.opacity(large || model.dropped ? 0.4 : 0),
                        radius: large ? 18 : 8, x: 0, y: large ? 8 : 3)
            // Treść przycięta do kształtu: przy rozwijaniu odsłania się od góry do dołu
            // razem z rosnącym kształtem.
            content(mode: mode)
                .id(mode)
                .transition(reduceMotion ? .opacity : .blurFade)
                .frame(width: size.width, height: size.height, alignment: .top)
                .frame(width: size.width + 2 * ear, height: size.height, alignment: .top)
                .clipShape(clipShape(mode: mode, size: size, ear: ear))
        }
        .frame(width: size.width + 2 * ear, height: size.height, alignment: .top)
        .scaleEffect(swell ? 1.04 : 1, anchor: .top)
        .contentShape(Rectangle())
        // Przeciągnięcie pliku nad wcięcie: odłożenie na półkę albo AirDrop
        .onDrop(of: [UTType.fileURL], delegate: NotchDropDelegate(model: model))
        // Najechanie kursorem wykrywa kontroler okna (okno przepuszcza kliknięcia poza wcięciem).
        .onTapGesture { if mode != .expanded { actions.toggle() } }
        .contextMenu {
            Button(tr("Ustawienia…", "Settings…")) { actions.settings() }
            Button(tr("Pokaż dziennik zdarzeń", "Show event log")) { actions.log() }
            Divider()
            Button(tr("Zakończ Dynamic Notch", "Quit Dynamic Notch")) { actions.quit() }
        }
        .offset(x: model.shapeOffset.width, y: model.shapeOffset.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.85),
                   value: mode)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: size)
        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: model.shapeOffset)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: swell)
        .animation(.easeInOut(duration: 0.2), value: model.dropped)
        .environment(\.colorScheme, .dark)
    }

    /// Kształt przycięcia – ten sam co tło (płaska góra przy pasku menu, zaokrąglony dół).
    private func clipShape(mode: NotchMode, size: CGSize, ear: CGFloat) -> AnyShape {
        let large = mode == .expanded || mode == .alert || mode == .drop
        if model.dropped {
            return AnyShape(RoundedRectangle(cornerRadius: large ? 16 : size.height / 2, style: .continuous))
        }
        return AnyShape(NotchShape(bottomRadius: large ? 16 : 8, ear: large ? 0 : ear))
    }

    /// macOS 27: mniej zaokrąglone narożniki (16 pkt) dla karty i panelu, Liquid Glass.
    /// Małe wcięcie zostaje czarne – jak sprzętowe wcięcie MacBooka.
    @ViewBuilder
    private func background(mode: NotchMode, size: CGSize, ear: CGFloat) -> some View {
        let large = mode == .expanded || mode == .alert || mode == .drop
        if model.dropped {
            let shape = RoundedRectangle(cornerRadius: large ? 16 : size.height / 2, style: .continuous)
            if large {
                GlassBackground(shape: shape, highContrast: highContrast)
                    .frame(width: size.width, height: size.height)
            } else {
                shape.fill(Color.black)
                    .overlay(shape.stroke(Color.white.opacity(highContrast ? 0.5 : 0.12), lineWidth: 1))
                    .frame(width: size.width, height: size.height)
            }
        } else if large {
            GlassBackground(shape: NotchShape(bottomRadius: 16, ear: 0), highContrast: highContrast)
                .frame(width: size.width + 2 * ear, height: size.height)
        } else {
            NotchShape(bottomRadius: 8, ear: ear)
                .fill(Color.black)
                .overlay(NotchShape(bottomRadius: 8, ear: ear)
                    .stroke(Color.white.opacity(highContrast ? 0.5 : 0), lineWidth: 1))
                .frame(width: size.width + 2 * ear, height: size.height)
        }
    }

    @ViewBuilder
    private func content(mode: NotchMode) -> some View {
        switch mode {
        case .idle:
            ZStack {
                Color.clear
                if model.screenRecording {
                    // Nagrywanie ekranu – mała czerwona kropka, jak wskaźnik w iPhonie
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                        .accessibilityLabel(tr("Trwa nagrywanie ekranu", "Screen recording in progress"))
                }
            }
            .frame(height: model.barHeight)
            .accessibilityLabel("Dynamic Notch")
        case .timer:
            TimerRow(model: model, secondaryDot: model.showsSecondaryDot, height: model.barHeight)
        case .drop:
            DropCard(model: model, topInset: model.dropped ? 0 : model.barHeight * 0.35)
        case .alert:
            if let alert = model.alert {
                AlertCard(alert: alert, topInset: model.dropped ? 0 : model.barHeight * 0.35,
                          openURL: actions.openURL,
                          addToShelf: { url in
                              model.addToShelf([url])
                              model.alert = nil
                          })
            }
        case .activity:
            if let activity = model.activity {
                ActivityRow(activity: activity, secondaryDot: model.showsSecondaryDot, height: model.barHeight)
            }
        case .music:
            if let np = model.nowPlaying {
                MusicRow(nowPlaying: np, height: model.barHeight, openPlayer: actions.openPlayer)
            }
        case .expanded:
            ExpandedPanel(model: model, actions: actions)
        }
    }
}

// MARK: - Wspólne elementy

private let secondaryText = Color(white: 0.62)
/// Kolor akcentu wybrany w Ustawieniach systemowych → Wygląd
var systemAccent: Color { Color(nsColor: .controlAccentColor) }

func batterySymbol(_ level: Int, onAC: Bool) -> String {
    if onAC { return "battery.100.bolt" }
    switch level {
    case 88...: return "battery.100"
    case 63..<88: return "battery.75"
    case 38..<63: return "battery.50"
    case 13..<38: return "battery.25"
    default: return "battery.0"
    }
}

private func volumeSymbol(_ value: Float, muted: Bool) -> String {
    if muted || value < 0.01 { return "speaker.slash.fill" }
    if value < 0.34 { return "speaker.wave.1.fill" }
    if value < 0.67 { return "speaker.wave.2.fill" }
    return "speaker.wave.3.fill"
}

private func timeText(_ seconds: Double) -> String {
    let s = max(0, Int(seconds.rounded()))
    return String(format: "%d:%02d", s / 60, s % 60)
}

private func hourText(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
}

private let weekdayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Lang.locale
    f.dateFormat = "EEE"
    return f
}()

/// „dziś 18:00”, „jutro 7:00”, „pon. 18:00”
func dayTimeText(_ date: Date, now: Date) -> String {
    let calendar = Calendar.current
    let day: String
    if calendar.isDate(date, inSameDayAs: now) {
        day = tr("dziś", "today")
    } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
              calendar.isDate(date, inSameDayAs: tomorrow) {
        day = tr("jutro", "tomorrow")
    } else {
        day = weekdayFormatter.string(from: date)
    }
    return "\(day) \(hourText(date))"
}

/// Tło karty i panelu w stylu macOS 27: głęboka czerń jak sprzętowe wcięcie, z delikatnym
/// refleksem światła na dolnej krawędzi i lekką poświatą u dołu (bez ramki wokół okna).
/// Kształt łączy się z paskiem menu, więc górna krawędź nie ma obwódki.
struct GlassBackground<S: Shape>: View {
    let shape: S
    let highContrast: Bool

    var body: some View {
        ZStack {
            shape.fill(Color.black)
            // Lekka głębia: odrobinę jaśniejszy dół – jak szkło podświetlone od spodu
            shape.fill(LinearGradient(colors: [Color.white.opacity(0), Color.white.opacity(highContrast ? 0 : 0.035)],
                                      startPoint: .top, endPoint: .bottom))
            // Refleks na krawędzi: niewidoczny u góry (przy pasku menu), wyraźniejszy na dole
            shape.stroke(LinearGradient(colors: [Color.white.opacity(0),
                                                 Color.white.opacity(0),
                                                 Color.white.opacity(highContrast ? 0.55 : 0.16)],
                                        startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
        .compositingGroup()
    }
}

/// Kafelek w panelu – półprzezroczysty, z delikatną krawędzią (macOS 27).
struct TileBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.5))
    }
}

/// Pasek postępu utworu – kliknięcie lub przeciągnięcie przewija utwór.
struct ScrubBar: View {
    var progress: Double
    var onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(white: 0.25)).frame(height: 4)
                Capsule().fill(Color.white)
                    .frame(width: max(0, min(1, progress)) * geo.size.width, height: 4)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                let fraction = max(0, min(1, value.location.x / max(geo.size.width, 1)))
                onSeek(fraction)
            })
        }
        .frame(height: 12)
        .accessibilityLabel(tr("Postęp utworu", "Track position"))
        .accessibilityValue(tr("\(Int(progress * 100)) procent", "\(Int(progress * 100)) percent"))
    }
}

/// Korektor przy grającej muzyce: 5 słupków o nieregularnym, „muzycznym” ruchu,
/// w kolorze dopasowanym do okładki. W trybie niskiego zużycia energii animacja zostaje,
/// tylko z mniejszą liczbą klatek; przy „Ogranicz ruch” słupki stoją nieruchomo.
struct Waveform: View {
    var active: Bool
    var tint: Color = .green
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let speeds1: [Double] = [6.1, 8.3, 5.2, 7.4, 9.1]
    private static let speeds2: [Double] = [11.7, 9.4, 13.1, 10.2, 12.6]
    private static let offsets: [Double] = [0.0, 1.7, 3.1, 4.4, 2.3]
    private static let still: [CGFloat] = [6, 10, 8, 12, 7]

    var body: some View {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let moving = active && !reduceMotion
        TimelineView(.animation(minimumInterval: lowPower ? 1.0 / 12 : 1.0 / 30, paused: !moving)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<5) { i in
                    Capsule()
                        .fill(tint)
                        .frame(width: 3, height: moving ? Self.height(i, time: t) : (active ? Self.still[i] : 3))
                }
            }
            .frame(width: 23, height: 14)
        }
        .accessibilityHidden(true)
    }

    private static func height(_ i: Int, time: Double) -> CGFloat {
        let a = sin(time * speeds1[i] + offsets[i])
        let b = sin(time * speeds2[i] + offsets[i] * 1.9) * 0.6
        let level = max(0, min(1, (a + b + 1.6) / 3.2))
        return 3 + 11 * CGFloat(level)
    }
}

struct Artwork: View {
    var image: NSImage?
    var size: CGFloat
    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color(white: 0.2)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.5, weight: .semibold))
                        .foregroundColor(secondaryText)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

private struct SecondaryDot: View {
    var body: some View {
        Circle().fill(Color.green).frame(width: 6, height: 6)
            .accessibilityLabel(tr("Muzyka gra", "Music playing"))
    }
}

// MARK: - Stany kompaktowe

struct ActivityRow: View {
    let activity: Activity
    let secondaryDot: Bool
    let height: CGFloat

    var body: some View {
        HStack(spacing: 7) {
            row
            if secondaryDot { SecondaryDot() }
        }
        .font(.system(size: 12, weight: .medium).monospacedDigit())
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .frame(height: height)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var row: some View {
        switch activity {
        case let .power(level, _, onAC):
            Image(systemName: onAC ? "bolt.fill" : batterySymbol(level, onAC: false))
                .foregroundColor(onAC ? .green : .white).frame(width: 18)
            Text(onAC ? tr("Ładowanie", "Charging") : tr("Na baterii", "On battery"))
            Spacer(minLength: 4)
            Text("\(level)%").foregroundColor(onAC ? .green : .white)
        case let .copied(symbol, preview):
            Image(systemName: symbol).foregroundColor(systemAccent).frame(width: 18)
            Text(tr("Skopiowano", "Copied"))
            Spacer(minLength: 4)
            Text(preview).foregroundColor(secondaryText).lineLimit(1).truncationMode(.tail)
        }
    }
}

struct MusicRow: View {
    let nowPlaying: NowPlaying
    let height: CGFloat
    var openPlayer: () -> Void = {}

    var body: some View {
        HStack(spacing: 7) {
            Artwork(image: nowPlaying.artwork, size: 16)
                .onTapGesture { openPlayer() }
                .help(tr("Otwórz", "Open") + " \(nowPlaying.player.displayName)")
            Text(nowPlaying.title).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            Waveform(active: nowPlaying.playing, tint: nowPlaying.tint.map { Color($0) } ?? .green)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .frame(height: height)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tr("Odtwarzanie", "Playing") + ": \(nowPlaying.title), \(nowPlaying.artist)")
    }
}

// MARK: - Karta powiadomienia

/// Powiększona karta powiadomienia – czytelna jak alert w Dynamic Island.
struct AlertCard: View {
    let alert: NotchAlert
    let topInset: CGFloat
    var openURL: (URL) -> Void = { _ in }
    var addToShelf: (URL) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 12) {
            if let image = alert.image, let url = alert.fileURL {
                // Miniatura zrzutu: kliknięcie otwiera, przeciągnięcie wstawia do dokumentu
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                    .onTapGesture { ShelfTools.open(url) }
                    .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                    .help(tr("Kliknij, aby otworzyć · przeciągnij do dokumentu", "Click to open · drag into a document"))
            } else {
                ZStack {
                    Circle().fill(Color(alert.tint).opacity(0.22))
                    Image(systemName: alert.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(alert.tint))
                }
                .frame(width: 40, height: 40)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1).truncationMode(.tail)
                Text(alert.subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.7))
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 6)
            if let title = alert.actionTitle, let url = alert.actionURL {
                Button(action: { alert.shelfAction ? addToShelf(url) : openURL(url) }) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(systemAccent))
                }
                .buttonStyle(.plain)
            } else if !alert.badge.isEmpty {
                Text(alert.badge)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundColor(Color(alert.badgeColor))
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.top, topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Rozwinięty panel z zakładkami

struct ExpandedPanel: View {
    @ObservedObject var model: NotchModel
    let actions: NotchActions

    /// Zakładki – skróty ⌘1…⌘4
    static let tabTitles = [tr("Teraz", "Now"), tr("Tydzień", "Week"), tr("Narzędzia", "Tools"), tr("Półka", "Shelf")]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            tabs
            switch model.panelTab {
            case 0:
                HStack(alignment: .top, spacing: 18) {
                    player.frame(width: 230, alignment: .leading)
                    controls
                }
                .transition(.opacity)
            case 1:
                TodayView(model: model, actions: actions)
                    .transition(.opacity)
            case 2:
                ToolsView(model: model)
                    .transition(.opacity)
            default:
                ShelfView(model: model, actions: actions)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .foregroundColor(.white)
        .animation(.easeInOut(duration: 0.2), value: model.panelTab)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(model.clock, style: .time)
            Text("·")
            Image(systemName: batterySymbol(model.batteryLevel, onAC: model.onAC))
            Text("\(model.batteryLevel)%").monospacedDigit()
            Spacer()
            Button(action: actions.collapse) {
                Image(systemName: "chevron.up").frame(width: 24, height: 20).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("Zwiń", "Close"))
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(secondaryText)
        .frame(height: model.barHeight)
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            Spacer()
            ForEach(Array(Self.tabTitles.enumerated()), id: \.offset) { index, title in
                Button(action: { model.panelTab = index }) {
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(model.panelTab == index ? .white : secondaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(model.panelTab == index ? Color(white: 0.2) : Color.clear))
                }
                .buttonStyle(.plain)
                .help("\(title) (⌘\(index + 1))")
                .accessibilityAddTraits(model.panelTab == index ? .isSelected : [])
            }
            Spacer()
        }
    }

    @ViewBuilder private var player: some View {
        if let np = model.nowPlaying {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Artwork(image: np.artwork, size: 52)
                        .onTapGesture { actions.openPlayer() }
                        .help(tr("Otwórz", "Open") + " \(np.player.displayName)")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint(tr("Otwiera odtwarzacz", "Opens the player"))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(np.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(np.artist).font(.system(size: 11)).foregroundColor(secondaryText).lineLimit(1)
                    }
                }
                if let duration = np.duration, duration > 0 {
                    // Postęp liczony na żywo co pół sekundy – bez ciągłego pytania odtwarzacza.
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        let position = np.livePosition(at: context.date)
                        VStack(spacing: 2) {
                            ScrubBar(progress: position / duration) { fraction in
                                actions.seek(fraction * duration)
                            }
                            HStack {
                                Text(timeText(position))
                                Spacer()
                                Text("-" + timeText(duration - position))
                            }
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundColor(secondaryText)
                        }
                    }
                }
                HStack(spacing: 22) {
                    controlButton("backward.fill", label: tr("Poprzedni utwór", "Previous track"), action: actions.previous)
                    controlButton(np.playing ? "pause.fill" : "play.fill",
                                  label: np.playing ? tr("Pauza", "Pause") : tr("Odtwarzaj", "Play"), action: actions.playPause, size: 20)
                    controlButton("forward.fill", label: tr("Następny utwór", "Next track"), action: actions.next)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(10)
            // Delikatna poświata w barwach okładki – jak w Muzyce na iPhonie
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(np.tint ?? .systemGray).opacity(0.18)))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "music.note").font(.system(size: 22)).foregroundColor(secondaryText)
                Text(tr("Nic nie jest odtwarzane", "Nothing playing")).font(.system(size: 12, weight: .medium))
                Button(action: actions.openPlayer) {
                    Text(tr("Otwórz Muzykę", "Open Music")).font(.system(size: 11)).foregroundColor(systemAccent)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
        }
    }

    private func controlButton(_ symbol: String, label: String, action: @escaping () -> Void,
                               size: CGFloat = 16) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            sliderRow(symbol: volumeSymbol(model.volume, muted: model.muted), label: tr("Głośność", "Volume"),
                      value: Binding(get: { Double(model.volume) }, set: { actions.setVolume(Float($0)) }))
            if let brightness = model.brightness {
                sliderRow(symbol: "sun.max.fill", label: tr("Jasność", "Brightness"),
                          value: Binding(get: { Double(brightness) }, set: { actions.setBrightness(Float($0)) }))
            }
            devicesSection
            if model.micInUse || model.cameraInUse {
                tile(symbol: model.cameraInUse ? "video.fill" : "mic.fill",
                     title: model.cameraInUse ? tr("Kamera w użyciu", "Camera in use") : tr("Mikrofon w użyciu", "Microphone in use"), value: "")
            }
            if let event = model.nextEvent {
                tile(symbol: "calendar", title: event.title, value: dayTimeText(event.start, now: model.clock))
                    .contentShape(Rectangle())
                    .onTapGesture { actions.openEvent(event) }
                    .help(tr("Otwórz w Kalendarzu", "Open in Calendar"))
            }
        }
    }

    /// Połączone urządzenia: zwinięte – jedno (najważniejsze) i liczba; rozwinięte – pełna lista.
    @ViewBuilder private var devicesSection: some View {
        let all = model.allDevices
        if let first = all.first(where: { $0.symbol.hasPrefix("airpods") }) ?? all.first {
            VStack(spacing: 3) {
                Button(action: { model.devicesListOpen.toggle() }) {
                    HStack(spacing: 7) {
                        Image(systemName: model.devicesListOpen ? "cable.connector.horizontal" : first.symbol)
                            .font(.system(size: 12)).frame(width: 18)
                        Text(model.devicesListOpen ? tr("Połączone urządzenia", "Connected devices") : first.name)
                            .lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 4)
                        Text("\(all.count)").monospacedDigit().foregroundColor(secondaryText)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(secondaryText)
                            .rotationEffect(.degrees(model.devicesListOpen ? 180 : 0))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(TileBackground())
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(model.devicesListOpen ? tr("Zwiń listę", "Collapse list") : tr("Pokaż wszystkie połączone urządzenia", "Show all connected devices"))
                .accessibilityLabel(tr("Połączone urządzenia", "Connected devices") + ": \(all.count)")

                if model.devicesListOpen {
                    VStack(spacing: 2) {
                        ForEach(all.prefix(6)) { device in
                            HStack(spacing: 7) {
                                Image(systemName: device.symbol).font(.system(size: 11)).frame(width: 18)
                                Text(device.name).lineLimit(1).truncationMode(.tail)
                                Spacer(minLength: 4)
                                Text(device.kind).font(.system(size: 9, weight: .medium))
                                    .foregroundColor(secondaryText)
                            }
                            .font(.system(size: 11))
                            .padding(.horizontal, 9)
                            .frame(height: 26)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.04)))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: model.devicesListOpen)
        } else {
            tile(symbol: "cable.connector.horizontal", title: tr("Brak połączonych urządzeń", "No connected devices"), value: "")
        }
    }

    private func sliderRow(symbol: String, label: String, value: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 12)).frame(width: 18)
            Slider(value: value, in: 0...1)
                .controlSize(.small)
                .tint(.white)
                .accessibilityLabel(label)
        }
    }

    private func tile(symbol: String, title: String, value: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 12)).frame(width: 18)
            Text(title).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            Text(value).monospacedDigit().foregroundColor(secondaryText)
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(TileBackground())
        .accessibilityElement(children: .combine)
    }
}

/// Zakładka „Dziś”: wydarzenia z Kalendarza i przypomnienia do odhaczenia.
struct TodayView: View {
    @ObservedObject var model: NotchModel
    let actions: NotchActions

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                sectionHeader(tr("Najbliższe 7 dni", "Next 7 days"), app: tr("Kalendarz", "Calendar"), action: actions.openCalendar)
                if model.todayEvents.isEmpty {
                    emptyTile(tr("Brak wydarzeń w tym tygodniu", "No events this week"))
                        .onTapGesture { actions.openCalendar() }
                } else {
                    ForEach(model.todayEvents.prefix(5)) { event in
                        eventTile(event)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                sectionHeader(tr("Przypomnienia", "Reminders"), app: tr("Przypomnienia", "Reminders"), action: actions.openReminders)
                if model.reminders.isEmpty {
                    emptyTile(tr("Wszystko zrobione", "All done"))
                        .onTapGesture { actions.openReminders() }
                } else {
                    ForEach(model.reminders.prefix(4)) { reminder in
                        reminderTile(reminder)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11, weight: .medium))
    }

    private func eventTile(_ event: CalendarItem) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 1.5).fill(Color(event.color)).frame(width: 3, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).lineLimit(1).truncationMode(.tail)
                Text("\(dayTimeText(event.start, now: model.clock)) – \(hourText(event.end))")
                    .font(.system(size: 10).monospacedDigit()).foregroundColor(secondaryText)
            }
            Spacer(minLength: 4)
            if let url = event.meetingURL {
                Button(action: { actions.openURL(url) }) {
                    Text(tr("Dołącz", "Join"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(systemAccent))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background(TileBackground())
        .contentShape(Rectangle())
        .onTapGesture { actions.openEvent(event) }
        .help(tr("Otwórz w Kalendarzu", "Open in Calendar"))
        .accessibilityElement(children: .combine)
    }

    private func reminderTile(_ reminder: ReminderItem) -> some View {
        HStack(spacing: 7) {
            Button(action: { actions.completeReminder(reminder.id) }) {
                Image(systemName: "circle")
                    .font(.system(size: 13))
                    .foregroundColor(reminder.overdue ? .red : .orange)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("Odhacz", "Complete") + ": \(reminder.title)")
            Text(reminder.title).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(height: 30)
        .background(TileBackground())
        .contentShape(Rectangle())
        .onTapGesture { actions.openReminder(reminder.id) }
        .help(tr("Otwórz w Przypomnieniach", "Open in Reminders"))
    }

    private func emptyTile(_ text: String) -> some View {
        Text(text)
            .foregroundColor(secondaryText)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .background(TileBackground())
            .contentShape(Rectangle())
    }

    /// Nagłówek sekcji – kliknięcie otwiera aplikację (Kalendarz / Przypomnienia).
    private func sectionHeader(_ title: String, app: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(title)
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(secondaryText)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tr("Otwórz", "Open") + " \(app)")
        .accessibilityLabel("\(title) – " + tr("otwórz", "open") + " \(app)")
    }
}
