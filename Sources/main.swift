// Dynamic Notch – małe wcięcie w stylu MacBooka z informacjami jak w Dynamic Island
// © 2026 ks. Piotr Bułka

import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // bez ikony w Docku i bez ikony na pasku menu
app.run()
