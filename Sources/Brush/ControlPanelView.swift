import SwiftUI

struct ControlPanelView: View {
    @ObservedObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    
    let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .primary, .secondary]
    
    var body: some View {
        VStack(spacing: 20) {
            // Tool Header
            HStack {
                Text("BRUSH")
                    .font(.system(.subheadline, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: { appState.isHidden.toggle() }) {
                    Image(systemName: appState.isHidden ? "eye.slash" : "eye")
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            
            // Tool Picker (Icon based)
            HStack(spacing: 12) {
                ToolButton(type: .pencil, icon: "paintbrush.pointed", selected: $appState.selectedTool)
                ToolButton(type: .rectangle, icon: "square", selected: $appState.selectedTool)
                ToolButton(type: .circle, icon: "circle", selected: $appState.selectedTool)
                ToolButton(type: .select, icon: "cursorarrow", selected: $appState.selectedTool)
            }
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 12) {
                // Color Selection
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(colors, id: \.self) { color in
                            Circle()
                                .fill(color)
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: appState.selectedColor == color ? 1.5 : 0)
                                        .padding(-3)
                                )
                                .onTapGesture { appState.selectedColor = color }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                
                // Size Slider
                HStack(spacing: 15) {
                    Image(systemName: "line.horizontal.3")
                        .font(.caption)
                    Slider(value: $appState.selectedLineWidth, in: 2...15)
                    Circle()
                        .fill(appState.selectedColor)
                        .frame(width: appState.selectedLineWidth, height: appState.selectedLineWidth)
                        .frame(width: 15, height: 15)
                }
                
                HStack {
                    Toggle(isOn: $appState.isFilled) {
                        Label("Fill", systemImage: "paintbrush.fill")
                            .font(.caption)
                    }
                    .toggleStyle(.button)
                    .disabled(appState.selectedTool == .pencil)
                    
                    Spacer()
                    
                    Toggle(isOn: $appState.isDrawingMode) {
                        Label("Draw", systemImage: "hand.draw")
                            .font(.caption)
                    }
                    .toggleStyle(.button)
                    .tint(.blue)
                    .onChange(of: appState.isDrawingMode) { oldValue, newValue in
                        NotificationCenter.default.post(name: NSNotification.Name("ToggleDrawingMode"), object: nil, userInfo: ["enabled": newValue])
                    }
                }
            }
            
            Divider()
            
            // Action Buttons
            HStack(spacing: 12) {
                Button(role: .destructive, action: { appState.deleteSelected() }) {
                    Label("Delete", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(appState.selectedPathId == nil)
                
                Button(action: { appState.clear() }) {
                    Label("Clear", systemImage: "xmark.bin")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 240)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }
}

struct ToolButton: View {
    let type: ToolType
    let icon: String
    @Binding var selected: ToolType
    
    var body: some View {
        Button(action: { selected = type }) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())   // full frame is tappable
                .background(selected == type ? Color.blue : Color.clear)
                .foregroundColor(selected == type ? .white : .primary)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
