import SwiftUI
import AppKit

@main
struct BrushApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem?
    var overlayWindow: OverlayWindow?
    var controlPanelWindow: NSWindow?
    // Keep strong references to hosting views so SwiftUI doesn't release them
    var overlayHostingView: NSHostingView<DrawingView>?
    var controlPanelHostingView: NSHostingView<ControlPanelView>?
    var appState = AppState()
    
    // Global hotkey state tracking
    private var globalMonitor: Any?
    private var pressedKeys = Set<String>()
    // Debounce timer for orientation snap
    private var snapTimer: Timer?
    
    // Toolbar size constants (must match PanelLayout in ControlPanelView)
    private let hW: CGFloat = 730, hH: CGFloat = 54    // horizontal
    private let vW: CGFloat = 90,  vH: CGFloat = 480   // vertical (80 content + 10 grip+padding)
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupOverlayWindow()
        setupControlPanel()
        setupGlobalHotkey()
        
        NotificationCenter.default.addObserver(self, selector: #selector(onToggleDrawingMode(_:)), name: NSNotification.Name("ToggleDrawingMode"), object: nil)
    }
    
    func setupGlobalHotkey() {
        // Global monitor fires even when another app is active.
        // Requires Input Monitoring permission on first run.
        let keyActions: [String: () -> Void] = [
            "b": { [weak self] in self?.toggleControlPanel() },     // Ctrl+Shift+B – Control Panel
            "d": { [weak self] in self?.toggleDrawingMode() },      // Ctrl+Shift+D – Drawing Mode
            "h": { [weak self] in self?.toggleVisibility() },       // Ctrl+Shift+H – Hide/Show
            "x": { [weak self] in self?.clearScreen() },            // Ctrl+Shift+X – Clear
            "q": { NSApp.terminate(nil) },                          // Ctrl+Shift+Q – Quit
        ]
        
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags
            // Must have EXACTLY Ctrl+Shift (no Cmd, no Option)
            guard mods.contains(.control) && mods.contains(.shift) else { return }
            guard !mods.contains(.command) && !mods.contains(.option) else { return }
            
            let char = event.charactersIgnoringModifiers?.lowercased() ?? ""
            if let action = keyActions[char] {
                DispatchQueue.main.async { action() }
            }
        }
    }
    
    @objc func toggleDrawingMode() {
        appState.isDrawingMode.toggle()
        overlayWindow?.setDrawingMode(appState.isDrawingMode)
        if appState.isDrawingMode {
            overlayWindow?.orderFrontRegardless()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    @objc func onToggleDrawingMode(_ notification: Notification) {
        if let userInfo = notification.userInfo, let enabled = userInfo["enabled"] as? Bool {
            overlayWindow?.setDrawingMode(enabled)
            if enabled { overlayWindow?.orderFrontRegardless() }
        }
    }
    
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "paintbrush", accessibilityDescription: "Brush")
        }
        
        let menu = NSMenu()
        
        // Helper to add items with Ctrl+Shift modifiers shown in the menu
        func addHotkeyItem(title: String, action: Selector, key: String) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key.lowercased())
            item.keyEquivalentModifierMask = [.control, .shift]
            menu.addItem(item)
        }
        
        addHotkeyItem(title: "Control Panel",       action: #selector(toggleControlPanel), key: "b")
        addHotkeyItem(title: "Toggle Drawing Mode", action: #selector(toggleDrawingMode),  key: "d")
        addHotkeyItem(title: "Show/Hide Drawings",  action: #selector(toggleVisibility),   key: "h")
        addHotkeyItem(title: "Clear All Drawings",  action: #selector(clearScreen),        key: "x")
        addHotkeyItem(title: "Take Screenshot",     action: #selector(takeScreenshot),     key: "s")
        
        menu.addItem(NSMenuItem.separator())
        addHotkeyItem(title: "Quit Brush",          action: #selector(quitApp),            key: "q")
        
        statusItem?.menu = menu
    }
    
    @objc func quitApp() { NSApp.terminate(nil) }

    
    func setupOverlayWindow() {
        let drawingView = DrawingView(appState: appState)
        let hostingView = NSHostingView(rootView: drawingView)
        overlayHostingView = hostingView
        
        let screenRect = NSScreen.main?.frame ?? NSRect.zero
        hostingView.frame = screenRect
        
        overlayWindow = OverlayWindow(contentView: hostingView)
        overlayWindow?.setFrame(screenRect, display: true)
        overlayWindow?.makeKeyAndOrderFront(nil)
    }
    
    func setupControlPanel() {
        let controlView = ControlPanelView(appState: appState)
        let hostingView = NSHostingView(rootView: controlView)
        controlPanelHostingView = hostingView
        
        let screen = NSScreen.main?.frame ?? NSRect.zero
        
        // Horizontal bar: content-sized width, 44pt tall, centered at the top
        let panelHeight: CGFloat = 44
        let panelWidth: CGFloat = 730
        let panelRect = NSRect(
            x: screen.midX - panelWidth / 2,
            y: screen.maxY - panelHeight - 6,
            width: panelWidth,
            height: panelHeight
        )
        
        let window = NSWindow(
            contentRect: panelRect,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.level = NSWindow.Level(Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
        window.isReleasedWhenClosed = false
        window.isMovable = true
        window.isMovableByWindowBackground = true  // drag by clicking empty areas
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = hostingView
        window.delegate = self   // enables windowDidMove
        
        self.controlPanelWindow = window
        window.orderFrontRegardless()
    }
    
    @objc func toggleControlPanel() {
        if let window = controlPanelWindow {
            if window.isVisible { window.orderOut(nil) }
            else { window.orderFrontRegardless() }
        }
    }
    
    // MARK: – NSWindowDelegate: orientation snap
    
    func windowDidMove(_ notification: Notification) {
        snapTimer?.invalidate()
        snapTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            self?.checkAndSnapOrientation()
        }
    }
    
    private func checkAndSnapOrientation() {
        guard let window = controlPanelWindow,
              let screen = NSScreen.main else { return }
        
        let screenW = screen.frame.width
        let midX = window.frame.midX
        let threshold = screenW * 0.20   // within 20% of either edge → vertical
        
        let newOrientation: BarOrientation
        if midX < threshold {
            newOrientation = .verticalLeft
        } else if midX > screenW - threshold {
            newOrientation = .verticalRight
        } else {
            newOrientation = .horizontal
        }
        
        guard newOrientation != appState.barOrientation else {
            // Same orientation — just make sure window is inside screen bounds
            clampToScreen(window: window, screen: screen.frame)
            return
        }
        appState.barOrientation = newOrientation
        snapWindow(to: newOrientation, screen: screen.frame, window: window)
    }
    
    private func clampToScreen(window: NSWindow, screen: NSRect) {
        var f = window.frame
        f.origin.x = max(screen.minX, min(f.origin.x, screen.maxX - f.width))
        f.origin.y = max(screen.minY, min(f.origin.y, screen.maxY - f.height))
        if f.origin != window.frame.origin {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                window.animator().setFrame(f, display: true)
            }
        }
    }
    
    private func snapWindow(to orientation: BarOrientation, screen: NSRect, window: NSWindow) {
        let currentMid = window.frame.midY
        let newFrame: NSRect
        
        switch orientation {
        case .horizontal:
            // Re-center horizontally, keep vertical position
            newFrame = NSRect(
                x: screen.midX - hW / 2,
                y: min(max(currentMid - hH / 2, screen.minY), screen.maxY - hH),
                width: hW, height: hH
            )
        case .verticalLeft:
            // Dock to the left edge, keep vertical center
            newFrame = NSRect(
                x: screen.minX,
                y: min(max(currentMid - vH / 2, screen.minY), screen.maxY - vH),
                width: vW, height: vH
            )
        case .verticalRight:
            // Dock to the right edge, keep vertical center
            newFrame = NSRect(
                x: screen.maxX - vW,
                y: min(max(currentMid - vH / 2, screen.minY), screen.maxY - vH),
                width: vW, height: vH
            )
        }
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            window.animator().setFrame(newFrame, display: true)
        }
    }
    
    @objc func toggleVisibility() {
        appState.isHidden.toggle()
        overlayWindow?.alphaValue = appState.isHidden ? 0 : 1
    }
    
    @objc func clearScreen() { appState.clear() }
    @objc func undoAction() { appState.undo() }
    @objc func redoAction() { appState.redo() }
    
    @objc func selectTool(_ sender: NSMenuItem) {
        if let tool = sender.representedObject as? ToolType {
            appState.selectedTool = tool
        }
    }
    
    @objc func takeScreenshot() {
        // Hide drawings for screenshot (optional, but requested features say "get a screenshot at any point")
        // Usually, people want the annotations in the screenshot too if they are drawing.
        // I'll take the screenshot with annotations.
        
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateString = dateFormatter.string(from: Date())
        
        // Save to Desktop
        let path = NSString(string: "~/Desktop/Brush_Screenshot_\(dateString).png").expandingTildeInPath
        task.arguments = ["-i", "-c"] // Interactive + to clipboard
        // Or directly to file:
        task.arguments = ["-x", path] // -x means mute sound
        
        task.launch()
        task.waitUntilExit()
    }
}
