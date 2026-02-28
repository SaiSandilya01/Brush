import SwiftUI
import Combine
import CoreImage

enum ToolType: String, CaseIterable, Identifiable {
    case pencil = "Pencil"
    case rectangle = "Rectangle"
    case circle = "Circle"
    case arrowSingle = "Arrow"
    case arrowDouble = "Double Arrow"
    case text = "Text"
    case select = "Select"
    var id: String { self.rawValue }
}

enum BarOrientation {
    case horizontal
    case verticalLeft   // bar moved to left side of screen, grip on right
    case verticalRight  // bar moved to right side of screen, grip on left
}

/// Maximum number of strokes kept in memory before oldest are dropped.
private let maxPathHistory = 500

struct DrawingPath: Identifiable {
    let id = UUID()
    var points: [CGPoint]
    var color: Color
    var lineWidth: CGFloat
    var toolType: ToolType
    var isFilled: Bool = false
    
    /// Text content (only used when toolType == .text)
    var text: String? = nil
    /// Font size for text tool (derived from lineWidth at commit time)
    var fontSize: CGFloat = 24
    
    /// Cached smooth Path for rendering. Rebuilt only when committed.
    var cachedPath: Path? = nil
}

class AppState: ObservableObject {
    // MARK: - Live Drawing State
    @Published var paths: [DrawingPath] = []
    @Published var currentPath: DrawingPath?
    
    // When selection changes, trigger snapshot rebuild so the selected path
    // is excluded from the background image and drawn live with a highlight.
    @Published var selectedPathId: UUID? {
        didSet { snapshotNeedsUpdate = true }
    }
    
    // MARK: - Snapshot for incremental rendering
    @Published var snapshotImage: CGImage?
    var snapshotNeedsUpdate = false

    // MARK: - Undo/Redo
    private var undoStack: [[DrawingPath]] = []
    private var redoStack: [[DrawingPath]] = []
    private let maxUndoLevels = 50
    
    // MARK: - Tool Settings
    @Published var selectedColor: Color = .red
    @Published var selectedLineWidth: CGFloat = 5.0
    @Published var isFilled: Bool = false
    
    // Auto-enable Drawing Mode when Select tool is chosen so the user
    // doesn't have to manually toggle it for selection to work.
    @Published var selectedTool: ToolType = .pencil {
        didSet {
            let needsDrawing = selectedTool == .select || selectedTool == .text
            if needsDrawing && !isDrawingMode {
                isDrawingMode = true
                NotificationCenter.default.post(
                    name: NSNotification.Name("ToggleDrawingMode"),
                    object: nil,
                    userInfo: ["enabled": true]
                )
            }
        }
    }
    
    // MARK: - App State
    @Published var isHidden: Bool = false
    @Published var isDrawingMode: Bool = false
    @Published var barOrientation: BarOrientation = .horizontal
    
    // MARK: - Mutations
    
    func commitPath(_ path: DrawingPath) {
        saveUndoSnapshot()
        var p = path
        p.cachedPath = buildSmoothedPath(from: p)
        paths.append(p)
        if paths.count > maxPathHistory {
            paths.removeFirst(paths.count - maxPathHistory)
        }
        snapshotNeedsUpdate = true
    }
    
    func deleteSelected() {
        guard let id = selectedPathId else { return }
        saveUndoSnapshot()
        paths.removeAll(where: { $0.id == id })
        selectedPathId = nil
        snapshotNeedsUpdate = true
    }
    
    func clear() {
        paths.removeAll()
        currentPath = nil
        selectedPathId = nil
        undoStack.removeAll()
        redoStack.removeAll()
        snapshotImage = nil
        snapshotNeedsUpdate = true  // triggers SnapshotNSView to clear its local cached image
    }
    
    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(paths)
        paths = previous
        selectedPathId = nil
        snapshotNeedsUpdate = true
    }
    
    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(paths)
        paths = next
        selectedPathId = nil
        snapshotNeedsUpdate = true
    }
    
    // MARK: - Private
    
    private func saveUndoSnapshot() {
        undoStack.append(paths)
        if undoStack.count > maxUndoLevels { undoStack.removeFirst() }
        redoStack.removeAll()
    }
    
    /// Builds a smooth path from a DrawingPath. Text tool returns empty path (rendered separately).
    func buildSmoothedPath(from drawingPath: DrawingPath) -> Path {
        let points = drawingPath.points
        var path = Path()
        
        // Text uses a separate rendering pass — no path needed
        if drawingPath.toolType == .text { return path }
        
        guard points.count > 1 else {
            if let p = points.first { path.move(to: p) }
            return path
        }
        
        switch drawingPath.toolType {
        case .pencil:
            path.move(to: points[0])
            if points.count == 2 {
                path.addLine(to: points[1])
            } else {
                for i in 1..<points.count - 1 {
                    let p0 = points[max(0, i - 1)]
                    let p1 = points[i]
                    let p2 = points[min(points.count - 1, i + 1)]
                    let cp1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6.0, y: p1.y + (p2.y - p0.y) / 6.0)
                    let cp2 = CGPoint(x: p2.x - (p2.x - p0.x) / 6.0, y: p2.y - (p2.y - p0.y) / 6.0)
                    path.addCurve(to: p2, control1: cp1, control2: cp2)
                }
            }
        case .rectangle:
            if let first = points.first, let last = points.last {
                path.addRect(CGRect(
                    x: min(first.x, last.x), y: min(first.y, last.y),
                    width: abs(first.x - last.x), height: abs(first.y - last.y)
                ))
            }
        case .circle:
            if let first = points.first, let last = points.last {
                path.addEllipse(in: CGRect(
                    x: min(first.x, last.x), y: min(first.y, last.y),
                    width: abs(first.x - last.x), height: abs(first.y - last.y)
                ))
            }
        case .arrowSingle:
            if let first = points.first, let last = points.last {
                path = buildArrowPath(from: first, to: last,
                                      lineWidth: drawingPath.lineWidth, doubleEnded: false)
            }
        case .arrowDouble:
            if let first = points.first, let last = points.last {
                path = buildArrowPath(from: first, to: last,
                                      lineWidth: drawingPath.lineWidth, doubleEnded: true)
            }
        case .text:
            break // rendered via NSAttributedString, not a Path
        case .select:
            break
        }
        return path
    }
}

// MARK: - Arrow Path Geometry

/// Builds a Path for a single- or double-ended arrow.
/// The path contains the shaft line plus filled arrowhead triangle(s).
func buildArrowPath(from start: CGPoint, to end: CGPoint,
                    lineWidth: CGFloat, doubleEnded: Bool) -> Path {
    var path = Path()
    let dx = end.x - start.x
    let dy = end.y - start.y
    let length = hypot(dx, dy)
    guard length > 1 else { return path }

    // Unit vector along the shaft
    let ux = dx / length
    let uy = dy / length
    // Perpendicular unit vector
    let px = -uy
    let py = ux

    let headLength = max(14.0, lineWidth * 4.0)
    let headWidth  = headLength * 0.55

    // --- Forward arrowhead (at `end`) ---
    // Shaft stops just before the arrowhead base
    let shaftEndForward = CGPoint(x: end.x - ux * headLength,
                                  y: end.y - uy * headLength)
    let shaftStartPoint = doubleEnded
        ? CGPoint(x: start.x + ux * headLength, y: start.y + uy * headLength)
        : start

    // Shaft
    path.move(to: shaftStartPoint)
    path.addLine(to: shaftEndForward)

    // Forward arrowhead triangle
    let fLeft  = CGPoint(x: shaftEndForward.x + px * headWidth / 2,
                         y: shaftEndForward.y + py * headWidth / 2)
    let fRight = CGPoint(x: shaftEndForward.x - px * headWidth / 2,
                         y: shaftEndForward.y - py * headWidth / 2)
    path.move(to: end)
    path.addLine(to: fLeft)
    path.addLine(to: fRight)
    path.closeSubpath()

    if doubleEnded {
        // Backward arrowhead triangle (at `start`, pointing away from `end`)
        let shaftEndBack = CGPoint(x: start.x + ux * headLength,
                                   y: start.y + uy * headLength)
        let bLeft  = CGPoint(x: shaftEndBack.x + px * headWidth / 2,
                             y: shaftEndBack.y + py * headWidth / 2)
        let bRight = CGPoint(x: shaftEndBack.x - px * headWidth / 2,
                             y: shaftEndBack.y - py * headWidth / 2)
        path.move(to: start)
        path.addLine(to: bLeft)
        path.addLine(to: bRight)
        path.closeSubpath()
    }

    return path
}
