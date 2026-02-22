import AppKit
import SwiftUI

class OverlayWindow: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSScreen.main?.frame ?? NSRect.zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        self.isFloatingPanel = true
        self.level = .screenSaver
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = true // Start click-through
        self.contentView = contentView
        
        // Ensure it covers the whole screen
        self.setFrame(NSScreen.main?.frame ?? NSRect.zero, display: true)
    }
    
    func setDrawingMode(_ enabled: Bool) {
        self.ignoresMouseEvents = !enabled
    }
    
    override var canBecomeKey: Bool {
        return false // Never become key to keep focus on control panel
    }
}
