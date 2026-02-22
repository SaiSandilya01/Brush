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

class AppDelegate: NSObject, NSApplicationDelegate {
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
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupOverlayWindow()
        setupControlPanel()
        setupGlobalHotkey()
        
        NotificationCenter.default.addObserver(self, selector: #selector(onToggleDrawingMode(_:)), name: NSNotification.Name("ToggleDrawingMode"), object: nil)
    }
    
    func setupGlobalHotkey() {
        // Monitor key events globally (works even when another app is focused)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            // Require Command modifier
            guard event.modifierFlags.contains(.command) else { return }
            
            let char = event.charactersIgnoringModifiers?.lowercased() ?? ""
            self.pressedKeys.insert(char)
            
            // Cmd + B + H: both 'b' and 'h' held with Command
            if self.pressedKeys.contains("b") && self.pressedKeys.contains("h") {
                self.pressedKeys.removeAll()
                DispatchQueue.main.async { self.toggleControlPanel() }
            }
        }
        
        // Clear tracked keys on key up so stale state doesn't accumulate
        NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            let char = event.charactersIgnoringModifiers?.lowercased() ?? ""
            self?.pressedKeys.remove(char)
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
            if enabled {
                overlayWindow?.orderFrontRegardless()
            }
        }
    }
    
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "paintbrush", accessibilityDescription: "Brush")
        }
        
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "Control Panel", action: #selector(toggleControlPanel), keyEquivalent: "p"))
        menu.addItem(NSMenuItem(title: "Show/Hide Drawings", action: #selector(toggleVisibility), keyEquivalent: "h"))
        menu.addItem(NSMenuItem(title: "Take Screenshot", action: #selector(takeScreenshot), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "Clear Screen", action: #selector(clearScreen), keyEquivalent: "c"))
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Undo", action: #selector(undoAction), keyEquivalent: "z"))
        let redoItem = NSMenuItem(title: "Redo", action: #selector(redoAction), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redoItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Brush", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "e"))
        
        statusItem?.menu = menu
    }
    
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
        controlPanelHostingView = hostingView  // strong reference prevents deallocation
        
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 250, height: 350),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.center()
        window.level = NSWindow.Level(Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
        window.isReleasedWhenClosed = false  // prevents crash when user clicks the ✕ button
        window.title = "Brush Controls"
        window.contentView = hostingView
        window.backgroundColor = .clear
        window.setFrameAutosaveName("BrushControlPanel")
        
        self.controlPanelWindow = window
        window.makeKeyAndOrderFront(nil)
    }
    
    @objc func toggleControlPanel() {
        if let window = controlPanelWindow {
            if window.isVisible {
                window.orderOut(nil)
            } else {
                window.makeKeyAndOrderFront(nil)
            }
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
