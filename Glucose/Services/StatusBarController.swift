import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let store: GlucoseStore
    private let statusItem: NSStatusItem
    private let panel: PopoverPanel
    private var outsideClickMonitor: Any?
    private var keyDownMonitor: Any?
    private var staleRefreshTimer: Timer?

    init(store: GlucoseStore) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.panel = PopoverPanel(
            contentSize: NSSize(width: 360, height: 300),
            content: AnyView(PopoverView().environment(store))
        )
        super.init()

        configureStatusItem()
        observeStoreForLabel()
        scheduleStaleRefresh()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.image = nil
        button.imagePosition = .noImage
        button.font = NSFont.menuBarFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize - 1)
        button.title = "—"
    }

    private func observeStoreForLabel() {
        withObservationTracking {
            _ = store.readings
            _ = store.hasCredentials
            renderLabel()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeStoreForLabel() }
        }
    }

    private func scheduleStaleRefresh() {
        // Re-render the label every minute so "stale" → "—" transitions when no
        // new readings arrive, without waiting for the next store change.
        staleRefreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.renderLabel() }
        }
    }

    private func renderLabel() {
        guard let button = statusItem.button else { return }
        if let reading = store.latestReading, !store.isStale {
            button.title = String(format: "%.1f", reading.mmol)
            if let angle = store.readings.trendAngleDegrees(endingAt: reading) {
                button.image = Self.arrowImage(rotatedDegrees: angle)
                button.imagePosition = .imageRight
                button.imageHugsTitle = true
            } else if let fallback = Self.fallbackArrowImage(for: reading.trend) {
                button.image = fallback
                button.imagePosition = .imageRight
                button.imageHugsTitle = true
            } else {
                button.image = nil
                button.imagePosition = .noImage
            }
        } else {
            button.title = "—"
            button.image = nil
            button.imagePosition = .noImage
        }
    }

    /// Leading whitespace (points) baked into the menu-bar arrow image so the
    /// glyph sits slightly to the right of where AppKit would otherwise place
    /// it (`button.imageHugsTitle = true` removes default spacing).
    private static let arrowLeadingPadding: CGFloat = 2

    /// Render `arrow.right` rotated by the given trend angle as a template
    /// NSImage, so AppKit tints it like the rest of the menu bar text.
    /// Angle convention matches `trendAngleDegrees`: 0 = flat/right,
    /// -90 = rising/up, +90 = falling/down.
    private static func arrowImage(rotatedDegrees angleDegrees: Double) -> NSImage? {
        let base = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: "trend")
        let config = NSImage.SymbolConfiguration(pointSize: NSFont.menuBarFont(ofSize: 0).pointSize,
                                                 weight: .bold)
        guard let configured = base?.withSymbolConfiguration(config) else { return nil }
        return paddedRotatedImage(configured, rotatedDegrees: angleDegrees)
    }

    private static func fallbackArrowImage(for trend: TrendDirection) -> NSImage? {
        switch trend {
        case .none, .notComputable, .rateOutOfRange:
            return nil
        default:
            guard let img = NSImage(systemSymbolName: trend.sfSymbol, accessibilityDescription: "trend") else {
                return nil
            }
            return paddedRotatedImage(img, rotatedDegrees: 0)
        }
    }

    private static func paddedRotatedImage(_ source: NSImage, rotatedDegrees angleDegrees: Double) -> NSImage {
        let inner = source.size
        let size = NSSize(width: inner.width + arrowLeadingPadding, height: inner.height)
        let composed = NSImage(size: size, flipped: false) { _ in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            // SwiftUI's positive rotation goes clockwise (screen +y down).
            // CG's positive rotation goes counter-clockwise (CG +y up).
            // Negate so the visual direction matches the popover arrow.
            let radians = -angleDegrees * .pi / 180.0
            cg.translateBy(x: arrowLeadingPadding + inner.width / 2, y: inner.height / 2)
            cg.rotate(by: radians)
            cg.translateBy(x: -inner.width / 2, y: -inner.height / 2)
            source.draw(in: NSRect(origin: .zero, size: inner))
            return true
        }
        composed.isTemplate = true
        return composed
    }

    @objc private func handleStatusItemClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }
        switch event.type {
        case .rightMouseUp:
            showContextMenu()
        default:
            togglePanel()
        }
    }

    private func togglePanel() {
        if panel.isVisible {
            closePanel()
        } else {
            openPanel()
        }
    }

    private func openPanel() {
        guard let button = statusItem.button,
              let buttonWindow = button.window else { return }

        let buttonFrameInScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let panelSize = panel.frame.size
        let gap: CGFloat = 6

        // Center under the button, clamped to the screen.
        var origin = NSPoint(
            x: buttonFrameInScreen.midX - panelSize.width / 2,
            y: buttonFrameInScreen.minY - panelSize.height - gap
        )
        if let screen = buttonWindow.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = max(visible.minX + 6, min(origin.x, visible.maxX - panelSize.width - 6))
            origin.y = max(visible.minY + 6, origin.y)
        }

        panel.setFrameOrigin(origin)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        installEventMonitors()
    }

    private func closePanel() {
        panel.orderOut(nil)
        removeEventMonitors()
    }

    private func installEventMonitors() {
        removeEventMonitors()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.closePanel() }
        }
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { // escape
                Task { @MainActor in self?.closePanel() }
                return nil
            }
            return event
        }
    }

    private func removeEventMonitors() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let keyDownMonitor { NSEvent.removeMonitor(keyDownMonitor) }
        outsideClickMonitor = nil
        keyDownMonitor = nil
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let refresh = NSMenuItem(title: "Refresh", action: #selector(refreshAction), keyEquivalent: "")
        refresh.target = self
        menu.addItem(refresh)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Glucose", action: #selector(quitApp), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func refreshAction() {
        Task { await store.fetchOnce() }
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

final class PopoverPanel: NSPanel {
    init(contentSize: NSSize, content: AnyView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow

        let host = NSHostingView(rootView: content)
        if #available(macOS 26.0, *) {
            // Liquid Glass, as used by the system menu-bar dropdowns (Wi-Fi,
            // Control Center). It draws its own edge highlight, so no border.
            let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: contentSize))
            glass.cornerRadius = 16
            glass.contentView = host
            contentView = glass
        } else {
            contentView = Self.legacyBackground(size: contentSize, hosting: host)
        }
    }

    /// Pre-Tahoe look: the frosted `.menu` material with a hairline border.
    private static func legacyBackground(size: NSSize, hosting host: NSView) -> NSView {
        let cornerRadius: CGFloat = 12

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .menu
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = cornerRadius
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]

        host.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            host.topAnchor.constraint(equalTo: effect.topAnchor),
            host.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
        ])

        // Subtle border that matches Control Center popovers.
        if let layer = effect.layer {
            layer.borderWidth = 0.5
            layer.borderColor = NSColor.white.withAlphaComponent(0.07).cgColor
        }
        return effect
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
