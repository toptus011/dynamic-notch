// ScreenshotMonitor.swift – nowy zrzut ekranu (⌘⇧3, ⌘⇧4, ⌘⇧5) → miniatura we wcięciu
// Korzysta ze Spotlight (atrybut kMDItemIsScreenCapture), więc działa niezależnie od folderu zrzutów.

import Cocoa
import ImageIO

final class ScreenshotMonitor {

    var onScreenshot: ((URL) -> Void)?

    private let query = NSMetadataQuery()
    private var known: Set<String> = []
    private var startedAt = Date()
    private var running = false

    init() {
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        let center = NotificationCenter.default
        center.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: .main) { [weak self] note in
            self?.update(note)
        }
    }

    func start() {
        guard !running else { return }
        running = true
        startedAt = Date()
        if !query.start() { Log.write("Zrzuty ekranu: Spotlight niedostępny") }
    }

    func stop() {
        guard running else { return }
        running = false
        query.stop()
    }

    private func update(_ note: Notification) {
        let info = note.userInfo ?? [:]
        let added = (info[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem]) ?? []
        let changed = (info[NSMetadataQueryUpdateChangedItemsKey] as? [NSMetadataItem]) ?? []
        for item in added + changed {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  !known.contains(path) else { continue }
            known.insert(path)
            let created = (item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date) ?? Date()
            // Tylko świeże zrzuty (zrobione po starcie programu, najwyżej 30 s temu).
            guard created >= startedAt.addingTimeInterval(-2), Date().timeIntervalSince(created) < 30 else { continue }
            let url = URL(fileURLWithPath: path)
            Log.write("Zrzut ekranu: \(url.lastPathComponent)")
            onScreenshot?(url)
        }
    }
}

/// Pliki na półce: otwieranie, AirDrop, ikony.
enum ShelfTools {

    static func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        guard service.canPerform(withItems: urls) else {
            Log.write("AirDrop niedostępny (włącz Wi-Fi i Bluetooth)")
            NSSound.beep()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
        Log.write("AirDrop: \(urls.count) plik(ów)")
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func icon(_ url: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    /// Mała miniatura obrazu (zrzut ekranu), bez wczytywania pełnej rozdzielczości do widoku.
    static func thumbnail(_ url: URL, maxSize: CGFloat = 160) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSize * 2,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2))
    }

    /// „1 plik”, „2 pliki”, „5 plików”
    static func filesText(_ n: Int) -> String {
        guard Lang.polish else { return n == 1 ? "1 file" : "\(n) files" }
        if n == 1 { return "1 plik" }
        let lastTwo = n % 100
        let last = n % 10
        if (2...4).contains(last) && !(12...14).contains(lastTwo) { return "\(n) pliki" }
        return "\(n) plików"
    }
}
