// NotchViews.swift – wygląd wcięcia (SwiftUI): kształt, stany, karty i rozwinięty panel
// Zgodnie z wytycznymi Apple: tło zawsze czarne, symbole SF Symbols, czcionka systemowa,
// cyfry o stałej szerokości, koncentryczne zaokrąglenia, „Ogranicz ruch”, opisy dla VoiceOvera.
// Uwaga: bez @State/@AppStorage – w macOS Tahoe są makrami wymagającymi pełnego Xcode.

import Cocoa
import SwiftUI

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
            .scaleEffect(active ? 0.92 : 1)
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
        let swell = model.hovering && mode != .expanded && mode != .alert && !reduceMotion

        ZStack(alignment: .top) {
            background(mode: mode, size: size, ear: ear)
            content(mode: mode)
                .id(mode)
                .transition(reduceMotion ? .opacity : .blurFade)
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipped()
        }
        .frame(width: size.width + 2 * ear, height: size.height, alignment: .top)
        .scaleEffect(swell ? 1.04 : 1, anchor: .top)
        .contentShape(Rectangle())
        .onHover { actions.hover($0) }
        .onTapGesture { if mode != .expanded { actions.toggle() } }
        .contextMenu {
            Button("Ustawienia…") { actions.settings() }
            Button("Pokaż dziennik zdarzeń") { actions.log() }
            Divider()
            Button("Zakończ Dynamic Notch") { actions.quit() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.8),
                   value: mode)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: swell)
        .animation(.easeInOut(duration: 0.2), value: model.dropped)
        .environment(\.colorScheme, .dark)
    }

    /// macOS 27: mniej zaokrąglone narożniki (16 pkt) dla karty i panelu, Liquid Glass.
    /// Małe wcięcie zostaje czarne – jak sprzętowe wcięcie MacBooka.
    @ViewBuilder
    private func background(mode: NotchMode, size: CGSize, ear: CGFloat) -> some View {
        let large = mode == .expanded || mode == .alert
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
            Color.clear.accessibilityLabel("Dynamic Notch")
        case .alert:
            if let alert = model.alert {
                AlertCard(alert: alert, topInset: model.dropped ? 0 : model.barHeight * 0.35,
                          openURL: actions.openURL)
            }
        case .activity:
            if let activity = model.activity {
                ActivityRow(activity: activity, secondaryDot: model.showsSecondaryDot, height: model.barHeight)
            }
        case .event:
            if let event = model.upcomingEvent {
                EventRow(event: event, now: model.clock, secondaryDot: model.showsSecondaryDot,
                         height: model.barHeight)
            }
        case .agenda:
            if let event = model.nextEvent {
                AgendaRow(event: event, now: model.clock, height: model.barHeight)
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

private func percent(_ value: Float) -> String { "\(Int((value * 100).rounded()))" }

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
    f.locale = Locale(identifier: "pl_PL")
    f.dateFormat = "EEE"
    return f
}()

/// „dziś 18:00”, „jutro 7:00”, „pon. 18:00”
func dayTimeText(_ date: Date, now: Date) -> String {
    let calendar = Calendar.current
    let day: String
    if calendar.isDate(date, inSameDayAs: now) {
        day = "dziś"
    } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
              calendar.isDate(date, inSameDayAs: tomorrow) {
        day = "jutro"
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

/// Pasek poziomu (głośność, jasność).
struct LevelBar: View {
    var value: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(white: 0.25))
                Capsule().fill(Color.white)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: 4)
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
        .accessibilityLabel("Postęp utworu")
        .accessibilityValue("\(Int(progress * 100)) procent")
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
            .accessibilityLabel("Muzyka gra")
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
            Text(onAC ? "Ładowanie" : "Na baterii")
            Spacer(minLength: 4)
            Text("\(level)%").foregroundColor(onAC ? .green : .white)
        }
    }
}

/// Zbliżające się wydarzenie: „za 12 min” albo „teraz”.
struct EventRow: View {
    let event: CalendarItem
    let now: Date
    let secondaryDot: Bool
    let height: CGFloat

    private var whenText: String {
        let seconds = event.start.timeIntervalSince(now)
        if seconds <= 60 { return "teraz" }
        return "za \(Int((seconds / 60).rounded(.up))) min"
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "calendar").symbolRenderingMode(.hierarchical)
                .foregroundColor(Color(event.color)).frame(width: 18)
            Text(event.title).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            Text(whenText).foregroundColor(.orange)
            if secondaryDot { SecondaryDot() }
        }
        .font(.system(size: 12, weight: .medium).monospacedDigit())
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .frame(height: height)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title), \(whenText)")
    }
}

/// Najbliższe wydarzenie z najbliższych 7 dni – widoczne, gdy nic nie gra.
struct AgendaRow: View {
    let event: CalendarItem
    let now: Date
    let height: CGFloat

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "calendar")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(Color(event.color)).frame(width: 18)
            Text(event.title).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            Text(dayTimeText(event.start, now: now))
                .foregroundColor(secondaryText)
        }
        .font(.system(size: 12, weight: .medium).monospacedDigit())
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .frame(height: height)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Najbliższe: \(event.title), \(dayTimeText(event.start, now: now))")
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
                .help("Otwórz \(nowPlaying.player.displayName)")
            Text(nowPlaying.title).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            Waveform(active: nowPlaying.playing, tint: nowPlaying.tint.map { Color($0) } ?? .green)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .frame(height: height)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Odtwarzanie: \(nowPlaying.title), \(nowPlaying.artist)")
    }
}

// MARK: - Karta powiadomienia

/// Powiększona karta powiadomienia – czytelna jak alert w Dynamic Island.
struct AlertCard: View {
    let alert: NotchAlert
    let topInset: CGFloat
    var openURL: (URL) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color(alert.tint).opacity(0.22))
                Image(systemName: alert.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color(alert.tint))
            }
            .frame(width: 40, height: 40)

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
                Button(action: { openURL(url) }) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.blue))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            tabs
            if model.panelTab == 0 {
                HStack(alignment: .top, spacing: 18) {
                    player.frame(width: 230, alignment: .leading)
                    controls
                }
                .transition(.opacity)
            } else {
                TodayView(model: model, actions: actions)
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
            .accessibilityLabel("Zwiń")
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(secondaryText)
        .frame(height: model.barHeight)
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            Spacer()
            ForEach(Array(["Teraz", "Tydzień"].enumerated()), id: \.offset) { index, title in
                Button(action: { model.panelTab = index }) {
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(model.panelTab == index ? .white : secondaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(model.panelTab == index ? Color(white: 0.2) : Color.clear))
                }
                .buttonStyle(.plain)
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
                        .help("Otwórz \(np.player.displayName)")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Otwiera odtwarzacz")
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
                    controlButton("backward.fill", label: "Poprzedni utwór", action: actions.previous)
                    controlButton(np.playing ? "pause.fill" : "play.fill",
                                  label: np.playing ? "Pauza" : "Odtwarzaj", action: actions.playPause, size: 20)
                    controlButton("forward.fill", label: "Następny utwór", action: actions.next)
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
                Text("Nic nie jest odtwarzane").font(.system(size: 12, weight: .medium))
                Button(action: actions.openPlayer) {
                    Text("Otwórz Muzykę").font(.system(size: 11)).foregroundColor(.blue)
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
            sliderRow(symbol: volumeSymbol(model.volume, muted: model.muted), label: "Głośność",
                      value: Binding(get: { Double(model.volume) }, set: { actions.setVolume(Float($0)) }))
            if let brightness = model.brightness {
                sliderRow(symbol: "sun.max.fill", label: "Jasność",
                          value: Binding(get: { Double(brightness) }, set: { actions.setBrightness(Float($0)) }))
            }
            if let device = model.devices.first(where: { $0.symbol.hasPrefix("airpods") }) ?? model.devices.first {
                tile(symbol: device.symbol, title: device.name, value: "")
            }
            if model.micInUse || model.cameraInUse {
                tile(symbol: model.cameraInUse ? "video.fill" : "mic.fill",
                     title: model.cameraInUse ? "Kamera w użyciu" : "Mikrofon w użyciu", value: "")
            }
            if let event = model.nextEvent {
                tile(symbol: "calendar", title: event.title, value: dayTimeText(event.start, now: model.clock))
                    .contentShape(Rectangle())
                    .onTapGesture { actions.openCalendar() }
                    .help("Otwórz Kalendarz")
            }
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
                sectionHeader("Najbliższe 7 dni", app: "Kalendarz", action: actions.openCalendar)
                if model.todayEvents.isEmpty {
                    emptyTile("Brak wydarzeń w tym tygodniu")
                        .onTapGesture { actions.openCalendar() }
                } else {
                    ForEach(model.todayEvents.prefix(5)) { event in
                        eventTile(event)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("Przypomnienia", app: "Przypomnienia", action: actions.openReminders)
                if model.reminders.isEmpty {
                    emptyTile("Wszystko zrobione")
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
                    Text("Dołącz")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.blue))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background(TileBackground())
        .contentShape(Rectangle())
        .onTapGesture { actions.openCalendar() }
        .help("Otwórz w Kalendarzu")
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
            .accessibilityLabel("Odhacz: \(reminder.title)")
            Text(reminder.title).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(height: 30)
        .background(TileBackground())
        .contentShape(Rectangle())
        .onTapGesture { actions.openReminders() }
        .help("Otwórz w Przypomnieniach")
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
        .help("Otwórz \(app)")
        .accessibilityLabel("\(title) – otwórz \(app)")
    }
}
