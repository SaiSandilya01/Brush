import SwiftUI
import AppKit

struct DrawingView: View {
    @ObservedObject var appState: AppState
    
    /// Last recorded point for downsampling.
    @State private var lastRecordedPoint: CGPoint? = nil
    /// Last velocity for width variation.
    @State private var lastVelocity: CGFloat = 0
    
    var body: some View {
        ZStack {
            // 1. Snapshot Layer: pre-rendered image of all committed strokes
            SnapshotCanvasView(appState: appState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // 2. Active stroke layer: renders only the in-progress stroke
            Canvas { context, _ in
                if let currentPath = appState.currentPath {
                    renderLivePath(currentPath, in: &context)
                }
                
                // Selection highlight overlay on committed paths
                for dp in appState.paths where dp.id == appState.selectedPathId {
                    if let cachedPath = dp.cachedPath {
                        let glowStyle = StrokeStyle(lineWidth: dp.lineWidth + 10, lineCap: .round, lineJoin: .round)
                        context.stroke(cachedPath, with: .color(Color.blue.opacity(0.3)), style: glowStyle)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(appState.isHidden ? 0 : 1)
            
            // 3. Gesture & Indicator Layer
            if appState.isDrawingMode && !appState.isHidden {
                ZStack {
                    Color.black.opacity(0.01)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in handleDragChanged(value) }
                                .onEnded { _ in handleDragEnded() }
                        )
                    
                    Rectangle()
                        .stroke(Color.blue.opacity(0.2), lineWidth: 2)
                        .edgesIgnoringSafeArea(.all)
                    
                    VStack {
                        HStack {
                            Label(appState.selectedTool.rawValue, systemImage: toolIcon(for: appState.selectedTool))
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .edgesIgnoringSafeArea(.all)
        .background(KeyEventHandlerView(
            onDelete: { appState.deleteSelected() },
            onUndo:   { appState.undo() },
            onRedo:   { appState.redo() }
        ))
    }
    
    // MARK: - Text Tool
    
    private func textFontSize() -> CGFloat {
        max(16, appState.selectedLineWidth * 4)
    }
    
    private func toolIcon(for tool: ToolType) -> String {
        switch tool {
        case .pencil:      return "paintbrush.pointed"
        case .rectangle:   return "square"
        case .circle:      return "circle"
        case .arrowSingle: return "arrow.right"
        case .arrowDouble: return "arrow.left.and.right"
        case .text:        return "textformat"
        case .select:      return "cursorarrow"
        }
    }
    
    // MARK: - Live Rendering (in-progress stroke only)
    
    private func renderLivePath(_ drawingPath: DrawingPath, in context: inout GraphicsContext) {
        guard drawingPath.points.count > 1 else { return }
        
        var path = Path()
        let first = drawingPath.points.first!
        let last  = drawingPath.points.last!
        
        switch drawingPath.toolType {
        case .pencil:
            // For pencil, draw lines through all collected points
            path.addLines(drawingPath.points)
            let style = StrokeStyle(lineWidth: drawingPath.lineWidth, lineCap: .round, lineJoin: .round)
            context.stroke(path, with: .color(drawingPath.color), style: style)
            return

        case .rectangle:
            path.addRect(CGRect(
                x: min(first.x, last.x), y: min(first.y, last.y),
                width: abs(first.x - last.x), height: abs(first.y - last.y)
            ))

        case .circle:
            path.addEllipse(in: CGRect(
                x: min(first.x, last.x), y: min(first.y, last.y),
                width: abs(first.x - last.x), height: abs(first.y - last.y)
            ))

        case .arrowSingle:
            // Live preview: build arrow path and render it
            let arrowPath = buildArrowPath(from: first, to: last,
                                           lineWidth: drawingPath.lineWidth, doubleEnded: false)
            let shaftStyle = StrokeStyle(lineWidth: drawingPath.lineWidth, lineCap: .round, lineJoin: .round)
            context.stroke(arrowPath, with: .color(drawingPath.color), style: shaftStyle)
            context.fill(arrowPath, with: .color(drawingPath.color))
            return

        case .arrowDouble:
            let arrowPath = buildArrowPath(from: first, to: last,
                                           lineWidth: drawingPath.lineWidth, doubleEnded: true)
            let shaftStyle = StrokeStyle(lineWidth: drawingPath.lineWidth, lineCap: .round, lineJoin: .round)
            context.stroke(arrowPath, with: .color(drawingPath.color), style: shaftStyle)
            context.fill(arrowPath, with: .color(drawingPath.color))
            return

        case .text:
            return // rendered by the overlay TextField, not the Canvas

        case .select:
            return
        }

        if drawingPath.isFilled {
            context.fill(path, with: .color(drawingPath.color))
        } else {
            let style = StrokeStyle(lineWidth: drawingPath.lineWidth, lineCap: .round, lineJoin: .round)
            context.stroke(path, with: .color(drawingPath.color), style: style)
        }
    }
    
    // MARK: - Input Handling
    
    private func handleDragChanged(_ value: DragGesture.Value) {
        // --- Text Tool: tap to place ---
        if appState.selectedTool == .text {
            // Only capture on the very first event of a new gesture (no currentPath yet)
            if appState.currentPath == nil {
                let pt = value.startLocation
                // Signal AppDelegate to open the real text input panel
                NotificationCenter.default.post(
                    name: NSNotification.Name("RequestTextInput"),
                    object: nil,
                    userInfo: [
                        "x": pt.x,
                        "y": pt.y,
                        "color": appState.selectedColor,
                        "fontSize": textFontSize(),
                        "lineWidth": appState.selectedLineWidth
                    ]
                )
                // Sentinel: prevents re-firing within the same drag gesture
                appState.currentPath = DrawingPath(
                    points: [pt],
                    color: appState.selectedColor,
                    lineWidth: appState.selectedLineWidth,
                    toolType: .text
                )
            }
            return
        }
        
        // --- Selection Tool ---
        if appState.selectedTool == .select {
            let hit = appState.paths.last(where: { dp in
                switch dp.toolType {
                case .pencil:
                    return dp.points.contains(where: { pt in
                        hypot(pt.x - value.location.x, pt.y - value.location.y) < 20
                    })
                case .rectangle, .circle, .arrowSingle, .arrowDouble:
                    return getBoundingRect(for: dp).insetBy(dx: -10, dy: -10).contains(value.location)
                case .text:
                    guard let anchor = dp.points.first else { return false }
                    let hitRect = CGRect(x: anchor.x - 10, y: anchor.y - dp.fontSize,
                                        width: 300, height: dp.fontSize + 20)
                    return hitRect.contains(value.location)
                case .select:
                    return false
                }
            })
            appState.selectedPathId = hit?.id
            return
        }
        
        let newPoint = value.location
        
        // --- Optimization #1: Point Downsampling ---
        // Skip points that are too close to the last recorded one.
        if let last = lastRecordedPoint {
            let dist = hypot(newPoint.x - last.x, newPoint.y - last.y)
            if dist < 2.0 { return }
        }
        lastRecordedPoint = newPoint
        
        // --- Optimization #2: Velocity-based line width ---
        let velocity = CGPoint(x: value.velocity.width, y: value.velocity.height)
        let speed = hypot(velocity.x, velocity.y)
        // Smooth the speed to avoid jitter
        let smoothedSpeed = lastVelocity * 0.6 + speed * 0.4
        lastVelocity = smoothedSpeed
        // Map speed: fast = thinner, slow = thicker (capped to ±40% of selected width)
        let baseWidth = appState.selectedLineWidth
        let speedFactor = max(0.6, min(1.4, 1.0 - (smoothedSpeed / 5000.0)))
        let dynamicWidth = baseWidth * speedFactor
        
        // --- Append point or start new path ---
        if var path = appState.currentPath {
            path.points.append(newPoint)
            // Update width dynamically for pencil
            if appState.selectedTool == .pencil {
                path.lineWidth = dynamicWidth
            }
            appState.currentPath = path
        } else {
            lastVelocity = 0
            appState.currentPath = DrawingPath(
                points: [newPoint],
                color: appState.selectedColor,
                lineWidth: appState.selectedTool == .pencil ? dynamicWidth : baseWidth,
                toolType: appState.selectedTool,
                isFilled: appState.isFilled
            )
        }
    }
    
    private func handleDragEnded() {
        if appState.selectedTool == .select { return }
        // Text tool: clear sentinel currentPath; commit happens via the overlay onSubmit
        if appState.selectedTool == .text {
            appState.currentPath = nil
            return
        }
        lastRecordedPoint = nil
        lastVelocity = 0
        if let currentPath = appState.currentPath {
            // Background thread: compute smooth cached path, then commit on main thread
            let pathToProcess = currentPath
            let state = appState
            DispatchQueue.global(qos: .userInitiated).async {
                let smoothed = state.buildSmoothedPath(from: pathToProcess)
                DispatchQueue.main.async {
                    var finalPath = pathToProcess
                    finalPath.cachedPath = smoothed
                    state.commitPath(finalPath)
                    state.currentPath = nil
                }
            }
        }
    }
    
    private func getBoundingRect(for drawingPath: DrawingPath) -> CGRect {
        guard !drawingPath.points.isEmpty else { return .zero }
        let xs = drawingPath.points.map { $0.x }
        let ys = drawingPath.points.map { $0.y }
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
}

// MARK: - Snapshot Canvas (incremental rendering)

/// An NSViewRepresentable that maintains a CGImage snapshot of all committed strokes.
/// On each update, it only redraws from scratch when `snapshotNeedsUpdate` is set.
struct SnapshotCanvasView: NSViewRepresentable {
    @ObservedObject var appState: AppState
    
    func makeNSView(context: Context) -> SnapshotNSView {
        let view = SnapshotNSView()
        view.appState = appState
        return view
    }
    
    func updateNSView(_ nsView: SnapshotNSView, context: Context) {
        if appState.snapshotNeedsUpdate {
            nsView.rebuildSnapshot()
            appState.snapshotNeedsUpdate = false
        }
        nsView.alphaValue = appState.isHidden ? 0 : 1
        nsView.needsDisplay = true
    }
}

class SnapshotNSView: NSView {
    var appState: AppState?
    private var snapshotImage: CGImage?
    private var buildGeneration = 0   // increments every rebuild; stale closures discard their result
    
    override var isFlipped: Bool { true }
    
    func rebuildSnapshot() {
        guard let appState = appState else {
            snapshotImage = nil
            return
        }
        
        guard !appState.paths.isEmpty else {
            snapshotImage = nil
            needsDisplay = true
            return
        }
        
        let generation = buildGeneration + 1
        buildGeneration = generation
        
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let size = bounds.isEmpty ? (NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)) : bounds.size
        let width  = Int(size.width  * scale)
        let height = Int(size.height * scale)
        guard width > 0, height > 0 else { return }
        
        let paths = appState.paths
        let selectedId = appState.selectedPathId
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, self.buildGeneration == generation else { return }
            
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            
            ctx.scaleBy(x: scale, y: scale)
            
            for dp in paths {
                guard self.buildGeneration == generation else { return } // abort if stale
                guard dp.id != selectedId else { continue }
                
                // Text elements are drawn in a separate pass below
                if dp.toolType == .text { continue }
                
                guard let swiftPath = dp.cachedPath else { continue }
                
                let cgPath = swiftPath.cgPath
                ctx.saveGState()
                let nsColor = NSColor(dp.color)
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)
                ctx.setLineWidth(dp.lineWidth)
                ctx.setStrokeColor(nsColor.cgColor)
                ctx.setFillColor(nsColor.cgColor)

                switch dp.toolType {
                case .arrowSingle, .arrowDouble:
                    // Arrows: stroke the shaft and fill the arrowhead triangles
                    ctx.addPath(cgPath)
                    ctx.drawPath(using: .fillStroke)
                case .rectangle, .circle:
                    if dp.isFilled {
                        ctx.addPath(cgPath)
                        ctx.fillPath()
                    } else {
                        ctx.addPath(cgPath)
                        ctx.strokePath()
                    }
                default:
                    ctx.addPath(cgPath)
                    ctx.strokePath()
                }
                ctx.restoreGState()
            }
            
            // --- Text rendering pass (Core Text — thread-safe, works on background CGContext) ---
            for dp in paths {
                guard self.buildGeneration == generation else { return }
                guard dp.toolType == .text, dp.id != selectedId else { continue }
                guard let txt = dp.text, let anchor = dp.points.first else { continue }
                
                let nsColor = NSColor(dp.color)
                
                // Build Core Text attributed string
                let ctFont = CTFontCreateWithName("Virgil3YOFF" as CFString, dp.fontSize, nil)
                let cfStr = txt as CFString
                let cfAttrStr = CFAttributedStringCreateMutable(kCFAllocatorDefault, 0)!
                CFAttributedStringReplaceString(cfAttrStr, CFRangeMake(0, 0), cfStr)
                let range = CFRangeMake(0, CFStringGetLength(cfStr))
                CFAttributedStringSetAttribute(cfAttrStr, range, kCTFontAttributeName, ctFont)
                CFAttributedStringSetAttribute(cfAttrStr, range, kCTForegroundColorAttributeName, nsColor.cgColor)
                
                let line = CTLineCreateWithAttributedString(cfAttrStr)
                
                ctx.saveGState()
                // anchor.y is SwiftUI top-down (same convention as all other path coordinates).
                // The SnapshotNSView has isFlipped=true and ctx.draw(img,in:) compensates,
                // so we use anchor.y directly — same as paths do.
                // textMatrix = scale(1,-1) pre-flips glyphs so they appear right-side-up
                // after the NSView's display flip. Without it, text renders upside-down.
                ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
                ctx.textPosition = CGPoint(x: anchor.x, y: anchor.y)
                CTLineDraw(line, ctx)
                ctx.restoreGState()
            }
            
            let image = ctx.makeImage()
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.buildGeneration == generation else { return }
                self.snapshotImage = image
                self.needsDisplay = true
            }
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        if let img = snapshotImage {
            ctx.draw(img, in: bounds)
        }
    }
}

// MARK: - Keyboard Handler

struct KeyEventHandlerView: NSViewRepresentable {
    let onDelete: () -> Void
    let onUndo:   () -> Void
    let onRedo:   () -> Void
    
    func makeNSView(context: Context) -> KeyHandlerNSView {
        let view = KeyHandlerNSView()
        view.onDelete = onDelete
        view.onUndo   = onUndo
        view.onRedo   = onRedo
        return view
    }
    
    func updateNSView(_ nsView: KeyHandlerNSView, context: Context) {
        nsView.onDelete = onDelete
        nsView.onUndo   = onUndo
        nsView.onRedo   = onRedo
    }
}

class KeyHandlerNSView: NSView {
    var onDelete: (() -> Void)?
    var onUndo:   (() -> Void)?
    var onRedo:   (() -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        // Delete or Backspace
        if event.keyCode == 51 || event.keyCode == 117 {
            onDelete?()
        }
        // Cmd+Z
        else if event.modifierFlags.contains(.command) && event.characters == "z" {
            if event.modifierFlags.contains(.shift) {
                onRedo?()
            } else {
                onUndo?()
            }
        } else {
            super.keyDown(with: event)
        }
    }
}
