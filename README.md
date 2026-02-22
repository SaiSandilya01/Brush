# Brush macOS Application

A lightweight background application for drawing and annotating on your Mac screen.

## Features
- **Trackpad Drawing**: Smooth drawing and shape creation.
- **Tools**: Pencil, Rectangle, Circle.
- **Customization**: Change colors, line width, and toggle filled shapes.
- **Modes**: 
    - **Drawing Mode**: Captures input for drawing.
    - **Click-through Mode**: Allows you to interact with apps behind your drawings.
- **Screenshots**: Automatically saves screenshots of your screen to the Desktop.
- **Menu Bar Integration**: Quick access to all controls.

## How to Run (Terminal - No Xcode Required)

If you don't have Xcode installed but have Command Line Tools, you can run the app directly from the terminal:

1. **Open Terminal** in the project directory (`/Users/sandilya/Projects/Brush`).
2. **Build the app**:
   ```bash
   swift build
   ```
3. **Run the app**:
   ```bash
   swift run
   ```

## How to Run (Xcode)
1. **Prerequisites**: You need a Mac with Xcode installed.
2. **Project Setup**:
    - Create a new **macOS App** project in Xcode.
    - Select **SwiftUI** for the Interface.
    - Copy the files from `Sources/Brush/` into your Xcode project.
3. **Permissions**:
    - The first time you take a screenshot, macOS will ask for **Screen Recording** permissions.
    - Enable it in `System Settings > Privacy & Security > Screen Recording`.
4. **Build and Run**: Press `Cmd + R` in Xcode.

## Usage
- Click the **Paintbrush** icon in the Menu Bar to open the Menu.
- Use the **Control Panel** (`Cmd + P`) to switch tools and colors.
- Toggle **Drawing Mode** when you want to draw. Turn it off when you need to click on other apps.

---

## TODO

### 1. Global Macros / Keyboard Shortcuts
Implement system-wide hotkeys that work even when another app is in focus:

| Action | Shortcut (Proposed) |
|---|---|
| Show / Hide Control Panel | `Cmd + B + H` |
| Quit Application | Custom (currently `Cmd + E` from menu) |
| Show / Hide Drawings | Custom global hotkey |
| Clear All Drawings | Custom global hotkey |

> **Note**: macOS requires **Accessibility / Input Monitoring** permissions for global monitors. The current `NSEvent.addGlobalMonitorForEvents` implementation may not fire when another app is active without granting this permission in `System Settings → Privacy & Security → Input Monitoring`.

### 2. Control Panel UI Refinement
- Tighter, more compact layout
- Larger tool icons with labels on hover (tooltips)
- Color picker with custom color support (beyond the preset palette)
- Opacity/alpha slider for colours
- Undo/Redo buttons visible in the panel
- Smooth open/close animation for the panel
