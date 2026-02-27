import SwiftUI

// MARK: – Layout Constants
private struct PanelLayout {
    static let barThickness: CGFloat   = 44
    static let hBarWidth: CGFloat      = 730
    static let vBarWidth: CGFloat      = 80    // wider so 2-col grids fit
    static let gripThickness: CGFloat  = 4
    static let gripLength: CGFloat     = hBarWidth / 3
    static let gripSideLength: CGFloat = 480 / 3
    static let cornerRadius: CGFloat   = 22
}

struct ControlPanelView: View {
    @ObservedObject var appState: AppState
    
    let colors: [Color] = [.black, .white, .red, .orange, .yellow, .green, .blue, .purple]
    
    private var isVertical: Bool { appState.barOrientation != .horizontal }
    private var gripOnRight: Bool { appState.barOrientation == .verticalLeft }
    
    var body: some View {
        ZStack {
            if isVertical {
                verticalLayout
            } else {
                horizontalLayout
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: PanelLayout.cornerRadius, style: .continuous))
    }
    
    // MARK: – Horizontal layout
    
    private var horizontalLayout: some View {
        VStack(spacing: 0) {
            // Toolbar row
            HStack(spacing: 0) {
                toolSection
                divider
                colorSection
                divider
                sizeSection
                divider
                actionSection
            }
            .frame(height: PanelLayout.barThickness)
            
            // Grip pill centered below the bar
            HStack {
                Spacer()
                gripPill(width: PanelLayout.gripLength, height: PanelLayout.gripThickness)
                Spacer()
            }
            .frame(height: 10)
        }
    }
    
    // MARK: – Vertical layout
    
    private var verticalLayout: some View {
        HStack(spacing: 0) {
            // Grip on left side when bar is on the right
            if !gripOnRight {
                gripPill(width: PanelLayout.gripThickness, height: PanelLayout.gripSideLength)
                    .padding(.horizontal, 3)
            }
            
            // Vertical toolbar content
            VStack(spacing: 0) {
                toolSectionV
                hDivider
                colorSectionV
                hDivider
                sizeSectionV
                hDivider
                actionSectionV
            }
            .frame(width: PanelLayout.vBarWidth)
            
            // Grip on right side when bar is on the left
            if gripOnRight {
                gripPill(width: PanelLayout.gripThickness, height: PanelLayout.gripSideLength)
                    .padding(.horizontal, 3)
            }
        }
    }
    
    // MARK: – Grip
    
    private func gripPill(width: CGFloat, height: CGFloat) -> some View {
        Capsule()
            .fill(Color.primary.opacity(0.2))
            .frame(width: width, height: height)
    }
    
    // MARK: – Horizontal Sections
    
    private var toolSection: some View {
        HStack(spacing: 2) {
            ToolBtn(icon: "paintbrush.pointed", tip: "Pencil",    tool: .pencil,    state: appState)
            ToolBtn(icon: "square",             tip: "Rectangle", tool: .rectangle, state: appState)
            ToolBtn(icon: "circle",             tip: "Circle",    tool: .circle,    state: appState)
            ToolBtn(icon: "cursorarrow",        tip: "Select",    tool: .select,    state: appState)
        }
        .padding(.horizontal, 8)
    }
    
    private var colorSection: some View {
        HStack(spacing: 6) {
            ForEach(colors, id: \.self) { color in
                colorCircle(color)
            }
        }
        .padding(.horizontal, 10)
    }
    
    private var sizeSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(.tertiary)
            Slider(value: $appState.selectedLineWidth, in: 2...20).frame(width: 80)
            Image(systemName: "circle.fill").font(.system(size: 13)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
    }
    
    private var actionSection: some View {
        HStack(spacing: 4) {
            ActionBtn(icon: appState.isFilled ? "square.fill" : "square", tip: "Fill",
                      active: appState.isFilled, disabled: appState.selectedTool == .pencil) {
                appState.isFilled.toggle()
            }
            ActionBtn(icon: "hand.draw", tip: "Drawing Mode (Ctrl+Shift+D)",
                      active: appState.isDrawingMode, tint: .blue) {
                appState.isDrawingMode.toggle()
                NotificationCenter.default.post(name: NSNotification.Name("ToggleDrawingMode"),
                    object: nil, userInfo: ["enabled": appState.isDrawingMode])
            }
            ActionBtn(icon: appState.isHidden ? "eye.slash" : "eye", tip: "Hide/Show (Ctrl+Shift+H)") {
                appState.isHidden.toggle()
            }
            ActionBtn(icon: "trash", tip: "Delete Selected", tint: .red,
                      disabled: appState.selectedPathId == nil) {
                appState.deleteSelected()
            }
            ActionBtn(icon: "xmark.bin", tip: "Clear All (Ctrl+Shift+X)", tint: .red) {
                appState.clear()
            }
        }
        .padding(.horizontal, 8)
    }
    
    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 24)
            .padding(.horizontal, 4)
    }
    
    // MARK: – Vertical Sections
    
    private var toolSectionV: some View {
        LazyVGrid(columns: [GridItem(.fixed(34)), GridItem(.fixed(34))], spacing: 4) {
            ToolBtn(icon: "paintbrush.pointed", tip: "Pencil",    tool: .pencil,    state: appState)
            ToolBtn(icon: "square",             tip: "Rectangle", tool: .rectangle, state: appState)
            ToolBtn(icon: "circle",             tip: "Circle",    tool: .circle,    state: appState)
            ToolBtn(icon: "cursorarrow",        tip: "Select",    tool: .select,    state: appState)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
    }
    
    private var colorSectionV: some View {
        LazyVGrid(columns: [GridItem(.fixed(20)), GridItem(.fixed(20))], spacing: 6) {
            ForEach(colors, id: \.self) { color in
                colorCircle(color)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
    }
    
    private var sizeSectionV: some View {
        VStack(spacing: 4) {
            Image(systemName: "circle.fill").font(.system(size: 13)).foregroundStyle(.tertiary)
            VerticalSlider(value: $appState.selectedLineWidth, range: 2...20)
                .frame(width: 28, height: 70)
            Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
    
    private var actionSectionV: some View {
        VStack(spacing: 4) {
            ActionBtn(icon: appState.isFilled ? "square.fill" : "square", tip: "Fill",
                      active: appState.isFilled, disabled: appState.selectedTool == .pencil) {
                appState.isFilled.toggle()
            }
            ActionBtn(icon: "hand.draw", tip: "Drawing Mode",
                      active: appState.isDrawingMode, tint: .blue) {
                appState.isDrawingMode.toggle()
                NotificationCenter.default.post(name: NSNotification.Name("ToggleDrawingMode"),
                    object: nil, userInfo: ["enabled": appState.isDrawingMode])
            }
            ActionBtn(icon: appState.isHidden ? "eye.slash" : "eye", tip: "Hide/Show") {
                appState.isHidden.toggle()
            }
            ActionBtn(icon: "trash", tip: "Delete", tint: .red,
                      disabled: appState.selectedPathId == nil) {
                appState.deleteSelected()
            }
            ActionBtn(icon: "xmark.bin", tip: "Clear All", tint: .red) {
                appState.clear()
            }
        }
        .padding(.vertical, 4)
    }
    
    private var hDivider: some View {
        Rectangle().fill(Color.primary.opacity(0.12))
            .frame(height: 1)
            .padding(.horizontal, 6)
    }
    
    // MARK: – Shared
    
    private func colorCircle(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 18, height: 18)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.6),
                lineWidth: appState.selectedColor == color ? 2 : 0).padding(-2))
            .shadow(color: .black.opacity(0.2), radius: 1)
            .onTapGesture { appState.selectedColor = color }
    }
}

// MARK: – Window-drag blocker

/// Wrapping a SwiftUI view in this as a .background() prevents AppKit from
/// treating mouse-down events in that region as window-drag initiators.
private struct NonDraggableBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> _NonDraggableView { _NonDraggableView() }
    func updateNSView(_ nsView: _NonDraggableView, context: Context) {}
}

class _NonDraggableView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
}

// MARK: – Vertical Slider

struct VerticalSlider: View {
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>

    var body: some View {
        GeometryReader { geo in
            let trackH = geo.size.height
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            // Thumb offset (0 = top → max, 1 = bottom → min)
            let thumbY = trackH * (1 - fraction)

            ZStack(alignment: .top) {
                // Track
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 4)
                    .frame(maxWidth: .infinity)

                // Fill above thumb
                Capsule()
                    .fill(Color.accentColor.opacity(0.7))
                    .frame(width: 4, height: max(0, trackH - thumbY))
                    .frame(maxWidth: .infinity)
                    .offset(y: thumbY)

                // Thumb
                Circle()
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .offset(y: thumbY - 7)
                    .frame(maxWidth: .infinity)
            }
            .background(NonDraggableBackground())
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let newFraction = 1 - (drag.location.y / trackH)
                        let clamped = min(1, max(0, newFraction))
                        value = range.lowerBound + clamped * (range.upperBound - range.lowerBound)
                    }
            )
        }
    }
}

// MARK: – Reusable Atoms

struct ToolBtn: View {
    let icon: String; let tip: String; let tool: ToolType; let state: AppState
    var body: some View {
        Button { state.selectedTool = tool } label: {
            Image(systemName: icon).font(.system(size: 13, weight: .medium))
                .frame(width: 30, height: 30).contentShape(Rectangle())
                .background(state.selectedTool == tool ? Color.accentColor : .clear)
                .foregroundColor(state.selectedTool == tool ? .white : .primary)
                .cornerRadius(10)
        }.buttonStyle(.plain).help(tip)
    }
}

struct ActionBtn: View {
    let icon: String; let tip: String
    var active: Bool = false; var tint: Color = .primary; var disabled: Bool = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13, weight: .medium))
                .frame(width: 30, height: 30).contentShape(Rectangle())
                .foregroundColor(active ? .white : (disabled ? .secondary : tint))
                .background(active ? tint : .clear)
                .cornerRadius(10)
        }.buttonStyle(.plain).disabled(disabled).help(tip)
    }
}
