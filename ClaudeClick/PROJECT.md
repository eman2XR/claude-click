# Claude Click - macOS UI Automation Tool

## Project Goal
Create a macOS command-line tool for automated testing and UI interaction that provides:
- Smart UI element detection using Accessibility API
- Mouse control (movement and clicking)
- Keyboard input
- Screenshot capture with coordinate grid overlay
- Visual coordinate identification for UI testing
- Wait and verification commands for testing workflows
- Real-time app activity monitoring and event logging

## Current Version: 1.0

### Features Implemented
1. ✅ Click and double-click functionality at coordinates
2. ✅ Accessibility API element finding by name
3. ✅ App-specific element filtering
4. ✅ Animated mouse movement (visual feedback)
5. ✅ Text input (type command)
6. ✅ Keyboard special keys (press-key command)
7. ✅ Wait command (simple delay)
8. ✅ Wait for app launch detection
9. ✅ Vision framework OCR text finding (find-text-ocr)
10. ✅ Screenshot capture (full screen or window)
11. ✅ Element dump to JSON with annotated PNG
12. ✅ Accessibility permission checking
13. ✅ Multi-display support
14. ✅ Element monitor (manual start)

### Current Status
- Release binary: `claude-click` (~120KB)
- Debug binary: `.build/debug/claude-click`
- All core features: FULLY IMPLEMENTED & TESTED
- Accessibility permissions: GRANTED
- Multi-display support: WORKING
- Animated mouse movement: 0.3s with ease-in-out interpolation
- Element monitor: Start manually with `~/bin/claude-click start-monitor 0.5 &`
- OCR text finding: Native macOS Vision framework integration

### Commands Available

#### Mouse Control
```bash
claude-click click <x> <y>                   # Click at coordinates (animated)
claude-click click <x> <y> --double          # Double-click at coordinates
```

#### Element Finding & Clicking
```bash
claude-click find-click <name> [app]         # Find and click element via Accessibility API
claude-click find-click <name> [app] --double # Find and double-click element
claude-click find-text-ocr <text> <app>      # Find text using OCR and click it
claude-click find-text-ocr <text> <app> --double # Find text with OCR and double-click
```

**Best Practice:** Try `find-click` first (faster), fall back to `find-text-ocr` if element not found.

#### Keyboard & Text Input

**WARNING:** These commands send input to the currently active app. ALWAYS verify the correct app is in focus before using these commands.

```bash
claude-click type "<text>"                   # Type text at current cursor
claude-click press-key <key>                 # Press special key
```

Available keys: return, enter, tab, space, delete, escape, esc, command, cmd, shift, capslock, option, alt, control, ctrl, right, left, down, up, f1-f12

#### Waiting
```bash
claude-click wait <seconds>                  # Wait for specified seconds
claude-click wait-for-app-launch <app> [timeout]  # Wait for app to launch (default 10s)
```

#### Screenshots
```bash
claude-click screenshot [filename]           # Take full screen screenshot
claude-click screenshot <app> [filename]     # Take window screenshot
```

#### Debugging
```bash
claude-click dump <app> <output>             # Dump app elements to JSON + PNG
claude-click dump screen <output>            # Dump all screen elements
claude-click check-permissions               # Check accessibility permissions
```

## Best Practices: Finding and Clicking Elements

### Recommended Workflow (Try Accessibility API First, Fall Back to OCR)

**1. First: Try Accessibility API (Fastest & Most Reliable)**
```bash
# Try finding element through Accessibility API
claude-click find-click "Play" "Keynote"
```

**When to use:** For standard UI elements (buttons, menus, text fields) that expose accessibility info
- Fast (< 100ms)
- Accurate (clicks exact center of element)
- Works with all standard macOS controls
- Returns proper element information

**2. Fallback: Use OCR (When Accessibility Fails)**
```bash
# If Accessibility API doesn't find it, use OCR
claude-click find-text-ocr "Play" "Keynote"
```

**When to use:** For text/elements not exposed via Accessibility API
- Works with any visible text
- Great for presentation software (Keynote, PowerPoint)
- Finds text in custom UI elements
- Slower (~1-2 seconds due to screenshot + OCR)
- May need adjustment for buttons (text position vs clickable area)

### Complete Example: Resilient Element Finding

```bash
# Try Accessibility API first
if ! claude-click find-click "Submit" "Safari" 2>/dev/null; then
    # Fall back to OCR if not found
    echo "Element not accessible, trying OCR..."
    claude-click find-text-ocr "Submit" "Safari"
fi
```

### OCR Limitations & Solutions

**Problem:** OCR finds text labels, not button centers
- Text "Play" might be below the actual Play button icon
- Solution: Manually adjust coordinates or use Accessibility API

**Problem:** Multiple matches for common words
- OCR returns first match
- Solution: Be specific with search text or use unique identifiers

**When OCR Works Best:**
- Keynote/PowerPoint slide text
- Large buttons with text labels
- Form labels and titles
- Menu items with unique text

**When Accessibility API Works Best:**
- System UI elements (buttons, checkboxes, menus)
- Standard macOS controls
- App toolbar buttons
- Text fields and input areas

### Checking Application State

**Best Method: wait-for-app-launch**

```bash
# Launch and wait for app
open -a "MyApp"
claude-click wait-for-app-launch "MyApp" 15
```
- Fast detection (checks every 100ms)
- Reliable
- Returns proper exit code

**Alternative: Screenshots for visual verification**

```bash
# Take screenshot to verify state after important actions
claude-click screenshot Safari verify.png
```
- Slower (~1-2 seconds)
- Complete visual state
- Can see everything on screen
- **When to use:**
  - After save/delete operations to verify success
  - After form submissions to verify state
  - When debugging element finding issues
  - Before proceeding to critical next steps

**Best Practice:**
1. Use wait-for-app-launch for app launches (reliable)
2. Take screenshots after important actions for verification (essential for debugging)

### Example Testing Workflows

#### Test Login Form
```bash
# Click username field and enter credentials
claude-click find-click "Username" "MyApp"
claude-click type "testuser"
claude-click press-key tab
claude-click type "password123"
claude-click press-key return

# Wait and take screenshot to verify
claude-click wait 2
claude-click screenshot MyApp login-result.png
```

#### Test Save Functionality
```bash
# Take screenshot of initial state
claude-click screenshot MyApp initial.png

# Make changes and save
claude-click find-click "Text Field" "MyApp"
claude-click type "New content"
claude-click find-click "Save" "MyApp"
claude-click wait 1

# Take screenshot to verify save completed
claude-click screenshot MyApp after-save.png
```

#### Launch and Test App
```bash
# Launch app and wait
open -a "Xcode"
claude-click wait-for-app-launch "Xcode" 60

# Click Run button
claude-click find-click "Run" "Xcode"

# Wait for target app to launch
claude-click wait-for-app-launch "MyTestApp" 30

# Interact with the app
claude-click find-click "Start Button" "MyTestApp"
```

### Smart Element Finding
The tool can automatically find and click UI elements by name:

```bash
# Click the Run button in Xcode
claude-click find-click "Run" "Xcode"

# Click any button with "Calendar" in the name
claude-click find-click "Calendar"

# Double-click an element
claude-click find-click "FolderName" --double
```

**How it works:**
1. Searches all running applications for elements matching the name
2. Optional app filter narrows search to specific application
3. Matches against both title and description attributes
4. Calculates center point of element
5. Animates mouse movement to target (0.3s with ease-in-out)
6. Automatically clicks at the calculated position

**Limitations:**
- Finder file lists don't expose accessible titles for files
- Use coordinate-based clicking for Finder files instead
- If multiple windows of same app are open, searches all windows and returns first match
- Minimized windows are also searched (close/minimize unwanted windows)

### Animated Mouse Movement
- Mouse smoothly animates to click targets over 0.3 seconds
- Uses ease-in-out interpolation for natural motion
- Makes it easy to visually follow automation actions
- Applied to all click and double-click operations
- Works correctly across multiple displays

### Multi-Display Support
- Tested with laptop + external monitor setup
- AX API returns coordinates in global coordinate space
- Main display typically at (0, 0)
- Additional displays positioned relative to main
- External monitors may have negative Y coordinates if positioned above main
- Click coordinates work correctly across all displays

### Element Finding vs Coordinate Clicking
**Use element finding when:**
- Element has a clear, unique name
- Element is in an accessible application
- Position might vary or change

**Use coordinate clicking when:**
- Element has no accessible name (e.g., Finder files)
- Need pixel-perfect precision
- Element is in a custom UI framework

### Multiple Windows Issue
When using element finding with multiple windows:
- AX API searches through all windows of the target app
- Returns first match found
- Minimized windows are also searched
- Best practice: close or minimize unwanted windows before automation

## Technical Implementation

### Accessibility API Element Finding
Uses macOS Accessibility API to discover UI elements:
- `AXUIElementCreateApplication(pid)` - Get app's accessibility element
- `AXUIElementCopyAttributeValue` - Read element attributes
- Searches through `kAXChildrenAttribute` recursively
- Matches against `kAXTitleAttribute` and `kAXDescriptionAttribute`
- Retrieves `kAXPositionAttribute`, `kAXSizeAttribute`, `kAXEnabledAttribute`
- Filters out invalid positions

### Keyboard Input
Text typing uses Unicode string events:
- `CGEvent(keyboardEventSource:virtualKey:keyDown:)` for key events
- `keyboardSetUnicodeString` for character input
- 10ms delay between characters for realistic typing
- Virtual key codes for special keys (Return: 0x24, Tab: 0x30, etc.)

### Click Functionality
Modeled after proven automation tools:
- Animates mouse to target position (0.3s ease-in-out)
- Sends left mouse down event
- 15ms delay between down and up
- Sends left mouse up event
- Uses `CGEvent` API with `kCGHIDEventTap`

### Double-Click Functionality
Proper double-click event sequence:
- First click with `mouseEventClickState = 1`
- 100ms delay between clicks
- Second click with `mouseEventClickState = 2`
- System recognizes as legitimate double-click

### Wait Functionality
- `wait`: Simple usleep-based delay
- `wait-for-app-launch`: Polls NSWorkspace.runningApplications every 100ms until app appears or timeout

### Animated Mouse Movement
```swift
func animatedMoveMouse(to targetPoint: CGPoint, duration: Double = 0.3)
```
- 60 FPS animation (16.7ms per frame)
- Ease-in-out interpolation: slow start, fast middle, slow end
- Interpolates from current mouse position to target
- Works across multiple displays in global coordinate space

### Retina Display Coordinate Handling
Correctly handles Retina display scaling:
- Physical resolution: 3024x1964 pixels (example)
- Logical coordinates: 1512x982 points (scale factor 2.0)
- All click operations use logical coordinate system

### Element Monitor (Manual Start)
To use find-click or find-text-ocr commands effectively:
- Start the monitor daemon manually: `~/bin/claude-click start-monitor 0.5 &`
- Daemon continuously updates element data to /tmp/screen-elements.json and /tmp/focused-app.json
- Updates every 0.5 seconds (configurable)
- Provides fast element lookups for interactive commands
- Stop with: `~/bin/claude-click stop-daemon`

### Binary Types
- **Debug binary** (`.build/debug/claude-click`): Rebuilt on each `swift build`, loses permissions
- **Release binary** (`claude-click`): Permanent optimized binary, retains permissions

## Technical Requirements
- macOS 13+
- Swift 5.9+
- Core Graphics framework
- ApplicationServices framework
- AppKit framework
- Accessibility permissions granted

## File Structure
```
ClaudeClick/
├── Package.swift                          # Swift package configuration
├── PROJECT.md                             # This file
├── Sources/
│   └── AutomationTool/
│       └── main.swift                     # Main implementation (~1000 lines)
├── .build/
│   ├── debug/
│   │   └── claude-click                   # Debug binary
│   └── release/
│       └── claude-click                   # Release binary
└── claude-click                           # Permanent release binary (~120KB)
```

## Build Instructions

### Quick Install (Recommended)
```bash
cd ClaudeClick
./install.sh
```

This will build a release version and install to `~/bin/claude-click`.

### Manual Debug Build
```bash
cd ClaudeClick
swift build
.build/debug/claude-click --help
```

### Manual Release Build and Install
```bash
cd ClaudeClick
swift build -c release
mkdir -p ~/bin
cp .build/release/claude-click ~/bin/claude-click
chmod +x ~/bin/claude-click
```

## Claude Configuration

### Permanent Permissions
Add to `~/.claude/settings.json`:
```json
{
  "permissions": {
    "allow": [
      "Bash(~/bin/claude-click:*)"
    ]
  }
}
```

**Restart Claude after adding permissions.**

## Usage Examples

### Finding Element Coordinates
```bash
# Use dump command to see all elements with their coordinates
claude-click dump screen debug-output

# Image saved to /tmp/debug-output.png with bounding boxes
# JSON saved to /tmp/debug-output.json with element data
```

### Automated Form Testing
```bash
# Fill out form
claude-click find-click "First Name"
claude-click type "John"
claude-click press-key tab
claude-click type "Doe"
claude-click press-key tab
claude-click type "john@example.com"

# Submit
claude-click press-key return

# Wait and verify
claude-click wait 2
claude-click screenshot result.png
```

## Key Learnings

### Why Release Binary is Important
1. **Accessibility Permissions**: macOS grants permissions to specific binary files
2. **Rebuild Issue**: Debug binaries change on rebuild, losing permissions
3. **Permanent Binary**: Release binary stays constant, retains permissions

### Coordinate System Clarification
- **CGDisplay coordinates**: Y=0 at top-left (used by click function)
- **NSScreen coordinates**: Y=0 at bottom-left (not used)
- **Retina scaling**: Physical pixels ÷ 2 = logical coordinates

### Multi-Display Coordinate System
- Global coordinate space spans all displays
- Main display typically at (0, 0)
- Additional displays positioned relative to main
- External monitors may have negative Y coordinates if positioned above main
- AX API returns coordinates in this global space
- Works seamlessly across displays

### Element Finding vs Coordinate Clicking
**Use element finding when:**
- Element has a clear, unique name
- Element is in an accessible application
- Position might vary or change

**Use coordinate clicking when:**
- Element has no accessible name (e.g., Finder files)
- Need pixel-perfect precision
- Element is in a custom UI framework

### Multiple Windows Issue
When using element finding with multiple windows:
- AX API searches through all windows of the target app
- Returns first match found
- Minimized windows are also searched
- Best practice: close or minimize unwanted windows before automation

## Known Issues
- Deprecation warning for `kUTTypePNG` (cosmetic, works fine)
- Click reliability depends on accessibility permissions being properly granted
- Finder file list items don't expose accessible titles (use coordinate-based clicking)
- Multiple windows of same app: first matching element is clicked

## Future Enhancements

### Potential Future Features
- Mouse position reading (`mouse-pos`)
- Mouse movement without clicking (`move`)
- Element verification (`verify-element`, `wait-for-element`)
- Element information queries (`get-element-info`)
- List all elements (`list-elements`)
- Screen configuration display (`screen-info`)
- Grid screenshots for coordinate identification (`grid-screenshot`)
- Right-click support
- Drag and drop
- Screenshot comparison for visual testing

## Version History

### v1.0 (November 2025) - Initial Release
- Click and double-click at coordinates
- Accessibility API element finding
- Animated mouse movement
- Text input (type command)
- Keyboard support (press-key command)
- Wait commands (wait, wait-for-app-launch)
- OCR text finding (find-text-ocr)
- Screenshots (full screen and window)
- Element dump with annotated images
- Multi-display support
- Element monitor (manual start)

## Conclusion
Claude Click provides comprehensive UI automation capabilities for testing:
1. Smart UI element discovery and clicking via Accessibility API
2. Complete keyboard input support (text, special keys)
3. Wait commands for testing workflows
4. Visual feedback through animated mouse movement
5. Multi-display support
6. OCR fallback for non-accessible elements
7. Element dumping for debugging
8. Clean, focused functionality in a small binary
9. Integration-ready for automated testing workflows

The combination of smart element finding, keyboard automation, and wait commands makes it ideal for Claude to perform comprehensive UI testing without manual trial and error.
