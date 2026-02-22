import SwiftUI
import Combine
import CoreImage

enum ToolType: String, CaseIterable, Identifiable {
    case pencil = "Pencil"
    case rectangle = "Rectangle"
    case circle = "Circle"
    case select = "Select"
    
    var id: String { self.rawValue }
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
            if selectedTool == .select && !isDrawingMode {
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
    
    /// Builds a smooth Catmull-Rom spline Path. Called once on commit, result is cached.
    func buildSmoothedPath(from drawingPath: DrawingPath) -> Path {
        let points = drawingPath.points
        var path = Path()
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
        case .select:
            break
        }
        return path
    }
}
