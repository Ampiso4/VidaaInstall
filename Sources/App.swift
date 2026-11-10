import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct VidaaInstallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    init() {
        // Une seule fenêtre : pas de restauration d'état. Sinon, après un arrêt brutal,
        // macOS peut relancer l'app… sans aucune fenêtre.
        UserDefaults.standard.register(defaults: ["ApplePersistenceIgnoreState": true, "NSQuitAlwaysKeepsWindows": false])
    }

    var body: some Scene {
        WindowGroup("VidaaInstall") {
            RootView(model: model)
                .background(WindowStyler())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1040, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Téléviseur") {
                Button("Lancer l'installation") { model.install() }.keyboardShortcut(.return, modifiers: .command)
                Button("Actualiser les applications") { model.section = .apps; model.refreshApps() }.keyboardShortcut("r")
                Button("Sauvegarder Appinfo.json") { model.backupNow() }.keyboardShortcut("s")
                Button("Rechercher des téléviseurs") { model.section = .tvs; model.startScan() }.keyboardShortcut("k")
                Divider()
                Button("Téléviseurs") { model.section = .tvs }.keyboardShortcut("1")
                Button("Installer") { model.section = .install }.keyboardShortcut("2")
                Button("Applications") { model.section = .apps }.keyboardShortcut("3")
                Button("Sauvegardes") { model.section = .backups }.keyboardShortcut("4")
            }
        }
    }
}

/// Fenêtre sans barre : le contenu passe sous les feux tricolores, fond déplaçable.
struct WindowStyler: NSViewRepresentable {
    final class Coordinator {
        var observers: [NSObjectProtocol] = []
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.styleMask.insert(.fullSizeContentView)
            w.backgroundColor = NSColor(red: 9 / 255, green: 21 / 255, blue: 64 / 255, alpha: 1)
            #if DEMO
            if AppModel.shots { w.setContentSize(NSSize(width: 1180, height: 740)); w.center() }
            #endif
            TrafficLights.place(in: w)
            // AppKit remet les boutons à leur place par défaut à chaque mise en page de la barre.
            let names: [Notification.Name] = [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
                                              NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification,
                                              NSWindow.didResignKeyNotification]
            for n in names {
                context.coordinator.observers.append(
                    NotificationCenter.default.addObserver(forName: n, object: w, queue: .main) { _ in TrafficLights.place(in: w) })
            }
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Place les trois boutons natifs à l'intérieur du panneau latéral en verre
/// (panneau : marge 10 pt, coins 24 pt).
enum TrafficLights {
    /// Bord gauche du bouton rouge et centre vertical de la rangée, depuis le coin haut-gauche.
    static let left: CGFloat = 24 // aligné sur le logo (marge du panneau 10 + 14)
    static let centerY: CGFloat = 32

    static func place(in w: NSWindow) {
        guard !w.styleMask.contains(.fullScreen),
              let close = w.standardWindowButton(.closeButton),
              let mini = w.standardWindowButton(.miniaturizeButton),
              let zoom = w.standardWindowButton(.zoomButton),
              let bar = close.superview, let container = bar.superview else { return }
        let measured = mini.frame.minX - close.frame.minX
        let spacing = measured > 0 ? measured : 20
        // La barre de titre est agrandie pour que les boutons puissent descendre sans être rognés.
        let height = centerY * 2
        if container.frame.height != height {
            var f = container.frame
            f.size.height = height
            f.origin.y = (container.superview?.bounds.height ?? w.frame.height) - height
            container.frame = f
            bar.frame = container.bounds
        }
        for (i, b) in [close, mini, zoom].enumerated() {
            b.setFrameOrigin(NSPoint(x: left + CGFloat(i) * spacing, y: (height - b.frame.height) / 2))
        }
    }
}
